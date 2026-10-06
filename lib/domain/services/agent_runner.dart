import 'dart:developer' as developer;

import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/agent_template.dart';
import '../tools/tool_definition.dart';
import '../tools/tool_registry.dart';
import 'agent_scope.dart';
import 'agent_validator.dart';
import 'llm_service.dart';
import 'thinking_parser.dart';

sealed class AgentEvent {
  const AgentEvent();
}

final class TraceAdded extends AgentEvent {
  const TraceAdded(this.entry);

  final TraceEntry entry;
}

final class AnswerToken extends AgentEvent {
  const AnswerToken(this.text);

  final String text;
}

final class LogAdded extends AgentEvent {
  const LogAdded(this.entry);

  final AgentLogEntry entry;
}

final class RunFinished extends AgentEvent {
  const RunFinished(this.run);

  final AgentRun run;
}

class AgentRunner {
  const AgentRunner(
    this._llm,
    this._tools,
    this._validator, {
    this.newId,
    this.now,
    this.toolRetries = 1,
  });

  final LlmService _llm;
  final ToolRegistry _tools;
  final AgentValidator _validator;

  /// How many extra times a tool step is asked when the model answered without
  /// reaching for the tool. The first failure is kept in the trace either way —
  /// a model that has to be told twice is a worse model, and this app exists
  /// to see that.
  final int toolRetries;

  final String Function()? newId;

  final DateTime Function()? now;
  static const String _logName = 'AgentRunner';

  Stream<AgentEvent> run(
    AgentTemplate template, {
    required Map<String, String> values,
    required String modelId,
  }) async* {
    final clock = Stopwatch()..start();
    final startedAt = now?.call() ?? DateTime.now();
    final trace = <TraceEntry>[];
    final scope = AgentScope(
      inputs: <String, String>{...template.defaultValues, ...values},
    );

    final availability = await _validator.check(
      template,
      hasModel: _llm.isLoaded,
      values: scope.inputs,
    );
    if (!availability.canRun) {
      for (final blocker in availability.blockers) {
        yield _log('error', blocker, isError: true);
      }
      yield RunFinished(
        _record(
          template: template,
          modelId: modelId,
          startedAt: startedAt,
          clock: clock,
          trace: trace,
          error: availability.firstBlocker,
        ),
      );
      return;
    }

    try {
      await _llm.setSystemPrompt(template.systemPrompt);
      yield _log('system', template.systemPrompt);

      // A reasoning model works the answer out while thinking and then states
      // it, rather than calling the tool it was given. Caught rather than
      // fatal: a template with no such variable should still run, and the log
      // is where that is worth saying.
      try {
        await _llm.setThinking(false);
        yield _log('system', 'Thinking disabled for this run.');
      } catch (error) {
        yield _log(
          'system',
          "This model's template has no enable_thinking: $error",
        );
      }

      for (final step in template.pipeline) {
        await for (final event in _runStep(step, scope, trace)) {
          yield event;
        }
      }
      yield* _runAnswer(template, scope, trace);
    } catch (error, stackTrace) {
      developer.log(
        'Agent ${template.id} stopped early',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      _markLastFailed(trace);
      yield _log('error', '${_describe(error)}\n$stackTrace', isError: true);
      yield RunFinished(
        _record(
          template: template,
          modelId: modelId,
          startedAt: startedAt,
          clock: clock,
          trace: trace,
          output: scope.steps[_answerKey] ?? '',
          error: _describe(error),
        ),
      );
      return;
    }

    yield RunFinished(
      _record(
        template: template,
        modelId: modelId,
        startedAt: startedAt,
        clock: clock,
        trace: trace,
        output: scope.steps[_answerKey] ?? '',
      ),
    );
  }

  static const String _answerKey = ' answer';

  Stream<AgentEvent> _runStep(
    PipelineStep step,
    AgentScope scope,
    List<TraceEntry> trace,
  ) async* {
    final tools = _toolsFor(step);
    final prompt = buildStepPrompt(
      instruction: _instructionFor(step),
      reads: step.reads,
      scope: scope,
    );

    yield _log(
      'step',
      '${step.id} · ${step.kind.label.toLowerCase()} · '
          '${tools.isEmpty ? 'no tools' : tools.first.name}',
    );

    var asked = prompt;
    for (var attempt = 0; ; attempt++) {
      final clock = Stopwatch()..start();
      // Tools before history, which is the order the library's own test uses.
      await _llm.setTools(tools);
      await _llm.resetHistory();

      yield _log('prompt', asked);
      final buffer = StringBuffer();
      await for (final token in _llm.ask(asked)) {
        buffer.write(token);
      }
      clock.stop();

      final raw = buffer.toString().trim();
      yield _log('reply', raw.isEmpty ? '(nothing)' : raw);

      final calls = step.kind == StepKind.tool
          ? await _llm.recentToolCalls()
          : const <ToolInvocation>[];
      for (final call in calls) {
        yield _log('tool', call.name);
        yield _log(
          'args',
          call.rawArguments.isEmpty ? call.arguments : call.rawArguments,
        );
        yield _log('result', call.result.isEmpty ? '(nothing)' : call.result);
      }

      final skipped = step.kind == StepKind.tool && calls.isEmpty;
      final retrying = skipped && attempt < toolRetries;
      if (skipped) {
        yield _log(
          'error',
          'The model answered without calling ${step.tool}.'
              '${retrying ? ' Asking again.' : ''}',
          isError: true,
        );
      }

      if (retrying) {
        // The failed attempt stays in the trace: a model that needs telling
        // twice is a worse model, and hiding that would defeat the point.
        final entry = TraceEntry(
          kind: TraceKind.tool,
          label: '${step.tool} — not called, retrying',
          durationMs: clock.elapsedMilliseconds,
          ok: false,
        );
        trace.add(entry);
        yield TraceAdded(entry);
        asked = _insistOn(step, prompt);
        continue;
      }

      scope.record(step.id, _outputOf(raw, calls));
      for (final entry in _traceFor(step, calls, clock.elapsedMilliseconds)) {
        trace.add(entry);
        yield TraceAdded(entry);
      }
      return;
    }
  }

  /// What a step passes on: its reply with any reasoning removed, or — when a
  /// model called the tool and then said nothing — what the tool returned, so
  /// the next step is not handed a blank.
  static String _outputOf(String raw, List<ToolInvocation> calls) {
    final answer = splitThinking(raw).answer;
    if (answer.isNotEmpty || calls.isEmpty) return answer;
    return <String>[for (final call in calls) call.result].join('\n\n').trim();
  }

  /// The prompt for a second attempt: the original, then a line leaving no
  /// room for the model to answer on its own.
  static String _insistOn(PipelineStep step, String prompt) =>
      '$prompt\n\nYou did not call the ${step.tool} tool. Call it now. Do not '
      'work the answer out yourself and do not answer from memory.';
  Stream<AgentEvent> _runAnswer(
    AgentTemplate template,
    AgentScope scope,
    List<TraceEntry> trace,
  ) async* {
    final clock = Stopwatch()..start();
    await _llm.setTools(const <ToolDefinition>[]);
    await _llm.resetHistory();

    final reads = template.answer.reads.isNotEmpty
        ? template.answer.reads
        : <String>[for (final step in template.pipeline) 'step.${step.id}'];

    final prompt = buildStepPrompt(
      instruction: template.answer.prompt,
      reads: reads,
      scope: scope,
    );
    yield _log('step', 'answer · no tools');
    yield _log('prompt', prompt);

    final buffer = StringBuffer();
    await for (final token in _llm.ask(prompt)) {
      buffer.write(token);
      yield AnswerToken(token);
    }
    clock.stop();
    final raw = buffer.toString().trim();
    // The tokens streamed raw so the screen could fill in as they arrived;
    // what is kept is the answer alone, so the run record, its summary and the
    // history card never carry the model's reasoning. The log keeps the raw
    // text — that is the one place the thinking is worth reading.
    scope.record(_answerKey, splitThinking(raw).answer);
    yield _log('reply', raw.isEmpty ? '(nothing)' : raw);

    final entry = TraceEntry(
      kind: TraceKind.answer,
      label: 'Final answer',
      durationMs: clock.elapsedMilliseconds,
    );
    trace.add(entry);
    yield TraceAdded(entry);
  }

  List<ToolDefinition> _toolsFor(PipelineStep step) {
    if (step.kind != StepKind.tool) return const <ToolDefinition>[];
    final tool = _tools.byName(step.tool ?? '');
    return tool == null ? const <ToolDefinition>[] : <ToolDefinition>[tool];
  }

  String _instructionFor(PipelineStep step) {
    final written = step.prompt?.trim() ?? '';
    if (written.isNotEmpty) return written;

    final tool = _tools.byName(step.tool ?? '');
    if (tool == null) return 'Answer using what you have been given.';
    return 'Use the ${tool.name} tool on what you have been given, then report '
        'what it returned.';
  }

  LogAdded _log(String channel, String text, {bool isError = false}) =>
      LogAdded(
        AgentLogEntry(
          at: now?.call() ?? DateTime.now(),
          channel: channel,
          text: text,
          isError: isError,
        ),
      );

  List<TraceEntry> _traceFor(
    PipelineStep step,
    List<ToolInvocation> calls,
    int elapsedMs,
  ) {
    if (step.kind != StepKind.tool) {
      return <TraceEntry>[
        TraceEntry(
          kind: TraceKind.thought,
          label: _summarise(step.prompt ?? step.id),
          durationMs: elapsedMs,
        ),
      ];
    }

    if (calls.isEmpty) {
      return <TraceEntry>[
        TraceEntry(
          kind: TraceKind.tool,
          label: '${step.tool} — not called',
          durationMs: elapsedMs,
          ok: false,
        ),
      ];
    }

    final each = elapsedMs ~/ calls.length;
    return <TraceEntry>[
      for (final call in calls) ...<TraceEntry>[
        TraceEntry(
          kind: TraceKind.tool,
          label: call.signature,
          durationMs: each,
        ),
        TraceEntry(
          kind: TraceKind.result,
          label: '${call.name} result',
          durationMs: 0,
        ),
      ],
    ];
  }

  AgentRun _record({
    required AgentTemplate template,
    required String modelId,
    required DateTime startedAt,
    required Stopwatch clock,
    required List<TraceEntry> trace,
    String output = '',
    String? error,
  }) {
    clock.stop();
    return AgentRun(
      id: newId?.call() ?? '${template.id}-${startedAt.microsecondsSinceEpoch}',
      agentId: template.id,
      agentName: template.name,
      modelId: modelId,
      startedAt: startedAt,
      durationMs: clock.elapsedMilliseconds,
      trace: List<TraceEntry>.unmodifiable(trace),
      output: output,
      error: error,
    );
  }

  static void _markLastFailed(List<TraceEntry> trace) {
    if (trace.isEmpty) return;
    final last = trace.removeLast();
    trace.add(
      TraceEntry(
        kind: last.kind,
        label: last.label,
        durationMs: last.durationMs,
        ok: false,
      ),
    );
  }

  /// The first line of [text], short enough for a trace row.
  static String _summarise(String text) {
    final first = text.trim().split('\n').first.trim();
    if (first.isEmpty) return 'Think';
    return first.length <= 48 ? first : '${first.substring(0, 47)}…';
  }

  static String _describe(Object error) {
    final text = error.toString().trim();
    return text.isEmpty ? 'The run failed.' : text;
  }
}

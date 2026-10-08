import 'dart:developer' as developer;

import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/agent_template.dart';
import '../tools/tool_definition.dart';
import '../tools/tool_registry.dart';
import 'agent_scope.dart';
import 'agent_validator.dart';
import 'llm_service.dart';
import 'structured_summary.dart';
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
      // `await for` rather than `yield*`, which forwards an error straight to
      // whoever is listening and past the catch below. An answer step that
      // failed used to take the whole stream down with it, so the run was
      // never recorded and the partial answer was lost — unlike a pipeline
      // step failing, which has always been caught here.
      await for (final event in _runAnswer(template, scope, trace)) {
        yield event;
      }
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

  static String _outputOf(String raw, List<ToolInvocation> calls) {
    final answer = splitThinking(raw).answer;
    if (calls.isEmpty) return answer;

    final results = <String>[
      for (final call in calls)
        if (call.result.trim().isNotEmpty) call.result.trim(),
    ];
    if (results.isEmpty) return answer;

    return <String>[...results, if (answer.isNotEmpty) answer].join('\n\n');
  }

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
    // Constrained before the ask and lifted after it, whatever happens. An
    // agent with no schema is left alone entirely rather than handed a null:
    // the sampler it was loaded with is already the one it wants.
    final schema = template.answer.schema;
    final constrained = schema != null && await _constrain(schema);
    if (schema != null && !constrained) {
      yield _log(
        'error',
        'This model would not take the answer schema. Answering without it.',
        isError: true,
      );
    }

    yield _log('step', 'answer · no tools${constrained ? ' · schema' : ''}');
    yield _log('prompt', prompt);

    // Caught and held rather than guarded by `finally`: the tokens have to be
    // yielded as they arrive, and awaiting inside a `finally` that wraps a
    // `yield` is not somewhere to put work that must happen. The constraint
    // is lifted first, then the failure travels on unchanged.
    final buffer = StringBuffer();
    Object? failure;
    StackTrace? failureTrace;
    try {
      await for (final token in _llm.ask(prompt)) {
        buffer.write(token);
        yield AnswerToken(token);
      }
    } catch (error, stackTrace) {
      failure = error;
      failureTrace = stackTrace;
    }

    if (constrained) await _constrain(null);
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace ?? StackTrace.current);
    }
    clock.stop();
    final raw = buffer.toString().trim();
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

  /// Applies [schema] to the next reply, or lifts the constraint when it is
  /// null. Returns whether a constraint is now in force.
  ///
  /// A schema the backend will not compile loses the shape, not the run: the
  /// model is asked the same question unconstrained and whatever it writes is
  /// shown as prose. Which schemas llguidance accepts is not knowable from
  /// here, and an agent that cannot answer at all is worse than one that
  /// answers in the wrong shape.
  Future<bool> _constrain(Map<String, dynamic>? schema) async {
    try {
      await _llm.setResponseSchema(schema);
      return schema != null;
    } catch (error, stackTrace) {
      developer.log(
        'Could not ${schema == null ? 'lift' : 'apply'} the answer schema',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
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
    final view = template.answer.view;
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
      // Both recorded rather than read back off the template later: editing
      // an agent must not change what its finished runs say they did.
      view: template.answer.isStructured ? (view ?? '') : null,
      summaryLine: summariseStructured(view, output),
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

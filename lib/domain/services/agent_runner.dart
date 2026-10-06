import 'dart:developer' as developer;

import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/agent_template.dart';
import '../tools/tool_definition.dart';
import '../tools/tool_registry.dart';
import 'agent_scope.dart';
import 'agent_validator.dart';
import 'llm_service.dart';

/// Something that happened during a run.
///
/// Four kinds, deliberately few. The trace screen appends a row per
/// [TraceAdded], streams the answer from [AnswerToken], collects [LogAdded]
/// for the log sheet, and stops at [RunFinished] — which carries the whole
/// record whether the run succeeded or not, so there is no separate failure
/// event to forget to handle.
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

/// One line for the log sheet. Separate from [TraceAdded] because the two
/// answer different questions: a trace row says *what* a step did and is kept
/// in the run's history, while a log line says what was actually sent and
/// returned and is thrown away when the screen closes.
final class LogAdded extends AgentEvent {
  const LogAdded(this.entry);

  final AgentLogEntry entry;
}

final class RunFinished extends AgentEvent {
  const RunFinished(this.run);

  final AgentRun run;
}

/// Runs one agent.
///
/// The shape of a run is fixed by the template, not decided by the model: the
/// pipeline's steps happen in order, each one is a single turn with exactly
/// one tool in reach or none at all, and the answer step closes it. The model
/// chooses a tool's *arguments* and nothing else. That is what makes a run
/// reproducible enough to compare one model against another, which is the
/// whole point of this app.
///
/// The model is loaded once and used for every step. Steps carry a `model`
/// field that is ignored — swapping weights mid-run means unloading and
/// reloading a gigabyte or so per step, which on a phone is slower than the
/// generation it was meant to improve.
class AgentRunner {
  const AgentRunner(
    this._llm,
    this._tools,
    this._validator, {
    this.newId,
    this.now,
  });

  final LlmService _llm;
  final ToolRegistry _tools;
  final AgentValidator _validator;

  /// Overridden in tests so a run record is comparable; otherwise the id is
  /// built from the agent and the start time.
  final String Function()? newId;

  /// Overridden in tests so `startedAt` is fixed.
  final DateTime Function()? now;

  static const String _logName = 'AgentRunner';

  /// Runs [template] with [values], emitting as it goes.
  ///
  /// The model must already be loaded; [modelId] names it only so the run
  /// record can say which one answered. Loading is the caller's job because
  /// the chat screen and an agent both want the same weights and the same
  /// GPU-to-CPU fallback, and only the view model layer knows the settings
  /// that go into it.
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
      // The template's own prompt, not the user's Chat one: it is what tells
      // the model to call the tool rather than guess, and it is set once here
      // because it survives the history being cleared between steps.
      await _llm.setSystemPrompt(template.systemPrompt);
      yield _log('system', template.systemPrompt);

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

  /// Where the answer's text is kept in the scope. Not a step id a template
  /// can use — the leading space makes it unwritable from JSON, so no step can
  /// collide with it.
  static const String _answerKey = ' answer';

  /// One pipeline step: clear the context, set the one tool it may use, ask,
  /// and record what came back.
  Stream<AgentEvent> _runStep(
    PipelineStep step,
    AgentScope scope,
    List<TraceEntry> trace,
  ) async* {
    final clock = Stopwatch()..start();

    // The context is cleared between steps because the scope, not the chat
    // history, is what carries data forward. A five-step agent would otherwise
    // need a context window holding every tool result at once, which no phone
    // model has; and clearing makes `recentToolCalls` mean this step's calls
    // with nothing to track. The system prompt is kept — it lives outside the
    // history.
    await _llm.resetHistory();
    final tools = _toolsFor(step);
    await _llm.setTools(tools);

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
    yield _log('prompt', prompt);

    final buffer = StringBuffer();
    await for (final token in _llm.ask(prompt)) {
      buffer.write(token);
    }
    final reply = buffer.toString().trim();
    scope.record(step.id, reply);
    clock.stop();

    yield _log('reply', reply.isEmpty ? '(nothing)' : reply);

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
    if (step.kind == StepKind.tool && calls.isEmpty) {
      yield _log(
        'error',
        'The model answered without calling ${step.tool}.',
        isError: true,
      );
    }

    for (final entry in _traceFor(step, calls, clock.elapsedMilliseconds)) {
      trace.add(entry);
      yield TraceAdded(entry);
    }
  }

  /// The closing step: no tools, everything gathered so far, and the answer
  /// streamed token by token so the output panel fills in as it is written.
  Stream<AgentEvent> _runAnswer(
    AgentTemplate template,
    AgentScope scope,
    List<TraceEntry> trace,
  ) async* {
    final clock = Stopwatch()..start();
    await _llm.resetHistory();
    await _llm.setTools(const <ToolDefinition>[]);

    // An answer that names no sources reads every step in order, which is
    // what a summary almost always wants and saves a template repeating the
    // list of its own steps.
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
    final answer = buffer.toString().trim();
    scope.record(_answerKey, answer);
    yield _log('reply', answer.isEmpty ? '(nothing)' : answer);

    final entry = TraceEntry(
      kind: TraceKind.answer,
      label: 'Final answer',
      durationMs: clock.elapsedMilliseconds,
    );
    trace.add(entry);
    yield TraceAdded(entry);
  }

  /// Exactly one tool on a tool step, none on a reason step. One rather than
  /// all of them because a small model handed four tools will reach for the
  /// wrong one; the template already decided which is right here.
  List<ToolDefinition> _toolsFor(PipelineStep step) {
    if (step.kind != StepKind.tool) return const <ToolDefinition>[];
    final tool = _tools.byName(step.tool ?? '');
    return tool == null ? const <ToolDefinition>[] : <ToolDefinition>[tool];
  }

  /// What to ask the model. A tool step may carry no instruction — the builder
  /// shows no field for one — so a usable line is generated from the tool's
  /// own description, which is already written for the model to read.
  String _instructionFor(PipelineStep step) {
    final written = step.prompt?.trim() ?? '';
    if (written.isNotEmpty) return written;

    final tool = _tools.byName(step.tool ?? '');
    if (tool == null) return 'Answer using what you have been given.';
    return 'Use the ${tool.name} tool on what you have been given, then report '
        'what it returned.';
  }

  /// One line for the log sheet, stamped now.
  LogAdded _log(String channel, String text, {bool isError = false}) =>
      LogAdded(
        AgentLogEntry(
          at: now?.call() ?? DateTime.now(),
          channel: channel,
          text: text,
          isError: isError,
        ),
      );

  /// The rows this step adds to the trace, given the [calls] it made.
  ///
  /// A reason step is one `thought` row. A tool step is a `tool` row and a
  /// `result` row per call the model actually made — which may be none, if it
  /// answered without reaching for the tool it was given. That case is worth
  /// seeing rather than hiding: a model ignoring the only tool in reach is
  /// exactly the failure this app is built to measure.
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

    // The step's own time, split evenly: the calls happened inside Rust and
    // arrive without clocks of their own.
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

  /// Marks the row a failure stopped on, so the trace shows where it broke
  /// rather than ending on a row that looks like it succeeded.
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

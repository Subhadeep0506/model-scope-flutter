import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_log.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/domain/services/agent_runner.dart';
import 'package:model_scope_flutter/domain/services/agent_validator.dart';
import 'package:model_scope_flutter/domain/services/llm_service.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/tool_registry.dart';

import '../support/fakes.dart';

void main() {
  /// A registry holding two tools that do nothing. The runner never calls a
  /// tool itself — the model does, inside the backend — so a stand-in with the
  /// right name is all it needs.
  ToolRegistry registryOf(List<String> names) => ToolRegistry(
    tools: <ToolDefinition>[
      for (final name in names)
        ToolDefinition(
          name: name,
          description: 'Does nothing, for a test.',
          function: ({required String input}) async => 'ok',
        ),
    ],
  );

  AgentRunner runnerOver(FakeLlmService llm, {ToolRegistry? tools}) {
    final registry = tools ?? registryOf(<String>['web_search']);
    return AgentRunner(
      llm,
      registry,
      AgentValidator(registry),
      newId: () => 'run-1',
      now: () => DateTime(2026, 10, 6, 9),
    );
  }

  /// A two-step agent: one tool step, one reason step, then the answer.
  AgentTemplate templateOf({
    List<PipelineStep>? pipeline,
    List<AgentInput>? inputs,
    AnswerStep? answer,
  }) => AgentTemplate(
    id: 'test_agent',
    name: 'Test Agent',
    purpose: 'For a test',
    systemPrompt: 'You are careful.',
    inputs:
        inputs ??
        const <AgentInput>[
          AgentInput(
            name: 'query',
            label: 'Query',
            defaultValue: 'dart records',
          ),
        ],
    pipeline:
        pipeline ??
        const <PipelineStep>[
          PipelineStep(
            id: 'search',
            kind: StepKind.tool,
            tool: 'web_search',
            prompt: 'Search for {{input.query}}.',
          ),
          PipelineStep(
            id: 'points',
            kind: StepKind.reason,
            reads: <String>['step.search'],
            prompt: 'List the main points.',
          ),
        ],
    answer: answer ?? const AnswerStep(prompt: 'Write it up.'),
  );

  Future<List<AgentEvent>> runOf(
    AgentRunner runner,
    AgentTemplate template, {
    Map<String, String> values = const <String, String>{},
  }) => runner.run(template, values: values, modelId: 'qwen25-15b').toList();

  AgentRun finishedRun(List<AgentEvent> events) =>
      events.whereType<RunFinished>().single.run;

  group('sequencing', () {
    test('walks the pipeline in order and ends with the answer', () async {
      final llm = FakeLlmService(tokens: <String>['ok'])..loadedForTest();
      final events = await runOf(runnerOver(llm), templateOf());

      // One ask per step, plus the answer.
      check(llm.prompts).length.equals(3);
      check(finishedRun(events).error).isNull();
      check(finishedRun(events).trace.map((entry) => entry.kind).toList())
          .deepEquals(<TraceKind>[
            TraceKind.tool,
            TraceKind.thought,
            TraceKind.answer,
          ]);
    });

    test('hands each step exactly one tool, and the answer none', () async {
      final llm = FakeLlmService()..loadedForTest();

      await runOf(runnerOver(llm), templateOf());

      // One tool on the tool step is the whole point: a small model handed
      // four will reach for the wrong one, and the template already chose.
      check(llm.toolSets).deepEquals(<List<String>>[
        <String>['web_search'],
        <String>[],
        <String>[],
      ]);
    });

    test('clears the context before every step', () async {
      final llm = FakeLlmService()..loadedForTest();

      await runOf(runnerOver(llm), templateOf());

      // Three steps, three resets. Without this a five-step agent would need
      // a context window holding every tool result at once.
      check(llm.resetCalls).equals(3);
    });

    test('carries a step output into the next step', () async {
      final llm = FakeLlmService(tokens: <String>['found'])..loadedForTest();
      llm.scriptedReplies = <List<String>>[
        <String>['two', ' results'],
        <String>['the', ' points'],
        <String>['done'],
      ];

      await runOf(runnerOver(llm), templateOf());

      // The reason step reads `step.search`, so what step one said must be in
      // step two's prompt — that wiring is the whole of the pipeline.
      check(llm.prompts[1]).contains('two results');
      check(llm.prompts[1]).contains('List the main points.');
    });

    test('the answer reads every step when it names none', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedReplies = <List<String>>[
        <String>['SEARCHED'],
        <String>['REASONED'],
        <String>['final'],
      ];

      await runOf(runnerOver(llm), templateOf());

      check(llm.prompts.last).contains('SEARCHED');
      check(llm.prompts.last).contains('REASONED');
    });
  });

  group('inputs', () {
    test('fills placeholders from the values it was given', () async {
      final llm = FakeLlmService()..loadedForTest();

      await runOf(
        runnerOver(llm),
        templateOf(),
        values: <String, String>{'query': 'flutter 4'},
      );

      check(llm.prompts.first).equals('Search for flutter 4.');
    });

    test(
      'falls back to the defaults, which is what Run with defaults does',
      () async {
        final llm = FakeLlmService()..loadedForTest();

        await runOf(runnerOver(llm), templateOf());

        check(llm.prompts.first).equals('Search for dart records.');
      },
    );

    test(
      'a required input with no value stops the run before it starts',
      () async {
        final llm = FakeLlmService()..loadedForTest();
        final template = templateOf(
          inputs: const <AgentInput>[AgentInput(name: 'query', label: 'Query')],
        );

        final run = finishedRun(await runOf(runnerOver(llm), template));

        check(run.error).isNotNull();
        check(run.error).isNotNull().contains('Query needs a value');
        check(llm.prompts).isEmpty();
      },
    );
  });

  group('the trace', () {
    test('names the tool and the arguments the model chose', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedToolCalls = <int, List<ToolInvocation>>{
        0: <ToolInvocation>[
          const ToolInvocation(
            name: 'web_search',
            arguments: '"dart records"',
            result: 'Results for dart records',
          ),
        ],
      };

      final run = finishedRun(await runOf(runnerOver(llm), templateOf()));

      check(run.trace.first.label).equals('web_search("dart records")');
      check(run.trace[1].kind).equals(TraceKind.result);
      check(run.trace[1].label).equals('web_search result');
    });

    test('records a tool step where the model never called the tool', () async {
      final llm = FakeLlmService()..loadedForTest();

      final run = finishedRun(await runOf(runnerOver(llm), templateOf()));

      // A model ignoring the only tool in reach is exactly the failure this
      // app is built to measure, so it is shown rather than hidden.
      check(run.trace.first.label).equals('web_search — not called');
      check(run.trace.first.ok).isFalse();
    });

    test('streams the answer token by token', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedReplies = <List<String>>[
        <String>['a'],
        <String>['b'],
        <String>['Hello', ' ', 'world'],
      ];

      final events = await runOf(runnerOver(llm), templateOf());

      check(events.whereType<AnswerToken>().map((e) => e.text).toList())
          .deepEquals(<String>['Hello', ' ', 'world']);
      check(finishedRun(events).output).equals('Hello world');
    });
  });

  group('failures', () {
    test(
      'a failing step ends the run with the trace gathered so far',
      () async {
        final llm = FakeLlmService()..loadedForTest();
        llm.askFailure = (ask) =>
            ask == 1 ? StateError('the model gave up') : null;

        final run = finishedRun(await runOf(runnerOver(llm), templateOf()));

        check(run.error).isNotNull().contains('gave up');
        // The first step finished, so its rows are kept; the last is marked.
        check(run.trace).length.equals(1);
        check(run.trace.last.ok).isFalse();
      },
    );

    test('an unknown tool stops the run and says so', () async {
      final llm = FakeLlmService()..loadedForTest();
      final template = templateOf(
        pipeline: const <PipelineStep>[
          PipelineStep(
            id: 'parse',
            kind: StepKind.tool,
            tool: 'pdf_parse',
            prompt: 'Read it.',
          ),
        ],
      );

      final run = finishedRun(await runOf(runnerOver(llm), template));

      check(run.error).isNotNull().contains('pdf_parse');
      check(llm.prompts).isEmpty();
    });

    test('no model loaded stops the run', () async {
      final llm = FakeLlmService();

      final run = finishedRun(await runOf(runnerOver(llm), templateOf()));

      check(run.error).isNotNull().contains('No model installed');
    });
  });

  test('the run record carries what the history card prints', () async {
    final llm = FakeLlmService()..loadedForTest();
    llm.scriptedReplies = <List<String>>[
      <String>['a'],
      <String>['b'],
      <String>['Kolkata 31°C · Berlin 17°C', '\nmore detail'],
    ];

    final run = finishedRun(await runOf(runnerOver(llm), templateOf()));

    check(run.id).equals('run-1');
    check(run.agentName).equals('Test Agent');
    check(run.startedAt).equals(DateTime(2026, 10, 6, 9));
    check(run.summary).equals('Kolkata 31°C · Berlin 17°C');
    check(run.statsLabel).startsWith('qwen25-15b · 3 steps · ');
  });

  group('the system prompt', () {
    test("sets the agent's own prompt once, before the first step", () async {
      final llm = FakeLlmService()..loadedForTest();

      await runOf(runnerOver(llm), templateOf());

      // Once, not per step: it lives outside the history, so clearing the
      // context between steps leaves it in place.
      check(llm.systemPrompts).deepEquals(<String>['You are careful.']);
    });

    test('is not set when the run is blocked before it starts', () async {
      final llm = FakeLlmService();

      await runOf(runnerOver(llm), templateOf());

      check(llm.systemPrompts).isEmpty();
    });
  });

  group('the log', () {
    List<AgentLogEntry> logsOf(List<AgentEvent> events) =>
        events.whereType<LogAdded>().map((event) => event.entry).toList();

    List<String> textOn(List<AgentLogEntry> logs, String channel) => <String>[
      for (final entry in logs)
        if (entry.channel == channel) entry.text,
    ];

    test('carries the whole prompt each step was actually sent', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedReplies = <List<String>>[
        <String>['two results'],
        <String>['the points'],
        <String>['done'],
      ];

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));

      // Exactly what went to the model, including the blocks a step read —
      // which is the only way to tell a bad answer from a bad prompt.
      check(textOn(logs, 'prompt')).deepEquals(llm.prompts);
      check(textOn(logs, 'prompt')[1]).contains('two results');
    });

    test('carries the raw reply each step produced', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedReplies = <List<String>>[
        <String>['SEARCHED'],
        <String>['REASONED'],
        <String>['ANSWERED'],
      ];

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));

      check(textOn(logs, 'reply'))
          .deepEquals(<String>['SEARCHED', 'REASONED', 'ANSWERED']);
    });

    test('names the tool, its arguments and the whole result', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.scriptedToolCalls = <int, List<ToolInvocation>>{
        0: <ToolInvocation>[
          const ToolInvocation(
            name: 'web_search',
            arguments: '"dart records"',
            rawArguments: '{"query": "dart records"}',
            result: 'A long page of results …',
          ),
        ],
      };

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));

      check(textOn(logs, 'tool')).deepEquals(<String>['web_search']);
      // The names are kept here, unlike on the trace row: a model passing the
      // right value under the wrong name is a failure worth seeing.
      check(textOn(logs, 'args'))
          .deepEquals(<String>['{"query": "dart records"}']);
      check(textOn(logs, 'result'))
          .deepEquals(<String>['A long page of results …']);
    });

    test('marks a tool step where the model never called the tool', () async {
      final llm = FakeLlmService()..loadedForTest();

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));
      final failures = logs.where((entry) => entry.isError).toList();

      check(failures).length.equals(1);
      check(failures.single.text).contains('without calling web_search');
    });

    test('ends on the error when a step throws', () async {
      final llm = FakeLlmService()..loadedForTest();
      llm.askFailure = (ask) =>
          ask == 1 ? StateError('the model gave up') : null;

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));

      check(logs.last.isError).isTrue();
      check(logs.last.text).contains('gave up');
    });

    test('says what blocked a run that never started', () async {
      final llm = FakeLlmService();

      final logs = logsOf(await runOf(runnerOver(llm), templateOf()));

      check(logs).length.equals(1);
      check(logs.single.text).contains('No model installed');
      check(logs.single.isError).isTrue();
    });
  });
}

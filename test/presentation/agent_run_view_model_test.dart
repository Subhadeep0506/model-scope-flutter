import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/view_models/agent_run_state.dart';
import 'package:model_scope_flutter/presentation/view_models/agent_run_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmService llm;
  late FakeAgentRunRepository history;

  ProviderContainer containerWith({
    List<ModelDescriptor>? models,
    List<AgentRun>? runs,
    AppSettings? appSettings,
    List<String> needingKeys = const <String>[],
  }) {
    llm = FakeLlmService();
    history = FakeAgentRunRepository(runs);
    return ProviderContainer.test(
      overrides: fakeOverrides(
        llm: llm,
        sessions: FakeSessionRepository(),
        library: FakeModelLibraryRepository.of(
          models ?? <ModelDescriptor>[fakeInstalledModel()],
        ),
        appSettings: FakeAppSettingsRepository(
          appSettings ?? const AppSettings(),
        ),
        agents: FakeAgentRepository(<Agent>[
          Agent(template: fakeAgentTemplate(), isBuiltIn: true),
        ]),
        agentRuns: history,
        tools: fakeToolRegistry(needingKeys: needingKeys),
      ),
    );
  }

  AgentRunViewModel notifierOf(ProviderContainer c) =>
      c.read(agentRunViewModelProvider.notifier);

  AgentRunState stateOf(ProviderContainer c) =>
      c.read(agentRunViewModelProvider);

  group('opening', () {
    test('reads the agent without loading any weights', () async {
      final container = containerWith();

      await notifierOf(container).open('test_agent');

      // The model loads when Run is pressed and not before — the point of
      // opening an agent is to read what it does, which costs nothing.
      check(llm.loadCalls).equals(0);
      check(stateOf(container).status).equals(AgentRunStatus.idle);
      check(stateOf(container).agent?.id).equals('test_agent');
    });

    test('seeds the inputs from the defaults', () async {
      final container = containerWith();

      await notifierOf(container).open('test_agent');

      check(stateOf(container).values)
          .deepEquals(<String, String>{'query': 'dart records'});
      check(stateOf(container).usesDefaults).isTrue();
    });

    test('editing an input is what makes a run "configured"', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      notifierOf(container).setValue('query', 'flutter 4');

      check(stateOf(container).usesDefaults).isFalse();
    });

    test('starts on the model active in Settings', () async {
      final container = containerWith(
        models: <ModelDescriptor>[
          fakeInstalledModel(fileName: 'a.gguf', name: 'A'),
          fakeInstalledModel(fileName: 'b.gguf', name: 'B'),
        ],
      );

      await notifierOf(container).open('test_agent');

      check(stateOf(container).modelId).isNotNull().endsWith('a.gguf');
      check(stateOf(container).installed).length.equals(2);
    });

    test('lists only this agent’s runs', () async {
      final container = containerWith(
        runs: <AgentRun>[
          fakeAgentRun(id: 'mine', agentId: 'test_agent'),
          fakeAgentRun(id: 'theirs', agentId: 'other'),
        ],
      );

      await notifierOf(container).open('test_agent');

      check(stateOf(container).history.map((run) => run.id).toList())
          .deepEquals(<String>['mine']);
    });

    test('a missing tool key blocks the run button', () async {
      final container = containerWith(needingKeys: <String>['web_search']);

      await notifierOf(container).open('test_agent');

      check(stateOf(container).status).equals(AgentRunStatus.blocked);
      check(stateOf(container).error).isNotNull().contains('web_search key');
    });

    test('an agent that is not there says so', () async {
      final container = containerWith();

      await notifierOf(container).open('gone');

      check(stateOf(container).status).equals(AgentRunStatus.failed);
      check(stateOf(container).error).isNotNull().contains('no longer exists');
    });
  });

  group('running', () {
    test('loads the model once, then walks the pipeline', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      check(llm.loadCalls).equals(1);
      // One ask for the tool step, one for the answer.
      check(llm.prompts).length.equals(2);
      check(stateOf(container).status).equals(AgentRunStatus.finished);
    });

    test('runs on the model picked here, not the active one', () async {
      final container = containerWith(
        models: <ModelDescriptor>[
          fakeInstalledModel(fileName: 'a.gguf', name: 'A'),
          fakeInstalledModel(fileName: 'b.gguf', name: 'B'),
        ],
      );
      await notifierOf(container).open('test_agent');
      final second = stateOf(container).installed[1];

      notifierOf(container).selectModel(second.id);
      await notifierOf(container).run();
      await pumpEventQueue();

      check(history.stored.single.modelId).equals(second.id);
      // The library is untouched: picking a model to compare agents on should
      // not keep rewriting what Chat answers with.
      final library = await container.read(
        modelLibraryViewModelProvider.future,
      );
      check(library.activeId).isNotNull().endsWith('a.gguf');
    });

    test('gathers the trace, the output and the log', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');
      llm.scriptedReplies = <List<String>>[
        <String>['searched'],
        <String>['Dart ', 'records'],
      ];

      await notifierOf(container).run();
      await pumpEventQueue();

      final state = stateOf(container);
      check(state.visibleTrace).length.equals(2);
      check(state.visibleOutput).equals('Dart records');
      check(state.logs).isNotEmpty();
      // The load is logged here, before the runner has anything to say.
      check(state.logs.first.channel).equals('load');
    });

    test('saves the run and refreshes what counts runs', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      check(history.stored).length.equals(1);
      check(history.stored.single.agentId).equals('test_agent');
      check(stateOf(container).history.first.agentId).equals('test_agent');
    });

    test('releases the model when the run ends', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      // Held only for as long as a run needs it, so nothing of the agent's —
      // its system prompt, its tools — is left on a model Chat picks up.
      check(llm.disposeCalls).equals(1);
      check(llm.isLoaded).isFalse();
    });

    test('drops GPU offload rather than giving up', () async {
      final container = containerWith(
        appSettings: const AppSettings(useGpu: true),
      );
      await notifierOf(container).open('test_agent');
      llm.loadFailure = (runtime) =>
          runtime.useGpu ? StateError('no GPU here') : null;

      await notifierOf(container).run();
      await pumpEventQueue();

      check(llm.loadCalls).equals(2);
      check(llm.runtimes.last.useGpu).isFalse();
      check(stateOf(container).notice).isNotNull().contains('CPU');
    });

    test('a load that fails outright ends the run and says why', () async {
      final container = containerWith(
        appSettings: const AppSettings(useGpu: false),
      );
      await notifierOf(container).open('test_agent');
      llm.loadFailure = (_) => StateError('the weights are gone');

      await notifierOf(container).run();
      await pumpEventQueue();

      check(stateOf(container).status).equals(AgentRunStatus.finished);
      check(stateOf(container).error).isNotNull().contains('weights are gone');
      check(llm.prompts).isEmpty();
    });

    test('with nothing installed it refuses before loading', () async {
      final container = containerWith(models: const <ModelDescriptor>[]);
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      check(llm.loadCalls).equals(0);
      check(stateOf(container).status).equals(AgentRunStatus.blocked);
    });
  });

  group('stopping', () {
    test('records what the run managed and releases the model', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');
      // Slow enough that the run is still going when stop lands.
      llm.gap = const Duration(milliseconds: 20);

      await notifierOf(container).run();
      await notifierOf(container).stop();

      check(llm.stopCalls).isGreaterThan(0);
      check(history.stored).length.equals(1);
      check(history.stored.single.error)
          .isNotNull()
          .contains('Stopped before it finished');
      check(llm.disposeCalls).equals(1);
      check(stateOf(container).status).equals(AgentRunStatus.finished);
    });

    test('does nothing when no run is going', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      await notifierOf(container).stop();

      check(history.stored).isEmpty();
      check(llm.stopCalls).equals(0);
    });

    test('leaving the screen mid-run releases the model too', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');
      llm.gap = const Duration(milliseconds: 20);

      await notifierOf(container).run();
      notifierOf(container).close();
      await pumpEventQueue();

      // Left loaded, the weights would still carry the agent's system prompt
      // and tools, and Chat would answer the next question as the agent.
      check(llm.disposeCalls).equals(1);
      check(history.stored).length.equals(1);
      check(history.stored.single.agentId).equals('test_agent');
      check(stateOf(container).agent).isNull();
    });

    test('closing an idle screen touches nothing', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      notifierOf(container).close();
      await pumpEventQueue();

      check(llm.disposeCalls).equals(0);
      check(history.stored).isEmpty();
    });
  });

  group('looking back', () {
    test('opening a past run shows its trace and output', () async {
      final past = fakeAgentRun(
        agentId: 'test_agent',
        output: 'what it said then',
      );
      final container = containerWith(runs: <AgentRun>[past]);
      await notifierOf(container).open('test_agent');

      notifierOf(container).openRun(past);

      final state = stateOf(container);
      check(state.showsRun).isTrue();
      check(state.visibleOutput).equals('what it said then');
      check(state.visibleTrace).length.equals(2);
      check(state.traceTotalLabel).equals('4.24s total');
    });

    test('going back clears the run and leaves the inputs', () async {
      final past = fakeAgentRun(agentId: 'test_agent');
      final container = containerWith(runs: <AgentRun>[past]);
      await notifierOf(container).open('test_agent');
      notifierOf(container).openRun(past);

      notifierOf(container).backToIdle();

      check(stateOf(container).showsRun).isFalse();
      check(stateOf(container).status).equals(AgentRunStatus.idle);
      check(stateOf(container).values)
          .deepEquals(<String, String>{'query': 'dart records'});
    });
  });
}

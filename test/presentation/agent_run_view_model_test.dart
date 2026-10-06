import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
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
    SamplerSettings? sampler,
    AgentTemplate? template,
    FakeCatalogRepository? catalog,
    List<String> needingKeys = const <String>[],
  }) {
    llm = FakeLlmService();
    history = FakeAgentRunRepository(runs);
    return ProviderContainer.test(
      overrides: fakeOverrides(
        llm: llm,
        sessions: FakeSessionRepository(),
        settings: FakeSettingsRepository(sampler ?? const SamplerSettings()),
        library: FakeModelLibraryRepository.of(
          models ?? <ModelDescriptor>[fakeInstalledModel()],
        ),
        appSettings: FakeAppSettingsRepository(
          appSettings ?? const AppSettings(),
        ),
        agents: FakeAgentRepository(<Agent>[
          Agent(template: template ?? fakeAgentTemplate(), isBuiltIn: true),
        ]),
        agentRuns: history,
        tools: fakeToolRegistry(needingKeys: needingKeys),
        // The shared default is text-only and shares a repository id with the
        // default installed model, which would warn in every test here.
        catalog: catalog ?? toolCapableCatalog(),
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

    test('warns when the model is not marked for tool calling', () async {
      final container = containerWith(
        models: <ModelDescriptor>[
          fakeInstalledModel(repoId: 'ggml-org/gemma-3-1b-it-GGUF'),
        ],
        catalog: FakeCatalogRepository(
          models: <CatalogModel>[
            fakeCatalogModel(
              repoId: 'ggml-org/gemma-3-1b-it-GGUF',
              name: 'Gemma 3 1B',
              capabilities: const <ModelCapability>[ModelCapability.textToText],
            ),
          ],
        ),
      );

      await notifierOf(container).open('test_agent');

      // A warning, not a blocker: watching a model fail to reach for a tool
      // is a legitimate thing to want to see here.
      check(stateOf(container).toolWarning)
          .isNotNull()
          .contains('Gemma 3 1B is not marked as tool-calling');
      check(stateOf(container).status).equals(AgentRunStatus.idle);
      check(stateOf(container).canRun).isTrue();
    });

    test('a tool-calling model draws no warning', () async {
      final container = containerWith();

      await notifierOf(container).open('test_agent');

      check(stateOf(container).toolWarning).isNull();
    });

    test('an agent that names no tools is never warned about', () async {
      final container = containerWith(
        template: fakeAgentTemplate(
          pipeline: const <PipelineStep>[
            PipelineStep(
              id: 'think',
              kind: StepKind.reason,
              prompt: 'Think about {{input.query}}.',
            ),
          ],
        ),
        models: <ModelDescriptor>[
          fakeInstalledModel(repoId: 'ggml-org/gemma-3-1b-it-GGUF'),
        ],
        catalog: FakeCatalogRepository(
          models: <CatalogModel>[
            fakeCatalogModel(
              repoId: 'ggml-org/gemma-3-1b-it-GGUF',
              capabilities: const <ModelCapability>[ModelCapability.textToText],
            ),
          ],
        ),
      );

      await notifierOf(container).open('test_agent');

      check(stateOf(container).toolWarning).isNull();
    });

    test('switching to a capable model clears the warning', () async {
      final container = containerWith(
        models: <ModelDescriptor>[
          fakeInstalledModel(repoId: 'ggml-org/gemma-3-1b-it-GGUF'),
          fakeInstalledModel(
            repoId: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
            fileName: 'qwen.gguf',
          ),
        ],
        catalog: FakeCatalogRepository(
          models: <CatalogModel>[
            fakeCatalogModel(
              repoId: 'ggml-org/gemma-3-1b-it-GGUF',
              capabilities: const <ModelCapability>[ModelCapability.textToText],
            ),
            fakeCatalogModel(
              repoId: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
              capabilities: const <ModelCapability>[
                ModelCapability.textToText,
                ModelCapability.toolCalling,
              ],
            ),
          ],
        ),
      );
      await notifierOf(container).open('test_agent');
      check(stateOf(container).toolWarning).isNotNull();

      await notifierOf(container)
          .selectModel(stateOf(container).installed[1].id);

      check(stateOf(container).toolWarning).isNull();
    });

    test('a model the catalog does not list is not warned about', () async {
      // Sideloaded, or installed by an older build. This cannot tell "cannot
      // call tools" from "unknown", so it says nothing.
      final container = containerWith(
        models: <ModelDescriptor>[fakeInstalledModel(repoId: 'someone/else')],
        catalog: FakeCatalogRepository(models: <CatalogModel>[]),
      );

      await notifierOf(container).open('test_agent');

      check(stateOf(container).toolWarning).isNull();
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
      llm.scriptedToolCalls = toolCalledOn();

      await notifierOf(container).run();
      await pumpEventQueue();

      check(llm.loadCalls).equals(1);
      // One ask for the tool step, one for the answer.
      check(llm.prompts).length.equals(2);
      check(stateOf(container).status).equals(AgentRunStatus.finished);
    });

    test('a step that skips its tool is asked again', () async {
      final container = containerWith();
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      // The fake never reports a call, so the tool step is asked twice before
      // the answer — the retry the runner does by default.
      check(llm.prompts).length.equals(3);
      check(llm.prompts[1]).contains('You did not call the web_search tool');
    });

    test('samples low whatever the Chat sliders say', () async {
      final container = containerWith(
        sampler: const SamplerSettings(temperature: 1.8),
      );
      await notifierOf(container).open('test_agent');

      await notifierOf(container).run();
      await pumpEventQueue();

      // A step is instruction-following, and two runs of one agent should
      // differ because of the model rather than the sampler.
      check(llm.applied.single.temperature)
          .equals(SamplerSettings.agentTemperature);
      check(llm.applied.single.maxTokens).equals(512);
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
      llm.scriptedToolCalls = toolCalledOn();
      llm.scriptedReplies = <List<String>>[
        <String>['searched'],
        <String>['Dart ', 'records'],
      ];

      await notifierOf(container).run();
      await pumpEventQueue();

      final state = stateOf(container);
      // A tool row, its result row, and the answer.
      check(state.visibleTrace).length.equals(3);
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

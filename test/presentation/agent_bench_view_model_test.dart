import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/view_models/agent_bench_state.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith({
    List<Agent>? agents,
    List<AgentRun>? runs,
    List<ModelDescriptor>? models,
    List<String> needingKeys = const <String>[],
  }) => ProviderContainer.test(
    overrides: fakeOverrides(
      llm: FakeLlmService(),
      sessions: FakeSessionRepository(),
      library: FakeModelLibraryRepository.of(
        models ?? <ModelDescriptor>[fakeInstalledModel()],
      ),
      agents: FakeAgentRepository(
        agents ??
            <Agent>[Agent(template: fakeAgentTemplate(), isBuiltIn: true)],
      ),
      agentRuns: FakeAgentRunRepository(runs),
      tools: fakeToolRegistry(needingKeys: needingKeys),
    ),
  );

  Future<AgentBenchState> benchOf(ProviderContainer c) =>
      c.read(agentBenchViewModelProvider.future);

  test('splits custom agents from built-in ones', () async {
    final bench = await benchOf(
      containerWith(
        agents: <Agent>[
          Agent(
            template: fakeAgentTemplate(id: 'mine', name: 'Mine'),
            isBuiltIn: false,
          ),
          Agent(
            template: fakeAgentTemplate(id: 'shipped', name: 'Shipped'),
            isBuiltIn: true,
          ),
        ],
      ),
    );

    check(bench.custom.map((l) => l.id).toList()).deepEquals(<String>['mine']);
    check(bench.builtIn.map((l) => l.id).toList())
        .deepEquals(<String>['shipped']);
    check(bench.agentCount).equals(2);
  });

  test('matches the last run to the agent that produced it', () async {
    final bench = await benchOf(
      containerWith(
        agents: <Agent>[
          Agent(template: fakeAgentTemplate(id: 'a'), isBuiltIn: true),
          Agent(template: fakeAgentTemplate(id: 'b'), isBuiltIn: true),
        ],
        // Newest first, as the repository keeps it.
        runs: <AgentRun>[
          fakeAgentRun(id: 'r3', agentId: 'a', output: 'newest'),
          fakeAgentRun(id: 'r2', agentId: 'a', output: 'older'),
          fakeAgentRun(id: 'r1', agentId: 'b', output: 'other agent'),
        ],
      ),
    );

    check(bench.builtIn.first.lastRun?.id).equals('r3');
    check(bench.builtIn[1].lastRun?.id).equals('r1');
  });

  test('an agent that has never run carries no run', () async {
    final bench = await benchOf(containerWith());

    check(bench.builtIn.single.lastRun).isNull();
    check(bench.builtIn.single.canRun).isTrue();
  });

  test('a tool with no key blocks the agent that names it', () async {
    final bench = await benchOf(
      containerWith(needingKeys: <String>['web_search']),
    );

    // Said on the card rather than three taps in — a fresh install should be
    // able to see which agents it can actually run.
    check(bench.builtIn.single.blocker).isNotNull().contains('web_search key');
    check(bench.builtIn.single.canRun).isFalse();
  });

  test('no model installed blocks every agent', () async {
    final bench = await benchOf(
      containerWith(models: const <ModelDescriptor>[]),
    );

    check(bench.builtIn.single.blocker)
        .isNotNull()
        .contains('No model installed');
  });

  test('the tiles count the runs, their mean and the tools', () async {
    final bench = await benchOf(
      containerWith(
        runs: <AgentRun>[
          fakeAgentRun(id: 'r1', durationMs: 4000),
          fakeAgentRun(id: 'r2', durationMs: 5000),
        ],
      ),
    );

    check(bench.runCount).equals(2);
    check(bench.averageRunMs).equals(4500);
    check(bench.averageRunLabel).equals('4.50s');
    check(bench.toolCount).equals(5);
  });

  test('an empty bench reports zeroes rather than failing', () async {
    final bench = await benchOf(containerWith(agents: <Agent>[]));

    check(bench.agentCount).equals(0);
    check(bench.runCount).equals(0);
    check(bench.averageRunLabel).equals('0.00s');
  });
}

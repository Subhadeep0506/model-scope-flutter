import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:model_scope_flutter/config/router/app_router.dart';
import 'package:model_scope_flutter/config/theme/app_theme.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/screens/agent_bench_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/stat_tile.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  List<Agent> twoAgents() => <Agent>[
    Agent(
      template: fakeAgentTemplate(
        id: 'web_answer',
        name: 'Web Answer',
        purpose: 'Answer one question from a live web search',
      ),
      isBuiltIn: true,
    ),
    Agent(
      template: fakeAgentTemplate(
        id: 'tool_stress_test',
        name: 'Tool-Calling Stress Test',
        purpose: 'Score agentic reliability under tricky prompts',
      ),
      isBuiltIn: true,
    ),
  ];

  Future<void> pumpBench(
    WidgetTester tester, {
    List<Agent>? agents,
    List<AgentRun>? runs,
    List<ModelDescriptor>? models,
    List<String> needingKeys = const <String>[],
  }) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        const AgentBenchScreen(),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          library: FakeModelLibraryRepository.of(
            models ?? <ModelDescriptor>[fakeInstalledModel()],
          ),
          agents: FakeAgentRepository(agents ?? twoAgents()),
          agentRuns: FakeAgentRunRepository(runs),
          tools: fakeToolRegistry(needingKeys: needingKeys),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tile(String label) =>
      find.byWidgetPredicate((w) => w is StatTile && w.label == label);

  String valueOf(WidgetTester tester, String label) =>
      tester.widget<StatTile>(tile(label)).value;

  testWidgets('heads the screen with the agent count', (tester) async {
    await pumpBench(tester);

    check(find.text('2 AGENTS AVAILABLE').evaluate()).isNotEmpty();
    check(find.text('Agent bench').evaluate()).isNotEmpty();
  });

  testWidgets('draws the three figures above the list', (tester) async {
    await pumpBench(
      tester,
      runs: <AgentRun>[
        fakeAgentRun(id: 'r1', agentId: 'web_answer', durationMs: 4000),
        fakeAgentRun(id: 'r2', agentId: 'web_answer', durationMs: 5000),
      ],
    );

    check(valueOf(tester, 'RUNS')).equals('2');
    check(valueOf(tester, 'AVG RUN')).equals('4.50s');
    check(valueOf(tester, 'TOOLS')).equals('5');
  });

  testWidgets('lists each agent with its tools', (tester) async {
    await pumpBench(tester);

    check(find.text('Web Answer').evaluate()).isNotEmpty();
    check(find.text('Answer one question from a live web search').evaluate())
        .isNotEmpty();
    // The mono chips name every tool the pipeline reaches for.
    check(find.text('web_search').evaluate()).isNotEmpty();
  });

  testWidgets('an agent that has never run says so', (tester) async {
    await pumpBench(tester);

    check(find.text('never run').evaluate()).length.equals(2);
  });

  testWidgets('a card that has run shows when, and what it said', (
    tester,
  ) async {
    await pumpBench(
      tester,
      runs: <AgentRun>[
        fakeAgentRun(
          agentId: 'web_answer',
          startedAt: DateTime.now().subtract(const Duration(hours: 4)),
          output: 'Flutter 3.38 is current.',
        ),
      ],
    );

    check(find.textContaining('last run 4h ago · Flutter 3.38').evaluate())
        .isNotEmpty();
  });

  testWidgets('a missing key is said on the card itself', (tester) async {
    await pumpBench(tester, needingKeys: <String>['web_search']);

    check(find.textContaining('Needs web_search key').evaluate()).isNotEmpty();
  });

  testWidgets('with nothing installed every card says so', (tester) async {
    await pumpBench(tester, models: const <ModelDescriptor>[]);

    check(find.textContaining('No model installed').evaluate()).isNotEmpty();
  });

  testWidgets('the custom section invites the user to build one', (
    tester,
  ) async {
    await pumpBench(tester);

    check(find.text('My agents').evaluate()).isNotEmpty();
    check(find.text('No custom agents yet — build one from tools').evaluate())
        .isNotEmpty();
    check(find.text('Built-in').evaluate()).isNotEmpty();
  });

  testWidgets('tapping a card opens that agent', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // A stand-in at the detail path, so this asserts where the bench sends
    // the user rather than what the detail screen renders.
    final router = GoRouter(
      initialLocation: Routes.agent,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.agent,
          builder: (_, _) => const AgentBenchScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          agents: FakeAgentRepository(twoAgents()),
        ),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Web Answer'));
    await tester.pumpAndSettle();

    check(find.text('Opened web_answer').evaluate()).isNotEmpty();
    check(router.state.matchedLocation).equals('/agent/web_answer');
  });
}

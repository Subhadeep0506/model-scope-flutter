import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/screens/agent_detail_screen.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeLlmService llm;
  late FakeAgentRunRepository history;

  Future<void> pumpDetail(
    WidgetTester tester, {
    List<AgentRun>? runs,
    List<ModelDescriptor>? models,
    List<String> needingKeys = const <String>[],
    FakeCatalogRepository? catalog,
    String agentId = 'test_agent',
  }) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    llm = FakeLlmService();
    history = FakeAgentRunRepository(runs);

    await tester.pumpWidget(
      harness(
        AgentDetailScreen(agentId: agentId),
        overrides: fakeOverrides(
          llm: llm,
          sessions: FakeSessionRepository(),
          library: FakeModelLibraryRepository.of(
            models ?? <ModelDescriptor>[fakeInstalledModel()],
          ),
          agents: FakeAgentRepository(<Agent>[
            Agent(template: fakeAgentTemplate(), isBuiltIn: true),
          ]),
          agentRuns: history,
          tools: fakeToolRegistry(needingKeys: needingKeys),
          catalog: catalog ?? toolCapableCatalog(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('heads the screen with the tools and the name', (tester) async {
    await pumpDetail(tester);

    check(find.text('WEB_SEARCH').evaluate()).isNotEmpty();
    check(find.text('Test Agent').evaluate()).isNotEmpty();
    check(find.text('A test agent that searches and then answers.').evaluate())
        .isNotEmpty();
  });

  testWidgets('offers the model and the inputs before a run', (tester) async {
    await pumpDetail(tester);

    check(find.text('MODEL').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(find.text('Configure inputs').evaluate()).isNotEmpty();
  });

  testWidgets('the button says it will run the defaults', (tester) async {
    await pumpDetail(tester);

    check(find.text('Run with defaults').evaluate()).isNotEmpty();
  });

  testWidgets('editing an input flips the button to Run configured', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(find.text('Configure inputs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'flutter 4');
    await tester.pumpAndSettle();

    check(find.text('Run configured').evaluate()).isNotEmpty();
    check(find.text('Run with defaults').evaluate()).isEmpty();
  });

  testWidgets('a blocked agent cannot be run and says why', (tester) async {
    await pumpDetail(tester, needingKeys: <String>['web_search']);

    check(find.textContaining('Needs web_search key').evaluate()).isNotEmpty();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    check(button.onPressed).isNull();
  });

  testWidgets('running draws the trace and the output', (tester) async {
    await pumpDetail(tester);
    llm.scriptedToolCalls = toolCalledOn();
    llm.scriptedReplies = <List<String>>[
      <String>['searched'],
      <String>['Dart ', 'records ', 'are tuples.'],
    ];

    await tester.tap(find.text('Run with defaults'));
    await tester.pumpAndSettle();

    check(find.text('TRACE').evaluate()).isNotEmpty();
    check(find.text('OUTPUT').evaluate()).isNotEmpty();
    check(find.textContaining('Dart records are tuples.').evaluate())
        .isNotEmpty();
    // The configuration collapses away so the trace has the screen.
    check(find.text('Configure inputs').evaluate()).isEmpty();
    check(find.text('MODEL').evaluate()).isEmpty();
  });

  testWidgets('Show logs opens the sheet with what was sent', (tester) async {
    await pumpDetail(tester);
    llm.scriptedReplies = <List<String>>[
      <String>['searched'],
      <String>['answered'],
    ];

    await tester.tap(find.text('Run with defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show logs'));
    await tester.pumpAndSettle();

    check(find.text('Run log').evaluate()).isNotEmpty();
    // The exact prompt the step was sent, which is what the trace cannot say.
    check(find.text('Search for dart records.').evaluate()).isNotEmpty();
    check(find.text('prompt').evaluate()).isNotEmpty();
    check(find.text('Copy all').evaluate()).isNotEmpty();
  });

  testWidgets('a finished run joins the history', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('Run with defaults'));
    await tester.pumpAndSettle();

    check(history.stored).length.equals(1);
    check(history.stored.single.agentId).equals('test_agent');
  });

  testWidgets('a past run is listed and opens read-only', (tester) async {
    await pumpDetail(
      tester,
      runs: <AgentRun>[
        fakeAgentRun(agentId: 'test_agent', output: 'what it said then'),
      ],
    );

    // The card's title is the run's first line of output.
    check(find.text('RUN HISTORY').evaluate()).isNotEmpty();
    check(find.text('TRACE').evaluate()).isEmpty();

    await tester.tap(find.text('what it said then'));
    await tester.pumpAndSettle();

    check(find.text('TRACE').evaluate()).isNotEmpty();
    check(find.text('OUTPUT').evaluate()).isNotEmpty();
    check(find.textContaining('what it said then').evaluate()).isNotEmpty();
    // Logs were never saved with the run, so there is nothing to show.
    check(find.text('Show logs').evaluate()).isEmpty();
    check(find.text('Run again').evaluate()).isNotEmpty();
  });

  testWidgets('Run again returns to the configuration', (tester) async {
    await pumpDetail(
      tester,
      runs: <AgentRun>[fakeAgentRun(agentId: 'test_agent')],
    );
    await tester.tap(find.text('Dart records are tuples with named fields.'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run again'));
    await tester.pumpAndSettle();

    check(find.text('Configure inputs').evaluate()).isNotEmpty();
    check(find.text('Run with defaults').evaluate()).isNotEmpty();
  });

  testWidgets('the output shows the answer, never the reasoning', (
    tester,
  ) async {
    await pumpDetail(tester);
    llm.scriptedToolCalls = toolCalledOn();
    llm.scriptedReplies = <List<String>>[
      <String>['searched'],
      <String>['<think>', 'Let me work this out.', '</think>', 'It is 42.'],
    ];

    await tester.tap(find.text('Run with defaults'));
    await tester.pumpAndSettle();

    check(find.textContaining('It is 42.').evaluate()).isNotEmpty();
    check(find.textContaining('Let me work this out').evaluate()).isEmpty();
    check(find.textContaining('<think>').evaluate()).isEmpty();
  });

  testWidgets('a model with no tool calling warns but still runs', (
    tester,
  ) async {
    await pumpDetail(
      tester,
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

    check(find.textContaining('not marked as tool-calling').evaluate())
        .isNotEmpty();
    // Watching a model fail to reach for a tool is a legitimate measurement,
    // so the button stays live.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    check(button.onPressed).isNotNull();
  });

  testWidgets('an agent that is not there says so', (tester) async {
    await pumpDetail(tester, agentId: 'gone');

    check(find.textContaining('no longer exists').evaluate()).isNotEmpty();
  });
}

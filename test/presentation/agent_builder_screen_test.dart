import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/screens/agent_builder_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/builder/reads_picker.dart';
import 'package:model_scope_flutter/presentation/widgets/builder/tool_picker_grid.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeAgentRepository agents;

  Future<void> pumpBuilder(
    WidgetTester tester, {
    String? agentId,
    bool duplicate = false,
    List<Agent>? seed,
    List<String> needingKeys = const <String>[],
  }) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    agents = FakeAgentRepository(seed ?? <Agent>[]);
    await tester.pumpWidget(
      harness(
        AgentBuilderScreen(agentId: agentId, duplicate: duplicate),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          agents: agents,
          tools: fakeToolRegistry(needingKeys: needingKeys),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fills in the four things every agent needs, by typing into the screen.
  Future<void> fillBasics(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. News digest'),
      'News digest',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'One line about what it tests'),
      'Summarises the news',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'How the model should behave for every step',
      ),
      'You are careful.',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'What to ask for, using what the steps produced',
      ),
      'Write the digest.',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a new agent opens on an empty form', (tester) async {
    await pumpBuilder(tester);

    check(find.text('PIPELINE BUILDER').evaluate()).isNotEmpty();
    check(find.text('New agent').evaluate()).isNotEmpty();
    check(find.text('Create agent').evaluate()).isNotEmpty();
    check(find.text('Basics').evaluate()).isNotEmpty();
    check(find.text('Pipeline').evaluate()).isNotEmpty();
    check(find.text('Answer · always last').evaluate()).isNotEmpty();
  });

  testWidgets('saving an empty agent lists what is missing', (tester) async {
    await pumpBuilder(tester);

    await tester.tap(find.text('Create agent'));
    await tester.pumpAndSettle();

    // The validator's own wording, so the builder and the bench say the same
    // thing about the same agent.
    check(find.textContaining('to fix').evaluate()).isNotEmpty();
    check(find.textContaining('needs a name').evaluate()).isNotEmpty();
    check(agents.saved).isEmpty();
  });

  testWidgets('a filled-in agent saves', (tester) async {
    await pumpBuilder(tester);
    await fillBasics(tester);

    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reason'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What should the model reason about?'),
      'Think about it.',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create agent'));
    await tester.pumpAndSettle();

    check(agents.saved).length.equals(1);
    check(agents.saved.single.id).equals('news_digest');
    check(agents.saved.single.pipeline.single.kind).equals(StepKind.reason);
  });

  testWidgets('the tool grid lists what the registry has', (tester) async {
    await pumpBuilder(tester);
    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();

    // Built from the registry, not the four the mockups draw.
    check(find.byType(ToolPickerGrid).evaluate()).isNotEmpty();
    check(find.text('Web search').evaluate()).isNotEmpty();
    check(find.text('Read a page').evaluate()).isNotEmpty();
    check(find.text('Calculator').evaluate()).isNotEmpty();
  });

  testWidgets('a tool that needs a key warns when it is picked', (
    tester,
  ) async {
    await pumpBuilder(tester, needingKeys: <String>['web_search']);
    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();

    check(find.textContaining('Needs').evaluate()).isEmpty();

    await tester.tap(find.text('Web search'));
    await tester.pumpAndSettle();

    check(find.textContaining('Needs').evaluate()).isNotEmpty();
  });

  testWidgets('a step may only read what runs before it', (tester) async {
    await pumpBuilder(tester);
    await tester.tap(find.text('Input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'Query');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();

    final pickers = tester.widgetList<ReadsPicker>(find.byType(ReadsPicker));
    // Step one, step two, and the answer.
    check(pickers).length.equals(3);
    check(pickers.first.available.map((r) => r.reference).toList())
        .deepEquals(<String>['input.query']);
    check(pickers.elementAt(1).available.map((r) => r.reference).toList())
        .deepEquals(<String>['input.query', 'step.step_1']);
    // The answer runs last, so it may read everything.
    check(pickers.last.available.map((r) => r.reference).toList())
        .deepEquals(<String>['input.query', 'step.step_1', 'step.step_2']);
  });

  testWidgets('choosing Choice reveals an options editor', (tester) async {
    await pumpBuilder(tester);
    await tester.tap(find.text('Input'));
    await tester.pumpAndSettle();

    check(find.text('OPTIONS').evaluate()).isEmpty();

    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choice').last);
    await tester.pumpAndSettle();

    // A choice with no options is a blocker, so the editor appears with it.
    check(find.text('OPTIONS').evaluate()).isNotEmpty();
    check(find.widgetWithText(TextField, 'Option 1').evaluate()).isNotEmpty();
  });

  group('the structured response', () {
    Future<void> turnOn(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Structured response'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
    }

    testWidgets('the toggle reveals the field rows', (tester) async {
      await pumpBuilder(tester);

      check(find.text('{} Fields').evaluate()).isEmpty();

      await turnOn(tester);

      check(find.text('{} Fields').evaluate()).isNotEmpty();
      check(find.text('</> JSON schema').evaluate()).isNotEmpty();
      check(find.widgetWithText(TextField, 'field_name').evaluate())
          .isNotEmpty();
    });

    testWidgets('the JSON tab shows what the rows say', (tester) async {
      await pumpBuilder(tester);
      await turnOn(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'field_name').first,
        'winner',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('</> JSON schema'));
      await tester.pumpAndSettle();

      check(find.textContaining('"winner"').evaluate()).isNotEmpty();
      check(find.textContaining('"type": "object"').evaluate()).isNotEmpty();
    });

    testWidgets('a schema the rows cannot draw is kept as written', (
      tester,
    ) async {
      await pumpBuilder(tester);
      await turnOn(tester);
      await tester.tap(find.text('</> JSON schema'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).last,
        '{"type":"object","properties":{"u":{"type":"string",'
        '"enum":["a","b"]}}}',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this schema'));
      await tester.pumpAndSettle();

      // Simplifying it into what the rows understand would change what the
      // model is allowed to emit, so it stays on the JSON tab and says so.
      check(find.textContaining('Kept exactly as written').evaluate())
          .isNotEmpty();

      // And the Fields tab says the same rather than showing empty rows.
      await tester.tap(find.text('{} Fields'));
      await tester.pumpAndSettle();
      check(find.textContaining('cannot show').evaluate()).isNotEmpty();
    });

    testWidgets('malformed JSON keeps the text and names the fault', (
      tester,
    ) async {
      await pumpBuilder(tester);
      await turnOn(tester);
      await tester.tap(find.text('</> JSON schema'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '{not json');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this schema'));
      await tester.pumpAndSettle();

      check(find.textContaining('not valid JSON').evaluate()).isNotEmpty();
      // Losing the text over a typo would be the worst possible response.
      check(find.textContaining('{not json').evaluate()).isNotEmpty();
    });
  });

  group('editing an existing agent', () {
    List<Agent> seedOf(AgentTemplate template, {bool builtIn = false}) =>
        <Agent>[Agent(template: template, isBuiltIn: builtIn)];

    testWidgets('loads it and says it is an edit', (tester) async {
      await pumpBuilder(
        tester,
        agentId: 'mine',
        seed: seedOf(fakeAgentTemplate(id: 'mine')),
      );

      check(find.text('Edit agent').evaluate()).isNotEmpty();
      check(find.text('Save changes').evaluate()).isNotEmpty();
      check(find.widgetWithText(TextField, 'Test Agent').evaluate())
          .isNotEmpty();
    });

    testWidgets('saving keeps the id even after a rename', (tester) async {
      await pumpBuilder(
        tester,
        agentId: 'mine',
        seed: seedOf(fakeAgentTemplate(id: 'mine')),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Test Agent'),
        'Renamed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      // An agent's file and its run history are both keyed by the id.
      check(agents.saved.single.id).equals('mine');
      check(agents.saved.single.name).equals('Renamed');
    });

    testWidgets('a duplicate is named as one and gets a new id', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        agentId: 'built_in',
        duplicate: true,
        seed: seedOf(fakeAgentTemplate(id: 'built_in'), builtIn: true),
      );

      check(find.text('New agent').evaluate()).isNotEmpty();
      check(find.widgetWithText(TextField, 'Test Agent copy').evaluate())
          .isNotEmpty();

      await tester.tap(find.text('Create agent'));
      await tester.pumpAndSettle();

      // The built-in stays where it is.
      check(agents.saved.single.id).equals('test_agent_copy');
    });

    testWidgets('an agent that is gone says so', (tester) async {
      await pumpBuilder(tester, agentId: 'nope');

      check(find.textContaining('no longer exists').evaluate()).isNotEmpty();
    });

    testWidgets('a built-in is edited in place and offers a reset', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        agentId: 'built_in',
        seed: seedOf(fakeAgentTemplate(id: 'built_in'), builtIn: true),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // The bundled file cannot be removed, so the destructive action puts
      // the shipped version back rather than taking the agent away.
      check(find.text('Reset to built-in').evaluate()).isNotEmpty();
      check(find.text('Delete agent').evaluate()).isEmpty();

      await tester.tap(find.text('Reset to built-in'));
      await tester.pumpAndSettle();

      check(find.textContaining('shipped with the app').evaluate())
          .isNotEmpty();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      check(agents.deleted).deepEquals(<String>['built_in']);
    });

    testWidgets('an agent of your own still offers Delete', (tester) async {
      await pumpBuilder(
        tester,
        agentId: 'mine',
        seed: seedOf(fakeAgentTemplate(id: 'mine')),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      check(find.text('Delete agent').evaluate()).isNotEmpty();
      check(find.text('Reset to built-in').evaluate()).isEmpty();
    });
  });

  group('the limits card', () {
    testWidgets('shows the web rows only for an agent that searches', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        agentId: 'mine',
        seed: <Agent>[
          Agent(template: fakeAgentTemplate(id: 'mine'), isBuiltIn: false),
        ],
      );

      // The shipped fake searches the web and retrieves nothing.
      check(find.text('WEB RESULTS').evaluate()).isNotEmpty();
      check(find.text('CHARS PER PAGE').evaluate()).isNotEmpty();
      check(find.text('PASSAGE LENGTH').evaluate()).isEmpty();
    });

    testWidgets('shows the document rows for one that retrieves', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        agentId: 'document_qna',
        seed: <Agent>[Agent(template: fakeDocumentAgent(), isBuiltIn: false)],
      );

      // This agent takes four inputs, so the card sits below the fold.
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();

      check(find.text('PASSAGE LENGTH').evaluate()).isNotEmpty();
      check(find.text('PASSAGES RETRIEVED').evaluate()).isNotEmpty();
      check(find.text('WEB RESULTS').evaluate()).isEmpty();
    });

    testWidgets('an agent reaching neither is shown no card at all', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        agentId: 'mine',
        seed: <Agent>[
          Agent(
            template: fakeAgentTemplate(
              id: 'mine',
              pipeline: const <PipelineStep>[
                PipelineStep(
                  id: 'think',
                  kind: StepKind.reason,
                  prompt: 'Consider it.',
                ),
              ],
            ),
            isBuiltIn: false,
          ),
        ],
      );

      // Six sliders controlling nothing would be worse than none.
      check(find.text('Limits').evaluate()).isEmpty();
    });
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    agents = FakeAgentRepository(<Agent>[]);
    await tester.pumpWidget(
      harness(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AgentBuilderScreen(),
        ),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          agents: agents,
        ),
      ),
    );
    await tester.pumpAndSettle();

    check(tester.takeException()).isNull();
  });
}

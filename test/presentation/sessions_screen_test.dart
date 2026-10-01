import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/presentation/screens/sessions_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/session_card.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  Future<FakeSessionRepository> pumpList(
    WidgetTester tester, {
    required List<ChatSession> seed,
  }) async {
    final repository = FakeSessionRepository(seed);
    await tester.pumpWidget(
      harness(
        const SessionsScreen(),
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('renders one card per session', (tester) async {
    // Arrange / Act
    await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation', count: 4),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    // Assert
    check(tester.widgetList(find.byType(SessionCard))).length.equals(2);
    check(find.text('Explain quantisation').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Instruct · 4 msgs').evaluate()).isNotEmpty();
  });

  testWidgets('the overline counts what is actually on screen', (tester) async {
    // Arrange
    await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    // Assert
    check(find.text('2 LOCAL SESSIONS').evaluate()).isNotEmpty();

    // Act — narrow the list with the search field.
    await tester.enterText(find.byType(TextField), 'changelog');
    await tester.pumpAndSettle();

    // Assert — singular, and only the matching card survives.
    check(find.text('1 LOCAL SESSION').evaluate()).isNotEmpty();
    check(tester.widgetList(find.byType(SessionCard))).length.equals(1);
    check(find.text('Draft a changelog').evaluate()).isNotEmpty();
  });

  testWidgets('says so when a filter matches nothing', (tester) async {
    // Arrange
    await pumpList(tester, seed: <ChatSession>[sessionWith(id: 'a')]);

    // Act
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    // Assert
    check(find.text('No sessions match those filters.').evaluate())
        .isNotEmpty();
  });

  testWidgets('delete removes the card and offers an undo', (tester) async {
    // Arrange
    final repository = await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    // Act
    await tester.tap(find.byTooltip('Delete Explain quantisation'));
    await tester.pumpAndSettle();

    // Assert
    check(tester.widgetList(find.byType(SessionCard))).length.equals(1);
    check(repository.stored.map((s) => s.id).toList())
        .deepEquals(<String>['b']);

    // Act — undo.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Assert
    check(tester.widgetList(find.byType(SessionCard))).length.equals(2);
    check(repository.stored.map((s) => s.id).toList())
        .unorderedEquals(<String>['a', 'b']);
  });

  testWidgets('every interactive element carries a label', (tester) async {
    // Arrange
    final handle = tester.ensureSemantics();
    await pumpList(tester, seed: <ChatSession>[sessionWith(id: 'a')]);

    // Assert — the dropdowns merge their label with their current value, so
    // these match on a prefix rather than the whole spoken string.
    check(find.bySemanticsLabel('New chat').evaluate()).isNotEmpty();
    check(find.bySemanticsLabel(RegExp('^Filter by model')).evaluate())
        .isNotEmpty();
    check(find.bySemanticsLabel(RegExp('^Filter by date')).evaluate())
        .isNotEmpty();
    check(find.byTooltip('Delete New chat').evaluate()).isNotEmpty();

    handle.dispose();
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    // Arrange — CLAUDE.md asks for legibility up to double the base size.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Act
    await tester.pumpWidget(
      harness(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SessionsScreen(),
        ),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(<ChatSession>[
            sessionWith(id: 'a', title: 'Explain quantisation end to end'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Assert — `pumpAndSettle` would have surfaced a layout exception.
    check(tester.takeException()).isNull();
  });
}

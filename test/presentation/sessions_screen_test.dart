import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:model_scope_flutter/config/router/app_router.dart';
import 'package:model_scope_flutter/config/theme/app_theme.dart';
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
    await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation', count: 4),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    check(tester.widgetList(find.byType(SessionCard))).length.equals(2);
    check(find.text('Explain quantisation').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Instruct · 4 msgs').evaluate()).isNotEmpty();
  });

  testWidgets('the overline counts what is actually on screen', (tester) async {
    await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    check(find.text('2 LOCAL SESSIONS').evaluate()).isNotEmpty();

    // Narrow the list with the search field.
    await tester.enterText(find.byType(TextField), 'changelog');
    await tester.pumpAndSettle();

    // Singular, and only the matching card survives.
    check(find.text('1 LOCAL SESSION').evaluate()).isNotEmpty();
    check(tester.widgetList(find.byType(SessionCard))).length.equals(1);
    check(find.text('Draft a changelog').evaluate()).isNotEmpty();
  });

  testWidgets('says so when a filter matches nothing', (tester) async {
    await pumpList(tester, seed: <ChatSession>[sessionWith(id: 'a')]);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    check(find.text('No sessions match those filters.').evaluate())
        .isNotEmpty();
    // A filter hiding the only chat is not the same as having no chats, so
    // the empty state must not offer to start one here.
    check(find.text('Start a chat').evaluate()).isEmpty();
  });

  testWidgets('a fresh install offers a way to start the first chat', (
    tester,
  ) async {
    // A router with a stand-in at the session path, so this asserts that the
    // button creates a chat and opens it rather than what the chat renders.
    final repository = FakeSessionRepository();
    final router = GoRouter(
      initialLocation: Routes.chat,
      routes: <RouteBase>[
        GoRoute(path: Routes.chat, builder: (_, _) => const SessionsScreen()),
        GoRoute(
          path: Routes.session,
          builder: (_, _) => const Scaffold(body: Text('The chat')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    check(find.text('No chats yet').evaluate()).isNotEmpty();
    check(find.text('No sessions match those filters.').evaluate()).isEmpty();
    // Nothing is seeded any more, so the store stays untouched until asked.
    check(repository.stored).isEmpty();

    await tester.tap(find.text('Start a chat'));
    await tester.pumpAndSettle();

    check(repository.stored).length.equals(1);
    check(find.text('The chat').evaluate()).isNotEmpty();
  });

  testWidgets('delete asks first and cancelling keeps the session', (
    tester,
  ) async {
    final repository = await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    await tester.tap(find.byTooltip('Delete Explain quantisation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A transcript is unrecoverable, so nothing goes until confirmed.
    check(tester.widgetList(find.byType(SessionCard))).length.equals(2);
    check(repository.stored.map((s) => s.id).toList())
        .unorderedEquals(<String>['a', 'b']);
  });

  testWidgets('confirming the dialog deletes the session', (tester) async {
    final repository = await pumpList(
      tester,
      seed: <ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ],
    );

    await tester.tap(find.byTooltip('Delete Explain quantisation'));
    await tester.pumpAndSettle();
    check(find.text('Delete "Explain quantisation"?').evaluate()).isNotEmpty();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    check(tester.widgetList(find.byType(SessionCard))).length.equals(1);
    check(repository.stored.map((s) => s.id).toList())
        .deepEquals(<String>['b']);
  });

  testWidgets('every interactive element carries a label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, seed: <ChatSession>[sessionWith(id: 'a')]);

    // The dropdowns merge their label with their current value, so
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
    // CLAUDE.md asks for legibility up to double the base size.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

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

    // `pumpAndSettle` would have surfaced a layout exception.
    check(tester.takeException()).isNull();
  });
}

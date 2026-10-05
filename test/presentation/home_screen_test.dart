import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/generation_metrics.dart';
import 'package:model_scope_flutter/presentation/screens/home_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/stat_tile.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// Replies are timestamped against the wall clock because the provider folds
  /// them against `DateTime.now()`; a fixed date would read as "no replies".
  final DateTime now = DateTime.now();

  ChatMessage reply(String id, GenerationMetrics metrics) => ChatMessage(
    id: id,
    role: MessageRole.assistant,
    text: 'answer',
    createdAt: now,
    metrics: metrics,
  );

  ChatSession seeded() => ChatSession(
    id: 'a',
    title: 'Explain quantisation',
    modelId: fakeInstalledModel().id,
    createdAt: now,
    updatedAt: now,
    messages: <ChatMessage>[
      ChatMessage(id: 'q', role: MessageRole.user, text: 'ask', createdAt: now),
      reply(
        'r1',
        const GenerationMetrics(
          latencyMs: 100,
          tokensPerSecond: 94.2,
          tokenCount: 1200,
        ),
      ),
      reply(
        'r2',
        const GenerationMetrics(
          latencyMs: 300,
          tokensPerSecond: 41,
          tokenCount: 2300,
        ),
      ),
    ],
  );

  /// The dashboard is a long scroll of lazily built slivers, so the view is
  /// made tall enough that the activity feed and the buttons below it exist.
  Future<void> pumpHome(
    WidgetTester tester, {
    List<ChatSession> sessions = const <ChatSession>[],
    FakeModelLibraryRepository? library,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: const HomeScreen(),
        ),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(sessions),
          library: library,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The tile carrying [label], whatever its figure.
  Finder tile(String label) =>
      find.byWidgetPredicate((w) => w is StatTile && w.label == label);

  String valueOf(WidgetTester tester, String label) =>
      tester.widget<StatTile>(tile(label)).value;

  testWidgets('draws all six runtime figures', (tester) async {
    await pumpHome(tester, sessions: <ChatSession>[seeded()]);

    // The grid is fixed, so a missing figure is a missing tile.
    for (final label in const <String>[
      'TOKENS GENERATED',
      'AVG LATENCY',
      'PEAK THROUGHPUT',
      'AGENT RUNS',
      'MODELS',
      'CHATS TODAY',
    ]) {
      check(because: label, tile(label).evaluate()).isNotEmpty();
    }
  });

  testWidgets('folds the stored replies into the tiles', (tester) async {
    await pumpHome(tester, sessions: <ChatSession>[seeded()]);

    check(valueOf(tester, 'TOKENS GENERATED')).equals('3.5k');
    check(valueOf(tester, 'AVG LATENCY')).equals('200ms');
    check(valueOf(tester, 'PEAK THROUGHPUT')).equals('94.2');
    check(valueOf(tester, 'CHATS TODAY')).equals('2');
    check(valueOf(tester, 'MODELS')).equals('1');

    // The peak caption names the model that reached it.
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
  });

  testWidgets('agent runs read zero while agents are unimplemented', (
    tester,
  ) async {
    // A full transcript must not invent a run.
    await pumpHome(tester, sessions: <ChatSession>[seeded()]);

    check(valueOf(tester, 'AGENT RUNS')).equals('0');
    check(find.text('across 0 agents').evaluate()).isNotEmpty();
  });

  testWidgets('a fresh install says so rather than drawing empty axes', (
    tester,
  ) async {
    // Nothing chatted, nothing installed. The sessions view
    // model still seeds one blank session, so the list is never empty.
    await pumpHome(tester, library: FakeModelLibraryRepository());

    check(valueOf(tester, 'TOKENS GENERATED')).equals('0');
    check(valueOf(tester, 'AVG LATENCY')).equals('0ms');
    check(valueOf(tester, 'MODELS')).equals('0');
    check(find.text('no replies yet').evaluate()).isNotEmpty();
    check(find.text('0 B on disk').evaluate()).isNotEmpty();
    // One line per chart: latency and throughput.
    check(find.text('No replies recorded yet.').evaluate()).length.equals(2);
    check(find.text('No models yet. Add one to start chatting.').evaluate())
        .isNotEmpty();
    // The seeded session has no model, which is not the same as having lost one.
    check(find.text('removed model · 0 messages').evaluate()).isEmpty();
    check(find.text('no model · 0 messages').evaluate()).isNotEmpty();
  });

  testWidgets('lists the installed model and the recent activity', (
    tester,
  ) async {
    await pumpHome(tester, sessions: <ChatSession>[seeded()]);

    // The model row, then both activity kinds.
    check(find.text('2 runs · 200ms · just now').evaluate()).isNotEmpty();
    check(find.text('Session "Explain quantisation"').evaluate()).isNotEmpty();
    check(find.text('Pulled SmolLM2 360M Instruct').evaluate()).isNotEmpty();
  });

  testWidgets('keeps every stat tile the same height', (tester) async {
    // Captions differ in length, which is what used to make
    // the tiles ragged.
    await pumpHome(tester, sessions: <ChatSession>[seeded()]);

    final heights = tester
        .widgetList<StatTile>(find.byType(StatTile))
        .map((t) => tester.getSize(find.byWidget(t)).height)
        .toSet();
    check(heights).length.equals(1);
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    // CLAUDE.md asks for legibility up to double the base size.
    await pumpHome(
      tester,
      sessions: <ChatSession>[seeded()],
      textScaler: const TextScaler.linear(2),
    );

    // `pumpAndSettle` would have surfaced a layout exception.
    check(tester.takeException()).isNull();
  });
}

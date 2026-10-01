import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/presentation/screens/chat_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/assistant_message.dart';
import 'package:model_scope_flutter/presentation/widgets/user_bubble.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// Pumps the transcript for [seed] and waits for the model to "load".
  Future<void> pumpChat(
    WidgetTester tester, {
    required ChatSession seed,
    required FakeLlmService llm,
    FakeSessionRepository? repository,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: ChatScreen(sessionId: seed.id),
        ),
        overrides: fakeOverrides(
          llm: llm,
          sessions: repository ?? FakeSessionRepository(<ChatSession>[seed]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types [text] and taps send.
  ///
  /// The pump in the middle matters: `enterText` does not schedule a frame, so
  /// without it the send button is still in its disabled state when tapped.
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send message'));
  }

  testWidgets('draws questions as bubbles and replies as plain text', (
    tester,
  ) async {
    // Arrange / Act
    await pumpChat(
      tester,
      seed: sessionWith(title: 'Explain quantisation', count: 4),
      llm: FakeLlmService(),
    );

    // Assert — the asymmetry is what the mockup is built on.
    check(tester.widgetList(find.byType(UserBubble))).length.equals(2);
    check(tester.widgetList(find.byType(AssistantMessage))).length.equals(2);
    check(find.text('Explain quantisation').evaluate()).isNotEmpty();
  });

  testWidgets('shows the model strip with the live temperature', (
    tester,
  ) async {
    // Arrange / Act
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    // Assert
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(find.text('Q8_0').evaluate()).isNotEmpty();
    check(find.text('T 0.70').evaluate()).isNotEmpty();
  });

  testWidgets('invites a first question when the session is empty', (
    tester,
  ) async {
    // Arrange / Act
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    // Assert
    check(
      find.text('Ask the model something to start this session.').evaluate(),
    ).isNotEmpty();
  });

  testWidgets('sending a message streams a reply with its metrics', (
    tester,
  ) async {
    // Arrange
    final llm = FakeLlmService(tokens: <String>['Eight', '-bit', ' weights.']);
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    // Act
    await send(tester, 'What does Q8_0 mean?');
    await tester.pumpAndSettle();

    // Assert
    check(llm.prompts).deepEquals(<String>['What does Q8_0 mean?']);
    check(find.text('Eight-bit weights.').evaluate()).isNotEmpty();
    check(find.textContaining('3 tok').evaluate()).isNotEmpty();
    check(find.byTooltip('Regenerate reply').evaluate()).isNotEmpty();
  });

  testWidgets('the composer is disabled until the model is ready', (
    tester,
  ) async {
    // Arrange — hold the load open so `preparing` is observable.
    final gate = Completer<void>();
    final llm = FakeLlmService()..loadGate = gate;
    await tester.pumpWidget(
      harness(
        ChatScreen(sessionId: sessionWith().id),
        overrides: fakeOverrides(
          llm: llm,
          sessions: FakeSessionRepository(<ChatSession>[sessionWith()]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Assert — the spinner is up and nothing can be sent yet.
    check(find.text('Loading the model…').evaluate()).isNotEmpty();
    await send(tester, 'Too early');
    await tester.pump();
    check(llm.prompts).isEmpty();

    // Act — let the weights land.
    gate.complete();
    await tester.pumpAndSettle();

    // Assert — the same text now sends.
    await send(tester, 'Now it works');
    await tester.pumpAndSettle();
    check(llm.prompts).deepEquals(<String>['Now it works']);
  });

  testWidgets('the send button becomes a stop button while streaming', (
    tester,
  ) async {
    // Arrange — a slow stream so the streaming state can be observed.
    final llm = FakeLlmService(
      tokens: List<String>.generate(6, (i) => 't$i'),
      gap: const Duration(milliseconds: 40),
    );
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    // Act
    await send(tester, 'Go on');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Assert
    check(find.bySemanticsLabel('Stop generating').evaluate()).isNotEmpty();

    // Act — stopping ends the turn early.
    await tester.tap(find.bySemanticsLabel('Stop generating'));
    await tester.pumpAndSettle();

    // Assert
    check(llm.stopCalls).equals(1);
    check(llm.emitted).isLessThan(6);
    check(find.bySemanticsLabel('Send message').evaluate()).isNotEmpty();
  });

  testWidgets('picking an attachment chips it and notes the limitation', (
    tester,
  ) async {
    // Arrange
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    // Act
    await tester.tap(find.bySemanticsLabel('Attach a file'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Attach PDF')));
    await tester.pumpAndSettle();

    // Assert — the chip is shown, with the in-app note that it is display-only.
    check(find.text('report.pdf').evaluate()).isNotEmpty();
    check(find.textContaining('not sent to it').evaluate()).isNotEmpty();
  });

  testWidgets('a generation failure is reported on the message', (
    tester,
  ) async {
    // Arrange
    final llm = FakeLlmService()..failure = StateError('context overflow');
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    // Act
    await send(tester, 'Break it');
    await tester.pumpAndSettle();

    // Assert — the transcript stays usable; only this turn shows the error.
    check(find.textContaining('context overflow').evaluate()).isNotEmpty();
    check(find.byType(TextField).evaluate()).isNotEmpty();
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    // Arrange
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Act
    await pumpChat(
      tester,
      seed: sessionWith(title: 'Explain quantisation end to end', count: 4),
      llm: FakeLlmService(),
      textScaler: const TextScaler.linear(2),
    );

    // Assert
    check(tester.takeException()).isNull();
  });
}

import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/presentation/screens/chat_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/assistant_message.dart';
import 'package:model_scope_flutter/presentation/widgets/chat_composer.dart';
import 'package:model_scope_flutter/presentation/widgets/image_thumbnail.dart';
import 'package:model_scope_flutter/presentation/widgets/user_bubble.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// The image button's semantics label while it is enabled. Disabled it
  /// grows a reason, which is why the tests that want it off match a prefix.
  const String attach = 'Attach an image';

  /// Pumps the transcript for [seed] and waits for the model to "load". Pass
  /// [vision] to install the projector that lets the model read images.
  Future<void> pumpChat(
    WidgetTester tester, {
    required ChatSession seed,
    required FakeLlmService llm,
    FakeSessionRepository? repository,
    FakeAttachmentPicker? picker,
    bool vision = false,
    TextScaler textScaler = TextScaler.noScaling,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: MediaQueryData(textScaler: textScaler, viewInsets: viewInsets),
          child: ChatScreen(sessionId: seed.id),
        ),
        overrides: fakeOverrides(
          llm: llm,
          sessions: repository ?? FakeSessionRepository(<ChatSession>[seed]),
          picker: picker,
          library: FakeModelLibraryRepository.of(
            <ModelDescriptor>[fakeInstalledModel()],
            projectors: vision
                ? <ProjectorDescriptor>[fakeProjector()]
                : const <ProjectorDescriptor>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types [text] and taps send. The pump in the middle matters: `enterText`
  /// does not schedule a frame, so without it send is still disabled.
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send message'));
  }

  testWidgets('draws questions as bubbles and replies as plain text', (
    tester,
  ) async {
    await pumpChat(
      tester,
      seed: sessionWith(title: 'Explain quantisation', count: 4),
      llm: FakeLlmService(),
    );

    // The asymmetry is what the mockup is built on.
    check(tester.widgetList(find.byType(UserBubble))).length.equals(2);
    check(tester.widgetList(find.byType(AssistantMessage))).length.equals(2);
    check(find.text('Explain quantisation').evaluate()).isNotEmpty();
  });

  testWidgets('shows the model strip with the live temperature', (
    tester,
  ) async {
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(find.text('Q8_0').evaluate()).isNotEmpty();
    check(find.text('T 0.70').evaluate()).isNotEmpty();
  });

  testWidgets('invites a first question when the session is empty', (
    tester,
  ) async {
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    check(
      find.text('Ask the model something to start this session.').evaluate(),
    ).isNotEmpty();
  });

  testWidgets('sending a message streams a reply with its metrics', (
    tester,
  ) async {
    final llm = FakeLlmService(tokens: <String>['Eight', '-bit', ' weights.']);
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    await send(tester, 'What does Q8_0 mean?');
    await tester.pumpAndSettle();

    check(llm.prompts).deepEquals(<String>['What does Q8_0 mean?']);
    check(find.text('Eight-bit weights.').evaluate()).isNotEmpty();
    check(find.textContaining('3 tok').evaluate()).isNotEmpty();
    check(find.byTooltip('Regenerate reply').evaluate()).isNotEmpty();
  });

  testWidgets('the composer is disabled until the model is ready', (
    tester,
  ) async {
    // Hold the load open so `preparing` is observable.
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

    // The spinner is up and nothing can be sent yet.
    check(find.text('Loading the model…').evaluate()).isNotEmpty();
    await send(tester, 'Too early');
    await tester.pump();
    check(llm.prompts).isEmpty();

    // Let the weights land.
    gate.complete();
    await tester.pumpAndSettle();

    // The same text now sends.
    await send(tester, 'Now it works');
    await tester.pumpAndSettle();
    check(llm.prompts).deepEquals(<String>['Now it works']);
  });

  testWidgets('the send button becomes a stop button while streaming', (
    tester,
  ) async {
    // A slow stream so the streaming state can be observed.
    final llm = FakeLlmService(
      tokens: List<String>.generate(6, (i) => 't$i'),
      gap: const Duration(milliseconds: 40),
    );
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    await send(tester, 'Go on');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    check(find.bySemanticsLabel('Stop generating').evaluate()).isNotEmpty();

    // Stopping ends the turn early.
    await tester.tap(find.bySemanticsLabel('Stop generating'));
    await tester.pumpAndSettle();

    check(llm.stopCalls).equals(1);
    check(llm.emitted).isLessThan(6);
    check(find.bySemanticsLabel('Send message').evaluate()).isNotEmpty();
  });

  testWidgets('picking an image puts a thumbnail in the composer', (
    tester,
  ) async {
    await pumpChat(
      tester,
      seed: sessionWith(),
      llm: FakeLlmService(),
      vision: true,
    );

    await tester.tap(find.bySemanticsLabel(attach));
    await tester.pumpAndSettle();

    check(find.byType(ImageThumbnail).evaluate()).length.equals(1);
  });

  testWidgets('cancelling the picker leaves the composer alone', (
    tester,
  ) async {
    await pumpChat(
      tester,
      seed: sessionWith(),
      llm: FakeLlmService(),
      vision: true,
      picker: FakeAttachmentPicker(),
    );

    await tester.tap(find.bySemanticsLabel(attach));
    await tester.pumpAndSettle();

    check(find.byType(ImageThumbnail).evaluate()).isEmpty();
  });

  testWidgets('a model without a projector cannot be given an image', (
    tester,
  ) async {
    await pumpChat(tester, seed: sessionWith(), llm: FakeLlmService());

    // The button is there and says why it is off, rather than disappearing.
    final label = find.bySemanticsLabel(
      RegExp('^Attach an image — this model cannot read images'),
    );
    check(label.evaluate()).isNotEmpty();

    await tester.tap(label, warnIfMissed: false);
    await tester.pumpAndSettle();

    check(find.byType(ImageThumbnail).evaluate()).isEmpty();
  });

  testWidgets('the image button switches off at three', (tester) async {
    await pumpChat(
      tester,
      seed: sessionWith(),
      llm: FakeLlmService(),
      vision: true,
      picker: FakeAttachmentPicker.each(const <String>[
        '/tmp/a.png',
        '/tmp/b.png',
        '/tmp/c.png',
      ]),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.bySemanticsLabel(attach));
      await tester.pumpAndSettle();
    }

    check(find.byType(ImageThumbnail).evaluate()).length.equals(3);
    check(find.bySemanticsLabel(RegExp('limit of 3 reached')).evaluate())
        .isNotEmpty();
  });

  testWidgets('a sent image rides along on the message', (tester) async {
    final llm = FakeLlmService();
    await pumpChat(tester, seed: sessionWith(), llm: llm, vision: true);

    await tester.tap(find.bySemanticsLabel(attach));
    await tester.pumpAndSettle();
    await send(tester, 'What is this?');
    await tester.pumpAndSettle();

    check(llm.askedImages.single).length.equals(1);
    // One on the bubble; the composer cleared when the message took it.
    check(find.byType(ImageThumbnail).evaluate()).length.equals(1);
  });

  testWidgets('a generation failure is reported on the message', (
    tester,
  ) async {
    final llm = FakeLlmService()..failure = StateError('context overflow');
    await pumpChat(tester, seed: sessionWith(), llm: llm);

    await send(tester, 'Break it');
    await tester.pumpAndSettle();

    // The transcript stays usable; only this turn shows the error.
    check(find.textContaining('context overflow').evaluate()).isNotEmpty();
    check(find.byType(TextField).evaluate()).isNotEmpty();
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpChat(
      tester,
      seed: sessionWith(title: 'Explain quantisation end to end', count: 4),
      llm: FakeLlmService(),
      textScaler: const TextScaler.linear(2),
    );

    check(tester.takeException()).isNull();
  });

  testWidgets('the composer rides above an open keyboard', (tester) async {
    // What the IME reports while it is up.
    const double keyboard = 300;

    await pumpChat(
      tester,
      seed: sessionWith(count: 4),
      llm: FakeLlmService(),
      viewInsets: const EdgeInsets.only(bottom: keyboard),
    );

    // The field must end above the keyboard, not behind it. As the
    // Scaffold's `bottomNavigationBar` it stayed pinned to the window edge.
    final height = tester.getSize(find.byType(Scaffold).first).height;
    check(tester.getBottomLeft(find.byType(ChatComposer)).dy)
        .isLessOrEqual(height - keyboard);
  });

  testWidgets('the composer sits at the bottom with no keyboard', (
    tester,
  ) async {
    await pumpChat(tester, seed: sessionWith(count: 4), llm: FakeLlmService());

    // Moving it into the body must not leave a gap below it.
    final height = tester.getSize(find.byType(Scaffold).first).height;
    check(tester.getBottomLeft(find.byType(ChatComposer)).dy)
        .isCloseTo(height, 0.5);
  });
}

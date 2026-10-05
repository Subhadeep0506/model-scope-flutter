import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/domain/services/history_window.dart';

/// A transcript of [turns] question-and-answer pairs, numbered from one.
List<ChatMessage> transcript(int turns) => <ChatMessage>[
  for (var i = 1; i <= turns; i++) ...<ChatMessage>[
    _message(id: 'q$i', role: MessageRole.user, text: 'question $i'),
    _message(id: 'a$i', role: MessageRole.assistant, text: 'answer $i'),
  ],
];

ChatMessage _message({
  required String id,
  required MessageRole role,
  required String text,
  String? error,
  List<String> images = const <String>[],
}) => ChatMessage(
  id: id,
  role: role,
  text: text,
  createdAt: DateTime(2026, 10, 2),
  error: error,
  imagePaths: images,
);

void main() {
  group('historyWindow', () {
    test('replays nothing at zero turns', () {
      final window = historyWindow(transcript(5), 0);

      // Every prompt is answered cold.
      check(window).isEmpty();
    });

    test('keeps the whole transcript when it fits the budget', () {
      final messages = transcript(3);

      final window = historyWindow(messages, 10);

      check(window.map((m) => m.id)).deepEquals(messages.map((m) => m.id));
    });

    test('keeps only the most recent turns once the budget binds', () {
      final window = historyWindow(transcript(30), 10);

      // The last ten pairs, oldest of them first.
      check(window).length.equals(20);
      check(window.first.id).equals('q21');
      check(window.last.id).equals('a30');
    });

    test('strips a reply down to its answer', () {
      final messages = <ChatMessage>[
        _message(id: 'q', role: MessageRole.user, text: 'Why?'),
        _message(
          id: 'a',
          role: MessageRole.assistant,
          text: '<think>Long chain of reasoning.</think>Because of X.',
        ),
      ];

      final window = historyWindow(messages, 10);

      // Reasoning is the bulk of the output and must not be replayed.
      check(window.last.text).equals('Because of X.');
    });

    test('drops errored and empty messages', () {
      final messages = <ChatMessage>[
        _message(id: 'q1', role: MessageRole.user, text: 'first'),
        _message(
          id: 'a1',
          role: MessageRole.assistant,
          text: '',
          error: 'Generation failed',
        ),
        _message(id: 'q2', role: MessageRole.user, text: 'second'),
        _message(id: 'a2', role: MessageRole.assistant, text: 'fine'),
      ];

      final window = historyWindow(messages, 10);

      check(window.map((m) => m.id)).deepEquals(<String>['q1', 'q2', 'a2']);
    });
  });

  group('needsHistoryReseat', () {
    test('is false for a short transcript with nothing to strip', () {
      // The model already holds exactly the window, so replaying it
      // would be a re-prefill for nothing.
      check(needsHistoryReseat(transcript(3), 10)).isFalse();
    });

    test('is true once the transcript outgrows the budget', () {
      check(needsHistoryReseat(transcript(11), 10)).isTrue();
    });

    test('is true when a reply carries reasoning to strip', () {
      final messages = <ChatMessage>[
        _message(id: 'q', role: MessageRole.user, text: 'Why?'),
        _message(
          id: 'a',
          role: MessageRole.assistant,
          text: '<think>Working.</think>Because.',
        ),
      ];

      check(needsHistoryReseat(messages, 10)).isTrue();
    });

    test('is false for an empty transcript at any budget', () {
      check(needsHistoryReseat(const <ChatMessage>[], 0)).isFalse();
      check(needsHistoryReseat(const <ChatMessage>[], 10)).isFalse();
    });

    test('is not disturbed by images on a message', () {
      // The markers are added when history is pushed to the model, not by
      // historyWindow — otherwise every turn of a conversation holding an
      // image would look changed and force a reseat.
      final messages = <ChatMessage>[
        _message(
          id: 'q',
          role: MessageRole.user,
          text: 'What is this?',
          images: const <String>['/app/images/dog.jpg'],
        ),
        _message(id: 'a', role: MessageRole.assistant, text: 'A dog.'),
      ];

      check(needsHistoryReseat(messages, 10)).isFalse();
    });
  });

  group('withImageMarkers', () {
    test('leaves a message without images alone', () {
      final message = _message(id: 'q', role: MessageRole.user, text: 'Why?');

      check(withImageMarkers(message)).equals('Why?');
    });

    test('names one image ahead of the text', () {
      final message = _message(
        id: 'q',
        role: MessageRole.user,
        text: 'What is this?',
        images: const <String>['/app/images/8f2-dog.jpg'],
      );

      // The stored name, not the whole path: the model is being told what it
      // was shown, and the app's folder layout is not part of that.
      check(withImageMarkers(message))
          .equals('[image: 8f2-dog.jpg]\nWhat is this?');
    });

    test('names every image, in order', () {
      final message = _message(
        id: 'q',
        role: MessageRole.user,
        text: 'Compare these.',
        images: const <String>[
          '/app/images/a.jpg',
          '/app/images/b.png',
          '/app/images/c.jpeg',
        ],
      );

      check(withImageMarkers(message)).equals(
        '[image: a.jpg]\n[image: b.png]\n[image: c.jpeg]\nCompare these.',
      );
    });
  });
}

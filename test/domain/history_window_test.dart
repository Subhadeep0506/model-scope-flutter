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
}) => ChatMessage(
  id: id,
  role: role,
  text: text,
  createdAt: DateTime(2026, 10, 2),
  error: error,
);

void main() {
  group('historyWindow', () {
    test('replays nothing at zero turns', () {
      // Act
      final window = historyWindow(transcript(5), 0);

      // Assert — every prompt is answered cold.
      check(window).isEmpty();
    });

    test('keeps the whole transcript when it fits the budget', () {
      // Arrange
      final messages = transcript(3);

      // Act
      final window = historyWindow(messages, 10);

      // Assert
      check(window.map((m) => m.id)).deepEquals(messages.map((m) => m.id));
    });

    test('keeps only the most recent turns once the budget binds', () {
      // Act
      final window = historyWindow(transcript(30), 10);

      // Assert — the last ten pairs, oldest of them first.
      check(window).length.equals(20);
      check(window.first.id).equals('q21');
      check(window.last.id).equals('a30');
    });

    test('strips a reply down to its answer', () {
      // Arrange
      final messages = <ChatMessage>[
        _message(id: 'q', role: MessageRole.user, text: 'Why?'),
        _message(
          id: 'a',
          role: MessageRole.assistant,
          text: '<think>Long chain of reasoning.</think>Because of X.',
        ),
      ];

      // Act
      final window = historyWindow(messages, 10);

      // Assert — reasoning is the bulk of the output and must not be replayed.
      check(window.last.text).equals('Because of X.');
    });

    test('drops errored and empty messages', () {
      // Arrange
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

      // Act
      final window = historyWindow(messages, 10);

      // Assert
      check(window.map((m) => m.id)).deepEquals(<String>['q1', 'q2', 'a2']);
    });
  });

  group('needsHistoryReseat', () {
    test('is false for a short transcript with nothing to strip', () {
      // Assert — the model already holds exactly the window, so replaying it
      // would be a re-prefill for nothing.
      check(needsHistoryReseat(transcript(3), 10)).isFalse();
    });

    test('is true once the transcript outgrows the budget', () {
      check(needsHistoryReseat(transcript(11), 10)).isTrue();
    });

    test('is true when a reply carries reasoning to strip', () {
      // Arrange
      final messages = <ChatMessage>[
        _message(id: 'q', role: MessageRole.user, text: 'Why?'),
        _message(
          id: 'a',
          role: MessageRole.assistant,
          text: '<think>Working.</think>Because.',
        ),
      ];

      // Assert
      check(needsHistoryReseat(messages, 10)).isTrue();
    });

    test('is false for an empty transcript at any budget', () {
      check(needsHistoryReseat(const <ChatMessage>[], 0)).isFalse();
      check(needsHistoryReseat(const <ChatMessage>[], 10)).isFalse();
    });
  });
}

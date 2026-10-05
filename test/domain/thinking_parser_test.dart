import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/thinking_parser.dart';

void main() {
  group('splitThinking', () {
    test('treats a reply with no tags as all answer', () {
      final split = splitThinking('The capital of France is Paris.');

      check(split.thinking).isEmpty();
      check(split.answer).equals('The capital of France is Paris.');
      check(split.isOpen).isFalse();
    });

    test('separates a closed block from the answer', () {
      final split = splitThinking(
        '<think>France. Capital. Paris.</think>\n\nIt is Paris.',
      );

      check(split.thinking).equals('France. Capital. Paris.');
      check(split.answer).equals('It is Paris.');
      check(split.isOpen).isFalse();
    });

    test('reports an unclosed block as still open, with no answer', () {
      // What the stream looks like part-way through a long think.
      const partial = '<think>France. Let me recall the';

      final split = splitThinking(partial);

      check(split.thinking).equals('France. Let me recall the');
      check(split.answer).isEmpty();
      check(split.isOpen).isTrue();
    });

    test('handles a closing tag whose opener was never emitted', () {
      // Several models leave the opener to the chat template.
      const raw = 'France. Capital. Paris.</think>It is Paris.';

      final split = splitThinking(raw);

      check(split.thinking).equals('France. Capital. Paris.');
      check(split.answer).equals('It is Paris.');
      check(split.isOpen).isFalse();
    });

    test('keeps an empty reply empty rather than inventing a block', () {
      final split = splitThinking('');

      check(split.thinking).isEmpty();
      check(split.answer).isEmpty();
      check(split.isOpen).isFalse();
    });
  });
}

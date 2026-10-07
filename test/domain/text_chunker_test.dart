import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/text_chunker.dart';

void main() {
  test('text shorter than one chunk comes back whole', () {
    check(chunkText('A short note.')).deepEquals(<String>['A short note.']);
  });

  test('nothing in is nothing out', () {
    check(chunkText('   \n\n  ')).isEmpty();
  });

  test('a long document is split into several passages', () {
    final text = List<String>.filled(200, 'word').join(' ');

    final chunks = chunkText(text, size: 200, overlap: 40);

    check(chunks.length).isGreaterThan(3);
    for (final chunk in chunks) {
      // The window is a ceiling, not a target; a chunk cut at a sentence is
      // shorter, never longer.
      check(chunk.length, because: chunk).isLessOrEqual(200);
    }
  });

  test('consecutive chunks overlap, so a straddling sentence survives', () {
    final text = List<String>.generate(120, (i) => 'w$i').join(' ');

    final chunks = chunkText(text, size: 150, overlap: 50);

    check(chunks.length).isGreaterThan(1);
    // The tail of one chunk reappears at the head of the next, which is what
    // stops the one passage that answers the question being cut in half.
    final tail = chunks.first.split(' ').last;
    check(chunks[1]).contains(tail);
  });

  test('every word of the document ends up in some chunk', () {
    final text = List<String>.generate(90, (i) => 'token$i').join(' ');

    final joined = chunkText(text, size: 120, overlap: 30).join(' ');

    for (var i = 0; i < 90; i++) {
      check(joined, because: 'token$i must not be lost').contains('token$i');
    }
  });

  test('a break is taken at a paragraph when one is near the end', () {
    final first = 'A' * 90;
    final second = 'B' * 90;

    final chunks = chunkText('$first\n\n$second', size: 120, overlap: 10);

    // Split at the blank line rather than mid-run of As.
    check(chunks.first).equals(first);
  });

  test('a break is taken at a sentence end when there is no paragraph', () {
    final text = '${'a ' * 40}end. ${'b ' * 40}';

    final chunks = chunkText(text, size: 100, overlap: 10);

    check(chunks.first).endsWith('end.');
  });

  test('runs of blank lines and stray spaces are collapsed', () {
    final chunks = chunkText('One   line.\n\n\n\n  Another   line.');

    check(chunks.single).equals('One line.\n\nAnother line.');
  });

  test('windows line endings do not survive as stray characters', () {
    check(chunkText('One.\r\n\r\nTwo.').single).equals('One.\n\nTwo.');
  });

  test('a nonsensical overlap does not loop for ever', () {
    // An overlap at or above the window would make no progress per step.
    final chunks = chunkText('x' * 500, size: 100, overlap: 500);

    check(chunks).isNotEmpty();
    check(chunks.length).isLessThan(50);
  });
}

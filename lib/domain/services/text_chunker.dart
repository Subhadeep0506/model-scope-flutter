/// How big a chunk is, in characters.
///
/// Characters rather than tokens because the encoder's tokenizer is not
/// reachable from here, and for prose the ratio is near enough constant.
/// ~700 characters is roughly 150-200 tokens: small enough that four of them
/// fit a phone-sized context beside the question, large enough to hold a
/// whole argument rather than half of one.
const int kChunkSize = 700;

/// How much of the previous chunk each one repeats.
///
/// Without an overlap, a sentence that straddles a boundary is in neither
/// chunk as a whole thought, and the passage that answers the question is the
/// one most likely to be cut in half.
const int kChunkOverlap = 120;

/// Splits [text] into overlapping passages, respecting paragraph and sentence
/// boundaries where it can.
///
/// A pure function, so the chunking can be reasoned about and tested without
/// a file, a model or a database in the way.
List<String> chunkText(
  String text, {
  int size = kChunkSize,
  int overlap = kChunkOverlap,
}) {
  final normalised = _normalise(text);
  if (normalised.isEmpty) return const <String>[];
  if (normalised.length <= size) return <String>[normalised];

  // Clamped once, then used everywhere below. An overlap at or above the
  // window would otherwise advance a character at a time, turning a page of
  // text into hundreds of near-identical chunks.
  final kept = overlap.clamp(0, size ~/ 2);
  final step = (size - kept).clamp(1, size);

  final chunks = <String>[];
  var start = 0;
  while (start < normalised.length) {
    final hardEnd = (start + size).clamp(0, normalised.length);
    final end = hardEnd == normalised.length
        ? hardEnd
        : _breakBefore(normalised, start, hardEnd);

    final chunk = normalised.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);

    if (end >= normalised.length) break;
    // Measured from the break actually taken, not from the nominal window,
    // so a chunk cut short at a paragraph does not leave a gap behind it.
    start = (end - kept).clamp(start + step, normalised.length);
  }
  return chunks;
}

/// Where to cut between [start] and [hardEnd]: the last paragraph break, else
/// the last sentence end, else the last space, else [hardEnd] itself.
///
/// Only breaks in the back half of the window are considered — a paragraph
/// break just after the start would leave a chunk of two words.
int _breakBefore(String text, int start, int hardEnd) {
  final floor = start + (hardEnd - start) ~/ 2;
  final window = text.substring(start, hardEnd);

  final paragraph = window.lastIndexOf('\n\n');
  if (paragraph >= 0 && start + paragraph > floor) return start + paragraph;

  for (final terminator in const <String>['. ', '.\n', '? ', '! ']) {
    final sentence = window.lastIndexOf(terminator);
    if (sentence >= 0 && start + sentence > floor) {
      // After the stop, so the sentence stays whole.
      return start + sentence + 1;
    }
  }

  final space = window.lastIndexOf(' ');
  if (space >= 0 && start + space > floor) return start + space;
  return hardEnd;
}

/// Collapses the whitespace a PDF extractor leaves behind, without losing the
/// blank lines that mark paragraphs — those are the best chunk boundaries
/// there are.
String _normalise(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .trim();

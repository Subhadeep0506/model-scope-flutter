const int kChunkSize = 700;
const int kChunkOverlap = 120;

List<String> chunkText(
  String text, {
  int size = kChunkSize,
  int overlap = kChunkOverlap,
}) {
  final normalised = _normalise(text);
  if (normalised.isEmpty) return const <String>[];
  if (normalised.length <= size) return <String>[normalised];
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
    start = (end - kept).clamp(start + step, normalised.length);
  }
  return chunks;
}

int _breakBefore(String text, int start, int hardEnd) {
  final floor = start + (hardEnd - start) ~/ 2;
  final window = text.substring(start, hardEnd);

  final paragraph = window.lastIndexOf('\n\n');
  if (paragraph >= 0 && start + paragraph > floor) return start + paragraph;

  for (final terminator in const <String>['. ', '.\n', '? ', '! ']) {
    final sentence = window.lastIndexOf(terminator);
    if (sentence >= 0 && start + sentence > floor) {
      return start + sentence + 1;
    }
  }

  final space = window.lastIndexOf(' ');
  if (space >= 0 && start + space > floor) return start + space;
  return hardEnd;
}

String _normalise(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .trim();

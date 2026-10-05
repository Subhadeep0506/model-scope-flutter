/// A reply split into the model's reasoning and the answer it settled on.
/// [isOpen] is true while a `<think>` block has been opened but not closed.
typedef ThoughtSplit = ({String thinking, String answer, bool isOpen});

const String _openTag = '<think>';
const String _closeTag = '</think>';

/// Separates a reasoning model's `<think>` block from its answer. Four shapes
/// are handled, because models differ in what they emit: no tags, both tags,
/// an open with no close (still streaming), and a close with no open.
ThoughtSplit splitThinking(String raw) {
  final openAt = raw.indexOf(_openTag);
  final closeAt = raw.indexOf(_closeTag);

  if (openAt < 0 && closeAt < 0) {
    return (thinking: '', answer: raw.trim(), isOpen: false);
  }

  if (closeAt < 0) {
    return (
      thinking: raw.substring(openAt + _openTag.length).trim(),
      answer: '',
      isOpen: true,
    );
  }

  // A close with no open before it means the opener was never emitted.
  final start = openAt >= 0 && openAt < closeAt ? openAt + _openTag.length : 0;
  return (
    thinking: raw.substring(start, closeAt).trim(),
    answer: raw.substring(closeAt + _closeTag.length).trim(),
    isOpen: false,
  );
}

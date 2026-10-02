/// A reply split into the model's reasoning and the answer it settled on.
///
/// [isOpen] is true while a `<think>` block has been opened but not yet closed,
/// which is the normal state part-way through streaming a reasoning model.
typedef ThoughtSplit = ({String thinking, String answer, bool isOpen});

const String _openTag = '<think>';
const String _closeTag = '</think>';

/// Separates a reasoning model's `<think>` block from its answer.
///
/// Models differ in what they actually emit, so four shapes are handled:
///
/// * no tags at all — the whole string is the answer, which is every
///   non-reasoning model and the overwhelmingly common case;
/// * `<think>…</think>answer` — the documented shape;
/// * `<think>…` with no close — still streaming, so everything after the tag
///   is reasoning and there is no answer yet;
/// * `…</think>answer` with no open — several models leave the opening tag to
///   the chat template and only emit the close, so a bare closer means
///   everything before it was reasoning.
///
/// Whitespace around each part is trimmed, so a block that ends in the newline
/// before the answer does not render as a blank line.
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

import '../../data/models/chat_message.dart';
import 'thinking_parser.dart';

/// The tail of [messages] the model is allowed to see, at most [turns]
/// question-and-answer pairs long.
///
/// A model's context window is finite and the user sets this budget, so an
/// unbounded transcript is replayed as its last [turns] questions and whatever
/// followed them. [turns] of zero means every prompt is answered cold.
///
/// Two things are dropped on the way out, both because the model cannot use
/// them: messages that are empty or carry a generation error, and the
/// `<think>` block of any reply that has one — reasoning is usually the bulk
/// of a reasoning model's output, so replaying it would spend the budget this
/// window exists to protect.
List<ChatMessage> historyWindow(List<ChatMessage> messages, int turns) {
  if (turns <= 0) return const <ChatMessage>[];

  final from = _startOfLastTurns(messages, turns);
  final window = <ChatMessage>[];
  for (final message in messages.skip(from)) {
    if (message.error != null) continue;
    final text = message.isUser
        ? message.text.trim()
        : splitThinking(message.text).answer;
    if (text.isEmpty) continue;
    window.add(message.copyWith(text: text));
  }
  return window;
}

/// Whether [messages] has to be replayed before the model answers again.
///
/// `nobodywho` keeps every prompt it was given and every token it generated,
/// so after a plain `ask` its context is the transcript verbatim. That is
/// already the right thing while the transcript fits the budget and no reply
/// carried a `<think>` block; once either stops holding, the model is holding
/// more than the user asked it to.
///
/// Replaying forces a re-prefill, which is slow on-device, so this exists to
/// keep it to the turns that actually need it.
bool needsHistoryReseat(List<ChatMessage> messages, int turns) {
  final window = historyWindow(messages, turns);
  if (window.length != messages.length) return true;
  for (var i = 0; i < window.length; i++) {
    if (window[i].text != messages[i].text) return true;
  }
  return false;
}

/// The index of the [turns]-from-last user message, or 0 when the transcript
/// holds fewer turns than that.
int _startOfLastTurns(List<ChatMessage> messages, int turns) {
  var seen = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (!messages[i].isUser) continue;
    seen++;
    if (seen == turns) return i;
  }
  return 0;
}

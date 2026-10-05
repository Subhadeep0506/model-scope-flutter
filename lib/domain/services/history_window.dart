import '../../data/models/chat_message.dart';
import 'thinking_parser.dart';

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

/// [message]'s text with a line naming each of its images in front of it.
///
/// Replaying a transcript re-feeds it as text, so an image that was sent on an
/// earlier turn is named rather than shown again: a second pass through the
/// projector would cost hundreds of tokens of a context the user has budgeted
/// in turns, and would fail outright if the file had since been deleted.
///
/// Kept out of [historyWindow] on purpose. That function's output is compared
/// against the stored text by [needsHistoryReseat], so marking it up there
/// would force a reseat on every turn of a conversation holding images.
String withImageMarkers(ChatMessage message) {
  if (message.imagePaths.isEmpty) return message.text;
  final markers = message.imagePaths.map((path) => '[image: ${_nameOf(path)}]');
  return '${markers.join('\n')}\n${message.text}';
}

String _nameOf(String path) => path.split(RegExp(r'[\\/]')).last;

bool needsHistoryReseat(List<ChatMessage> messages, int turns) {
  final window = historyWindow(messages, turns);
  if (window.length != messages.length) return true;
  for (var i = 0; i < window.length; i++) {
    if (window[i].text != messages[i].text) return true;
  }
  return false;
}

int _startOfLastTurns(List<ChatMessage> messages, int turns) {
  var seen = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (!messages[i].isUser) continue;
    seen++;
    if (seen == turns) return i;
  }
  return 0;
}

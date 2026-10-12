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

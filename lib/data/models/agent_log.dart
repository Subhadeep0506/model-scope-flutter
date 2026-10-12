class AgentLogEntry {
  const AgentLogEntry({
    required this.at,
    required this.channel,
    required this.text,
    this.isError = false,
  });

  final DateTime at;

  final String channel;

  final String text;

  final bool isError;

  static const List<String> channels = <String>[
    'load',
    'system',
    'step',
    'prompt',
    'reply',
    'tool',
    'args',
    'result',
    'error',
    'done',
  ];

  String get timeLabel {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    final second = at.second.toString().padLeft(2, '0');
    final milli = at.millisecond.toString().padLeft(3, '0');
    return '$hour:$minute:$second.$milli';
  }

  String get asText => '$timeLabel  ${channel.padRight(6)}  $text';
}

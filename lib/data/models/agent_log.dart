/// One line of the verbose log a run writes as it goes.
///
/// Deliberately not serialisable. The trace is the summary and is kept in
/// `agent_runs.json`; this is the full detail behind it — every prompt sent,
/// every raw reply, every tool's arguments and result untruncated. A single
/// scraped page runs to tens of kilobytes, and fifty of those in the history
/// file would cost the user more storage than the transcripts do. So the log
/// lives for as long as the run screen is open and no longer.
class AgentLogEntry {
  const AgentLogEntry({
    required this.at,
    required this.channel,
    required this.text,
    this.isError = false,
  });

  /// Stamped `09:14:02.113` down the left of the log sheet.
  final DateTime at;

  /// What kind of line this is, printed in mono beside the stamp. One of
  /// [channels] — a short word rather than an enum because the set is a
  /// presentation detail, and a new one should not mean a new type.
  final String channel;

  /// The line itself, in full. Wrapped rather than clipped in the sheet.
  final String text;

  /// Drawn in the danger colour. Set on a failure, and on a tool step where
  /// the model never reached for the tool it was given.
  final bool isError;

  /// Every channel the runner writes, in the order a run produces them. Listed
  /// so the sheet can size its gutter to the longest.
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

  /// `09:14:02.113`, the stamp at the head of the row.
  String get timeLabel {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    final second = at.second.toString().padLeft(2, '0');
    final milli = at.millisecond.toString().padLeft(3, '0');
    return '$hour:$minute:$second.$milli';
  }

  /// One line of the plain-text copy the sheet's `Copy all` puts on the
  /// clipboard, so a log can be pasted into a bug report as it was read.
  String get asText => '$timeLabel  ${channel.padRight(6)}  $text';
}

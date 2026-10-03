/// Formats an instant as the short relative stamp the Home mockup prints down
/// the right-hand edge of every activity row: `4h ago`, `2d ago`.
///
/// Deliberately coarse. The exact timestamp already has a home on the session
/// rows in Chats; here the only question is how recent something is, so the
/// label stays one unit wide and never wraps.
String formatAgo(DateTime moment, DateTime now) {
  final elapsed = now.difference(moment);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 7}w ago';
  return '${elapsed.inDays ~/ 365}y ago';
}

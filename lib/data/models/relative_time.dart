String formatAgo(DateTime moment, DateTime now) {
  final elapsed = now.difference(moment);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 7}w ago';
  return '${elapsed.inDays ~/ 365}y ago';
}

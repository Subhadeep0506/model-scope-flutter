import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/chat_session.dart';

/// The right-hand dropdown on the Chats screen.
enum SessionTimeFilter {
  all('All time'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days');

  const SessionTimeFilter(this.label);

  final String label;

  /// Oldest `updatedAt` this filter admits, or `null` for no lower bound.
  DateTime? floor(DateTime now) => switch (this) {
    SessionTimeFilter.all => null,
    SessionTimeFilter.today => DateTime(now.year, now.month, now.day),
    SessionTimeFilter.week => now.subtract(const Duration(days: 7)),
    SessionTimeFilter.month => now.subtract(const Duration(days: 30)),
  };
}

/// Search text plus the two dropdowns, kept out of the widget tree so the
/// Chats screen stays a pure observer.
class SessionFilter {
  const SessionFilter({
    this.query = '',
    this.modelId,
    this.time = SessionTimeFilter.all,
  });

  final String query;

  /// `null` means "All models".
  final String? modelId;

  final SessionTimeFilter time;

  bool get isActive =>
      query.isNotEmpty || modelId != null || time != SessionTimeFilter.all;

  bool matches(ChatSession session, DateTime now) {
    if (modelId != null && session.modelId != modelId) return false;

    final floor = time.floor(now);
    if (floor != null && session.updatedAt.isBefore(floor)) return false;

    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return session.title.toLowerCase().contains(needle);
  }

  SessionFilter copyWith({
    String? query,
    String? modelId,
    SessionTimeFilter? time,
    bool clearModel = false,
  }) => SessionFilter(
    query: query ?? this.query,
    modelId: clearModel ? null : (modelId ?? this.modelId),
    time: time ?? this.time,
  );
}

class SessionFilterViewModel extends Notifier<SessionFilter> {
  @override
  SessionFilter build() => const SessionFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setModel(String? modelId) =>
      state = state.copyWith(modelId: modelId, clearModel: modelId == null);

  void setTime(SessionTimeFilter time) => state = state.copyWith(time: time);

  void clear() => state = const SessionFilter();
}

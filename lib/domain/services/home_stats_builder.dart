import '../../data/models/byte_size.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/generation_metrics.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/model_library_repository.dart';

/// How many rows the Recent activity feed shows before it stops.
const int _activityLimit = 8;

/// How many days the latency trend covers.
const int _trendDays = 7;

/// Folds the stored sessions and the installed models into everything Home
/// draws.
///
/// Pure, synchronous and free of Flutter: Home watches two view models that
/// already hold this state, so there is nothing to load and nothing to persist.
/// Keeping it a function rather than a notifier is what makes the whole
/// dashboard testable without a widget or a device.
HomeStats buildHomeStats({
  required List<ChatSession> sessions,
  required ModelLibrary library,
  required DateTime now,
}) {
  final replies = _repliesOf(sessions);
  if (replies.isEmpty && library.isEmpty && sessions.isEmpty) {
    return HomeStats.empty;
  }

  final peak = _peakOf(replies);
  return HomeStats(
    totalTokens: replies.fold(0, (sum, r) => sum + r.metrics.tokenCount),
    averageLatencyMs: _meanLatency(replies),
    peakTokensPerSecond: peak?.metrics.tokensPerSecond ?? 0,
    peakModelName: _nameOf(library, peak?.modelId),
    modelCount: library.models.length,
    modelBytes: library.totalBytes,
    repliesToday: _countToday(replies, now),
    sessionCount: sessions.length,
    latencyTrend: _trend(replies, now),
    throughputBySize: _throughputBySize(replies, library),
    modelUsage: _usage(sessions, library),
    activity: _activity(sessions, library),
  );
}

/// One finished reply, flattened out of the session it belongs to so the folds
/// below never have to walk the nesting again.
class _Reply {
  const _Reply({
    required this.at,
    required this.metrics,
    required this.modelId,
  });

  final DateTime at;
  final GenerationMetrics metrics;
  final String modelId;
}

List<_Reply> _repliesOf(List<ChatSession> sessions) => <_Reply>[
  for (final session in sessions)
    for (final message in session.messages)
      if (message.role == MessageRole.assistant)
        if (message.metrics case final metrics?)
          _Reply(
            at: message.createdAt,
            metrics: metrics,
            modelId: session.modelId,
          ),
];

_Reply? _peakOf(List<_Reply> replies) {
  _Reply? best;
  for (final reply in replies) {
    final current = best;
    if (current == null ||
        reply.metrics.tokensPerSecond > current.metrics.tokensPerSecond) {
      best = reply;
    }
  }
  return best;
}

int _meanLatency(List<_Reply> replies) {
  if (replies.isEmpty) return 0;
  final total = replies.fold<int>(0, (sum, r) => sum + r.metrics.latencyMs);
  return (total / replies.length).round();
}

int _countToday(List<_Reply> replies, DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day);
  return replies.where((r) => !r.at.isBefore(midnight)).length;
}

/// Seven buckets ending today. A day nothing was generated on carries a null
/// average, which the chart draws as a gap rather than as a drop to zero.
List<DailyLatency> _trend(List<_Reply> replies, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return <DailyLatency>[
    for (var back = _trendDays - 1; back >= 0; back--)
      _bucket(replies, today.subtract(Duration(days: back))),
  ];
}

DailyLatency _bucket(List<_Reply> replies, DateTime day) {
  final next = day.add(const Duration(days: 1));
  final onDay = replies
      .where((r) => !r.at.isBefore(day) && r.at.isBefore(next))
      .toList();
  return DailyLatency(
    day: day,
    averageLatencyMs: onDay.isEmpty ? null : _meanLatency(onDay),
  );
}

/// Mean throughput per parameter size, smallest first.
///
/// Models whose manifest entry states no parameter count are left out — an
/// unlabelled bar would say nothing, and the axis in the mockup is a size scale.
List<SizeThroughput> _throughputBySize(
  List<_Reply> replies,
  ModelLibrary library,
) {
  final totals = <String, List<double>>{};
  for (final reply in replies) {
    final label = library.byId(reply.modelId)?.paramLabel;
    if (label == null) continue;
    totals
        .putIfAbsent(label, () => <double>[])
        .add(reply.metrics.tokensPerSecond);
  }

  final bars = <SizeThroughput>[
    for (final entry in totals.entries)
      SizeThroughput(
        paramLabel: entry.key,
        tokensPerSecond:
            entry.value.reduce((a, b) => a + b) / entry.value.length,
      ),
  ];
  return bars
    ..sort((a, b) => _params(a.paramLabel).compareTo(_params(b.paramLabel)));
}

/// `360M` → 360000000, `1.5B` → 1500000000, so the bars sort by actual size
/// rather than alphabetically — which would put `1.5B` before `360M`.
double _params(String label) {
  final match = RegExp(
    r'([\d.]+)\s*([MB])',
    caseSensitive: false,
  ).firstMatch(label);
  if (match == null) return 0;
  final value = double.tryParse(match.group(1) ?? '') ?? 0;
  final unit = (match.group(2) ?? '').toUpperCase();
  return unit == 'B' ? value * 1000000000 : value * 1000000;
}

/// Installed models, the ones that have answered something first.
List<ModelUsage> _usage(List<ChatSession> sessions, ModelLibrary library) {
  final used = <String, List<_Reply>>{};
  for (final reply in _repliesOf(sessions)) {
    used.putIfAbsent(reply.modelId, () => <_Reply>[]).add(reply);
  }

  final rows = <ModelUsage>[
    for (final model in library.models)
      _usageOf(model, used[model.id] ?? const <_Reply>[]),
  ];
  rows.sort((a, b) {
    if (a.runs != b.runs) return b.runs.compareTo(a.runs);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}

ModelUsage _usageOf(ModelDescriptor model, List<_Reply> replies) {
  DateTime? last;
  for (final reply in replies) {
    if (last == null || reply.at.isAfter(last)) last = reply.at;
  }
  return ModelUsage(
    modelId: model.id,
    name: model.name,
    quantization: model.quantization,
    runs: replies.length,
    averageLatencyMs: _meanLatency(replies),
    lastUsedAt: last,
  );
}

/// Sessions and downloads merged, newest first.
///
/// Agent runs belong here too and are the majority of the rows in the mockup;
/// they join once agents exist, without this feed changing shape.
List<ActivityEntry> _activity(
  List<ChatSession> sessions,
  ModelLibrary library,
) {
  final entries = <ActivityEntry>[
    for (final session in sessions)
      ActivityEntry(
        kind: ActivityKind.session,
        title: 'Session "${session.title}"',
        subtitle:
            '${_slugOf(session.modelId, library)} · '
            '${session.messageCount} messages',
        at: session.updatedAt,
      ),
    for (final model in library.models)
      ActivityEntry(
        kind: ActivityKind.install,
        title: 'Pulled ${model.name}',
        subtitle: '${model.quantization} · ${formatBytes(model.sizeBytes)}',
        at: model.installedAt,
      ),
  ];

  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries.take(_activityLimit).toList();
}

/// The mono slug the mockup prints under a session title: `smollm2-360m`.
///
/// A session created before anything was installed carries no model id at all,
/// which is the ordinary state on a fresh install — saying `removed model`
/// there would claim something was deleted that never existed.
String _slugOf(String modelId, ModelLibrary library) {
  if (modelId.isEmpty) return 'no model';

  final model = library.byId(modelId);
  if (model == null) return 'removed model';

  final repo = model.repoId.split('/').last;
  return repo
      .replaceAll(RegExp(r'-GGUF$', caseSensitive: false), '')
      .toLowerCase();
}

/// The model a reply came from, as named in the library. Null once that model
/// has been removed, which the peak tile renders as no caption at all.
String? _nameOf(ModelLibrary library, String? modelId) =>
    modelId == null ? null : library.byId(modelId)?.name;

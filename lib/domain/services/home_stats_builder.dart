import '../../data/models/agent_run.dart';
import '../../data/models/byte_size.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/usage_record.dart';
import '../../data/repositories/model_library_repository.dart';

const int _activityLimit = 8;

/// How many days the latency trend covers.
const int _trendDays = 7;

/// Home's figures.
///
/// Where each comes from matters, and the split is deliberate. Everything
/// about performance — tokens, latency, throughput, which model did what —
/// is folded out of [usage], the permanent ledger, so deleting a chat cannot
/// lower a figure for work that really happened. Everything about what
/// currently exists — how many sessions there are, what is in the activity
/// feed — still comes from [sessions] and [library], because a count of
/// things on the device has to be honest about the device.
HomeStats buildHomeStats({
  required List<ChatSession> sessions,
  required ModelLibrary library,
  required DateTime now,
  UsageLedger usage = UsageLedger.empty,
  List<AgentRun> runs = const <AgentRun>[],
  int agentCount = 0,
}) {
  // `runs` is in the guard as well as `usage` because the two are written
  // separately: a run recorded before the ledger existed is still activity
  // worth drawing, and folding to empty would hide the whole feed.
  if (usage.isEmpty && library.isEmpty && sessions.isEmpty && runs.isEmpty) {
    return HomeStats.empty;
  }

  final totals = usage.totals;
  return HomeStats(
    totalTokens: totals.tokens,
    averageLatencyMs: totals.averageLatencyMs,
    peakTokensPerSecond: totals.peakTokensPerSecond,
    peakModelName: totals.peakModelName,
    modelCount: library.models.length,
    modelBytes: library.totalBytes,
    repliesToday: _countToday(usage.recent, now),
    sessionCount: sessions.length,
    latencyTrend: _trend(usage.recent, now),
    throughputBySize: _throughputBySize(usage),
    modelUsage: _usage(usage, library),
    activity: _activity(sessions, library, runs),
    agentRuns: totals.agentRuns,
    agentCount: agentCount,
  );
}

int _meanLatency(List<UsageRecord> replies) {
  if (replies.isEmpty) return 0;
  final total = replies.fold<int>(0, (sum, r) => sum + r.latencyMs);
  return (total / replies.length).round();
}

int _countToday(List<UsageRecord> replies, DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day);
  return replies.where((r) => !r.at.isBefore(midnight)).length;
}

/// Seven buckets ending today. A day nothing was generated on carries a null
/// average, which the chart draws as a gap rather than as a drop to zero.
List<DailyLatency> _trend(List<UsageRecord> replies, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return <DailyLatency>[
    for (var back = _trendDays - 1; back >= 0; back--)
      _bucket(replies, today.subtract(Duration(days: back))),
  ];
}

DailyLatency _bucket(List<UsageRecord> replies, DateTime day) {
  final next = day.add(const Duration(days: 1));
  final onDay = replies
      .where((r) => !r.at.isBefore(day) && r.at.isBefore(next))
      .toList();
  return DailyLatency(
    day: day,
    averageLatencyMs: onDay.isEmpty ? null : _meanLatency(onDay),
  );
}

/// Mean throughput per parameter size, smallest first. Models with no stated
/// parameter count are left out; an unlabelled bar on a size axis says nothing.
///
/// Reads the size off the ledger rather than the library, so a bar survives
/// the model that earned it being deleted — which is the point of recording
/// the label on every row in the first place.
List<SizeThroughput> _throughputBySize(UsageLedger usage) {
  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final model in usage.byModel.values) {
    final label = model.paramLabel;
    if (label == null || model.replies == 0) continue;
    sums[label] = (sums[label] ?? 0) + model.tokensPerSecondSum;
    counts[label] = (counts[label] ?? 0) + model.replies;
  }

  final bars = <SizeThroughput>[
    for (final entry in sums.entries)
      SizeThroughput(
        paramLabel: entry.key,
        tokensPerSecond: entry.value / (counts[entry.key] ?? 1),
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

/// Every model that has answered something, plus the installed ones that have
/// not yet — which is what tells the user a download is sitting unused.
///
/// A model that has been deleted keeps its row: the replies it produced are
/// still part of what this device has done, and dropping the row was the old
/// behaviour that made the list shrink under the user.
List<ModelUsage> _usage(UsageLedger usage, ModelLibrary library) {
  final rows = <ModelUsage>[
    for (final model in usage.byModel.values)
      if (model.replies > 0)
        ModelUsage(
          modelId: model.modelId,
          // The library's name wins while the model is installed, so a
          // rename in the catalog shows up; the recorded one takes over
          // once the weights are gone.
          name: library.byId(model.modelId)?.name ?? _named(model),
          quantization:
              library.byId(model.modelId)?.quantization ?? model.quantization,
          runs: model.replies,
          averageLatencyMs: model.averageLatencyMs,
          lastUsedAt: model.lastUsedAt,
          isInstalled: library.byId(model.modelId) != null,
        ),
    for (final model in library.models)
      if ((usage.byModel[model.id]?.replies ?? 0) == 0) _unused(model),
  ];
  rows.sort((a, b) {
    if (a.runs != b.runs) return b.runs.compareTo(a.runs);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}

/// What to call a model whose weights have gone. The recorded name when there
/// is one, and the file it came from when there is not.
String _named(ModelTotals model) =>
    model.name.isNotEmpty ? model.name : model.modelId.split('/').last;

ModelUsage _unused(ModelDescriptor model) => ModelUsage(
  modelId: model.id,
  name: model.name,
  quantization: model.quantization,
  runs: 0,
  averageLatencyMs: 0,
  lastUsedAt: null,
);

/// Sessions, downloads and agent runs merged, newest first.
List<ActivityEntry> _activity(
  List<ChatSession> sessions,
  ModelLibrary library,
  List<AgentRun> runs,
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
    for (final run in runs)
      ActivityEntry(
        kind: ActivityKind.agentRun,
        title: run.succeeded
            ? 'Ran ${run.agentName}'
            : '${run.agentName} failed',
        subtitle: run.statsLabel,
        at: run.startedAt,
      ),
  ];

  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries.take(_activityLimit).toList();
}

/// The mono slug under a session title: `smollm2-360m`. A session created
/// before anything was installed carries no model id — ordinary on a fresh
/// install — so it reads `no model` rather than `removed model`.
String _slugOf(String modelId, ModelLibrary library) {
  if (modelId.isEmpty) return 'no model';

  final model = library.byId(modelId);
  if (model == null) return 'removed model';

  final repo = model.repoId.split('/').last;
  return repo
      .replaceAll(RegExp(r'-GGUF$', caseSensitive: false), '')
      .toLowerCase();
}

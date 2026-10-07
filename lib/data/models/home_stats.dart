import 'byte_size.dart';

/// Everything the Home dashboard draws, rebuilt each time Home builds.
///
/// The figures come from two different places, and which is which matters.
/// Performance — tokens, latency, throughput, per-model usage, agent runs —
/// is folded out of the persisted usage ledger, so it is lifetime and
/// deleting a chat does not lower it. Counts of what exists — [sessionCount],
/// [modelCount], [modelBytes], the session rows in [activity] — come from the
/// sessions and the model library, so they stay honest about the device.
class HomeStats {
  const HomeStats({
    required this.totalTokens,
    required this.averageLatencyMs,
    required this.peakTokensPerSecond,
    required this.peakModelName,
    required this.modelCount,
    required this.modelBytes,
    required this.repliesToday,
    required this.sessionCount,
    required this.latencyTrend,
    required this.throughputBySize,
    required this.modelUsage,
    required this.activity,
    this.agentRuns = 0,
    this.agentCount = 0,
  });

  static const HomeStats empty = HomeStats(
    totalTokens: 0,
    averageLatencyMs: 0,
    peakTokensPerSecond: 0,
    peakModelName: null,
    modelCount: 0,
    modelBytes: 0,
    repliesToday: 0,
    sessionCount: 0,
    latencyTrend: <DailyLatency>[],
    throughputBySize: <SizeThroughput>[],
    modelUsage: <ModelUsage>[],
    activity: <ActivityEntry>[],
  );

  /// Tokens across every reply this device has ever finished.
  final int totalTokens;

  /// Mean time to first token, in milliseconds.
  final int averageLatencyMs;

  /// Best throughput any single reply reached.
  final double peakTokensPerSecond;

  /// Which model reached [peakTokensPerSecond]. Null before the first reply.
  final String? peakModelName;

  final int modelCount;
  final int modelBytes;

  /// Replies generated since midnight.
  final int repliesToday;

  final int sessionCount;

  /// Seven buckets, oldest first, one per day up to and including today.
  final List<DailyLatency> latencyTrend;

  /// Mean throughput per parameter size, smallest model first.
  final List<SizeThroughput> throughputBySize;

  /// Every model that has answered something, busiest first, then the
  /// installed ones that have not.
  final List<ModelUsage> modelUsage;

  /// Sessions and downloads merged, newest first.
  final List<ActivityEntry> activity;

  /// Every agent run this device has finished. Counted in the ledger rather
  /// than from the run history file, which is capped at fifty — so this is
  /// "ever", unlike the traces behind it.
  final int agentRuns;

  /// Agents this build offers, bundled and custom together.
  final int agentCount;

  /// What the charts and the usage list show their empty copy for.
  bool get hasNoReplies => totalTokens == 0 && averageLatencyMs == 0;

  /// `8.06 GB`, matching the Settings models heading.
  String get modelBytesLabel => formatBytes(modelBytes);
}

/// One day of the latency trend. [averageLatencyMs] is null on a day with no
/// replies, which the chart draws as a gap rather than as a zero.
class DailyLatency {
  const DailyLatency({required this.day, required this.averageLatencyMs});

  /// Midnight on the day this bucket covers.
  final DateTime day;

  final int? averageLatencyMs;
}

/// Mean throughput for every model of one parameter size.
class SizeThroughput {
  const SizeThroughput({
    required this.paramLabel,
    required this.tokensPerSecond,
  });

  /// `360M`, `1.5B`.
  final String paramLabel;

  final double tokensPerSecond;
}

/// One row of the Models used list.
class ModelUsage {
  const ModelUsage({
    required this.modelId,
    required this.name,
    required this.quantization,
    required this.runs,
    required this.averageLatencyMs,
    required this.lastUsedAt,
    this.isInstalled = true,
  });

  final String modelId;
  final String name;
  final String quantization;

  /// Replies this model produced. Zero for an installed model nothing has
  /// chatted with yet.
  final int runs;

  final int averageLatencyMs;

  /// Null when [runs] is zero.
  final DateTime? lastUsedAt;

  /// Whether the weights are still on the device. A removed model keeps its
  /// row — the replies it produced still happened — but the row says so, so
  /// the list is not read as an inventory.
  final bool isInstalled;
}

/// What kind of thing happened, which picks the glyph on an activity row.
enum ActivityKind { session, install, agentRun }

/// One row of the Recent activity feed.
class ActivityEntry {
  const ActivityEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
  });

  final ActivityKind kind;
  final String title;

  /// The mono line under the title: `smollm2-360m · 18 messages`.
  final String subtitle;

  final DateTime at;
}

import 'byte_size.dart';

/// Everything the Home dashboard draws. Nothing here is persisted; every figure
/// is folded out of the stored sessions and the model library each time Home
/// builds, so deleting a session lowers the totals — hence the captions saying
/// "across stored sessions" rather than "lifetime".
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

  /// Tokens across every finished reply still on the device.
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

  /// Installed models, the ones that have answered something first.
  final List<ModelUsage> modelUsage;

  /// Sessions and downloads merged, newest first.
  final List<ActivityEntry> activity;

  /// Agents are not in this build, so these are zero — getters rather than
  /// fields, so there is nothing to pass in until they exist.
  int get agentRuns => 0;
  int get agentCount => 0;

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

import 'byte_size.dart';

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

  final int totalTokens;

  final int averageLatencyMs;

  final double peakTokensPerSecond;

  final String? peakModelName;

  final int modelCount;
  final int modelBytes;

  final int repliesToday;

  final int sessionCount;

  final List<DailyLatency> latencyTrend;

  final List<SizeThroughput> throughputBySize;

  final List<ModelUsage> modelUsage;

  final List<ActivityEntry> activity;

  final int agentRuns;

  final int agentCount;

  bool get hasNoReplies => totalTokens == 0 && averageLatencyMs == 0;

  String get modelBytesLabel => formatBytes(modelBytes);
}

class DailyLatency {
  const DailyLatency({required this.day, required this.averageLatencyMs});

  final DateTime day;

  final int? averageLatencyMs;
}

class SizeThroughput {
  const SizeThroughput({
    required this.paramLabel,
    required this.tokensPerSecond,
  });

  final String paramLabel;

  final double tokensPerSecond;
}

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

  final int runs;

  final int averageLatencyMs;

  final DateTime? lastUsedAt;

  final bool isInstalled;
}

enum ActivityKind { session, install, agentRun }

class ActivityEntry {
  const ActivityEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
  });

  final ActivityKind kind;
  final String title;

  final String subtitle;

  final DateTime at;
}

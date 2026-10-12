import 'package:json_annotation/json_annotation.dart';

import 'chat_message.dart';
import 'chat_session.dart';

part 'usage_record.g.dart';

@JsonEnum()
enum UsageKind {
  @JsonValue('chat')
  chat,
  @JsonValue('agent_run')
  agentRun,
}

@JsonSerializable(fieldRename: FieldRename.snake)
class UsageRecord {
  const UsageRecord({
    required this.at,
    required this.modelId,
    required this.tokenCount,
    required this.latencyMs,
    required this.tokensPerSecond,
    this.kind = UsageKind.chat,
    this.modelName = '',
    this.paramLabel,
    this.quantization = '',
    this.agentId,
  });

  factory UsageRecord.fromJson(Map<String, dynamic> json) =>
      _$UsageRecordFromJson(json);

  final DateTime at;

  final String modelId;

  final int tokenCount;
  final int latencyMs;
  final double tokensPerSecond;

  @JsonKey(defaultValue: UsageKind.chat)
  final UsageKind kind;

  @JsonKey(defaultValue: '')
  final String modelName;

  final String? paramLabel;

  @JsonKey(defaultValue: '')
  final String quantization;

  final String? agentId;

  Map<String, dynamic> toJson() => _$UsageRecordToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class UsageTotals {
  const UsageTotals({
    this.replies = 0,
    this.tokens = 0,
    this.latencySumMs = 0,
    this.peakTokensPerSecond = 0,
    this.peakModelId,
    this.peakModelName,
    this.agentRuns = 0,
  });

  factory UsageTotals.fromJson(Map<String, dynamic> json) =>
      _$UsageTotalsFromJson(json);

  static const UsageTotals empty = UsageTotals();

  @JsonKey(defaultValue: 0)
  final int replies;

  @JsonKey(defaultValue: 0)
  final int tokens;

  @JsonKey(defaultValue: 0)
  final int latencySumMs;

  @JsonKey(defaultValue: 0)
  final double peakTokensPerSecond;

  final String? peakModelId;

  final String? peakModelName;

  @JsonKey(defaultValue: 0)
  final int agentRuns;

  int get averageLatencyMs =>
      replies == 0 ? 0 : (latencySumMs / replies).round();

  UsageTotals plus(UsageRecord record) => UsageTotals(
    replies: replies + 1,
    tokens: tokens + record.tokenCount,
    latencySumMs: latencySumMs + record.latencyMs,
    peakTokensPerSecond: record.tokensPerSecond > peakTokensPerSecond
        ? record.tokensPerSecond
        : peakTokensPerSecond,
    peakModelId: record.tokensPerSecond > peakTokensPerSecond
        ? record.modelId
        : peakModelId,
    peakModelName: record.tokensPerSecond > peakTokensPerSecond
        ? record.modelName
        : peakModelName,
    agentRuns: agentRuns + (record.kind == UsageKind.agentRun ? 1 : 0),
  );

  Map<String, dynamic> toJson() => _$UsageTotalsToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ModelTotals {
  const ModelTotals({
    required this.modelId,
    this.name = '',
    this.quantization = '',
    this.paramLabel,
    this.replies = 0,
    this.tokens = 0,
    this.latencySumMs = 0,
    this.tokensPerSecondSum = 0,
    this.lastUsedAt,
  });

  factory ModelTotals.fromJson(Map<String, dynamic> json) =>
      _$ModelTotalsFromJson(json);

  final String modelId;

  @JsonKey(defaultValue: '')
  final String name;

  @JsonKey(defaultValue: '')
  final String quantization;

  final String? paramLabel;

  @JsonKey(defaultValue: 0)
  final int replies;

  @JsonKey(defaultValue: 0)
  final int tokens;

  @JsonKey(defaultValue: 0)
  final int latencySumMs;

  @JsonKey(defaultValue: 0)
  final double tokensPerSecondSum;

  final DateTime? lastUsedAt;

  int get averageLatencyMs =>
      replies == 0 ? 0 : (latencySumMs / replies).round();

  double get averageTokensPerSecond =>
      replies == 0 ? 0 : tokensPerSecondSum / replies;

  ModelTotals plus(UsageRecord record) {
    final last = lastUsedAt;
    return ModelTotals(
      modelId: modelId,

      name: record.modelName.isEmpty ? name : record.modelName,
      quantization: record.quantization.isEmpty
          ? quantization
          : record.quantization,
      paramLabel: record.paramLabel ?? paramLabel,
      replies: replies + 1,
      tokens: tokens + record.tokenCount,
      latencySumMs: latencySumMs + record.latencyMs,
      tokensPerSecondSum: tokensPerSecondSum + record.tokensPerSecond,
      lastUsedAt: last == null || record.at.isAfter(last) ? record.at : last,
    );
  }

  Map<String, dynamic> toJson() => _$ModelTotalsToJson(this);
}

class UsageLedger {
  const UsageLedger({
    this.recent = const <UsageRecord>[],
    this.totals = UsageTotals.empty,
    this.byModel = const <String, ModelTotals>{},
    this.migrated = false,
  });

  static const UsageLedger empty = UsageLedger();

  final List<UsageRecord> recent;

  final UsageTotals totals;

  final Map<String, ModelTotals> byModel;

  final bool migrated;

  bool get isEmpty => totals.replies == 0 && totals.agentRuns == 0;

  UsageLedger plus(UsageRecord record) => UsageLedger(
    recent: <UsageRecord>[...recent, record],
    totals: totals.plus(record),
    byModel: <String, ModelTotals>{
      ...byModel,

      record.modelId:
          (byModel[record.modelId] ?? ModelTotals(modelId: record.modelId))
              .plus(record),
    },
    migrated: migrated,
  );

  UsageLedger copyWith({
    List<UsageRecord>? recent,
    UsageTotals? totals,
    Map<String, ModelTotals>? byModel,
    bool? migrated,
  }) => UsageLedger(
    recent: recent ?? this.recent,
    totals: totals ?? this.totals,
    byModel: byModel ?? this.byModel,
    migrated: migrated ?? this.migrated,
  );
}

List<UsageRecord> recordsFromSessions(
  List<ChatSession> sessions, {
  String Function(String modelId)? nameOf,
}) {
  final records = <UsageRecord>[
    for (final session in sessions)
      for (final message in session.messages)
        if (message.role == MessageRole.assistant && message.error == null)
          if (message.metrics case final metrics?)
            UsageRecord(
              at: message.createdAt,
              modelId: session.modelId,
              modelName: nameOf?.call(session.modelId) ?? '',
              tokenCount: metrics.tokenCount,
              latencyMs: metrics.latencyMs,
              tokensPerSecond: metrics.tokensPerSecond,
            ),
  ];
  return records..sort((a, b) => a.at.compareTo(b.at));
}

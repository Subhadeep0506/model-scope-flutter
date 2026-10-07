import 'package:json_annotation/json_annotation.dart';

import 'chat_message.dart';
import 'chat_session.dart';

part 'usage_record.g.dart';

/// What produced a reply, which separates the figures Chat earned from the
/// ones an agent run did.
@JsonEnum()
enum UsageKind {
  @JsonValue('chat')
  chat,
  @JsonValue('agent_run')
  agentRun,
}

/// One finished reply, recorded the moment it finished.
///
/// A copy rather than a reference: a record has to outlive the session its
/// reply was in, which is the whole point of the ledger. The model's name and
/// size are copied too, so a figure still reads sensibly after the weights
/// have been deleted.
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

  /// `repo/file.gguf`, matching [ModelDescriptor.id].
  final String modelId;

  final int tokenCount;
  final int latencyMs;
  final double tokensPerSecond;

  @JsonKey(defaultValue: UsageKind.chat)
  final UsageKind kind;

  /// What the model was called when this ran.
  @JsonKey(defaultValue: '')
  final String modelName;

  /// `1.5B`. Null when the model never stated one.
  final String? paramLabel;

  @JsonKey(defaultValue: '')
  final String quantization;

  /// Which agent, on an [UsageKind.agentRun] record. Null on a chat reply.
  final String? agentId;

  Map<String, dynamic> toJson() => _$UsageRecordToJson(this);
}

/// Figures that only ever go up.
///
/// Kept apart from the records they were folded out of so that pruning old
/// records cannot lower a lifetime total — which is exactly what deleting a
/// session used to do.
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

  /// Summed rather than averaged, so adding one reply does not need the whole
  /// history back to recompute the mean.
  @JsonKey(defaultValue: 0)
  final int latencySumMs;

  @JsonKey(defaultValue: 0)
  final double peakTokensPerSecond;

  final String? peakModelId;

  /// The name the peak model had when it set the record, so the caption
  /// survives the model being deleted.
  final String? peakModelName;

  /// Every agent run ever finished. Counted here rather than from the run
  /// history file, which is capped at fifty.
  @JsonKey(defaultValue: 0)
  final int agentRuns;

  int get averageLatencyMs =>
      replies == 0 ? 0 : (latencySumMs / replies).round();

  /// [this] with [record] folded in.
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

/// Lifetime figures for one model.
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

  /// Summed throughput, for the same reason [latencySumMs] is summed: the
  /// mean has to be computable without the records it came from, which are
  /// pruned as they age.
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
      // The latest naming wins, so a catalog rename shows through.
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

/// Everything the dashboard's performance figures are folded out of.
///
/// Three parts, because they answer three different questions and age at
/// different rates: [recent] is the last few weeks, needed for the day-by-day
/// chart and pruned as it ages; [totals] and [byModel] are lifetime and never
/// shrink.
class UsageLedger {
  const UsageLedger({
    this.recent = const <UsageRecord>[],
    this.totals = UsageTotals.empty,
    this.byModel = const <String, ModelTotals>{},
    this.migrated = false,
  });

  static const UsageLedger empty = UsageLedger();

  /// Newest last, so a chart can walk it forwards.
  final List<UsageRecord> recent;

  final UsageTotals totals;

  final Map<String, ModelTotals> byModel;

  /// Whether the one-time fold of already-stored sessions has happened. False
  /// on a ledger that has never been written.
  final bool migrated;

  bool get isEmpty => totals.replies == 0 && totals.agentRuns == 0;

  /// [this] with [record] added to all three parts.
  UsageLedger plus(UsageRecord record) => UsageLedger(
    recent: <UsageRecord>[...recent, record],
    totals: totals.plus(record),
    byModel: <String, ModelTotals>{
      ...byModel,
      // An agent run carries no token figures worth attributing to a model
      // row, but it is still that model being used, so it counts.
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

/// Every finished reply in [sessions], oldest first.
///
/// The one-time migration for a device that chatted before the ledger existed:
/// without it, upgrading would reset every figure on Home to zero, which looks
/// exactly like the bug this ledger is here to fix.
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

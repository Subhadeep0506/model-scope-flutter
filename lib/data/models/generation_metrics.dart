import 'package:json_annotation/json_annotation.dart';

part 'generation_metrics.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class GenerationMetrics {
  const GenerationMetrics({
    required this.latencyMs,
    required this.tokensPerSecond,
    required this.tokenCount,
  });

  factory GenerationMetrics.fromJson(Map<String, dynamic> json) =>
      _$GenerationMetricsFromJson(json);

  final int latencyMs;

  final double tokensPerSecond;

  final int tokenCount;

  Map<String, dynamic> toJson() => _$GenerationMetricsToJson(this);

  String get label =>
      '${latencyMs}ms · ${tokensPerSecond.toStringAsFixed(1)} tok/s · $tokenCount tok';
}

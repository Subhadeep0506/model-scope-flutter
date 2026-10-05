import 'package:json_annotation/json_annotation.dart';

part 'generation_metrics.g.dart';

/// Timing figures for one reply, drawn as `118ms · 93.4 tok/s · 96 tok`.
/// `nobodywho` does not report these; the view model measures them while
/// draining the token stream, so they are stored and survive a reload.
@JsonSerializable(fieldRename: FieldRename.snake)
class GenerationMetrics {
  const GenerationMetrics({
    required this.latencyMs,
    required this.tokensPerSecond,
    required this.tokenCount,
  });

  factory GenerationMetrics.fromJson(Map<String, dynamic> json) =>
      _$GenerationMetricsFromJson(json);

  /// Time to the first token, in milliseconds.
  final int latencyMs;

  /// Tokens per second over the generation phase, excluding the initial wait.
  final double tokensPerSecond;

  /// How many tokens the stream emitted.
  final int tokenCount;

  Map<String, dynamic> toJson() => _$GenerationMetricsToJson(this);

  /// Formatted exactly as the mockup prints it.
  String get label =>
      '${latencyMs}ms · ${tokensPerSecond.toStringAsFixed(1)} tok/s · $tokenCount tok';
}

import 'package:json_annotation/json_annotation.dart';

part 'sampler_settings.g.dart';

// Declared at library level rather than as class statics because
// json_serializable copies default-value expressions verbatim into the
// generated part file, where a `SamplerSettings.`-scoped name would not
// resolve. The class re-exports them below so call sites stay readable.
const double _temperature = 0.70;
const double _topP = 0.90;
const int _topK = 40;
const int _maxTokens = 512;
const int _historyTurns = 10;
const String _systemPrompt = 'You are a concise, helpful on-device assistant.';

/// Sampling knobs exposed by the Sampling sheet.
///
/// Defaults match the values drawn in `assets/design/chat-settings.png`.
@JsonSerializable(fieldRename: FieldRename.snake)
class SamplerSettings {
  const SamplerSettings({
    this.temperature = _temperature,
    this.topP = _topP,
    this.topK = _topK,
    this.maxTokens = _maxTokens,
    this.historyTurns = _historyTurns,
    this.systemPrompt = _systemPrompt,
  });

  factory SamplerSettings.fromJson(Map<String, dynamic> json) =>
      _$SamplerSettingsFromJson(json);

  static const double defaultTemperature = _temperature;
  static const double defaultTopP = _topP;
  static const int defaultTopK = _topK;
  static const int defaultMaxTokens = _maxTokens;
  static const int defaultHistoryTurns = _historyTurns;
  static const String defaultSystemPrompt = _systemPrompt;

  /// Slider ranges, also from the mockup.
  static const (double, double) temperatureRange = (0.0, 2.0);
  static const (double, double) topPRange = (0.0, 1.0);
  static const (int, int) topKRange = (1, 100);
  static const (int, int) maxTokensRange = (64, 4096);

  /// How many past turns may be replayed. Zero is a real setting — it answers
  /// every prompt cold — so the range starts there rather than at one.
  static const (int, int) historyTurnsRange = (0, 50);

  final double temperature;
  final double topP;
  final int topK;

  /// `nobodywho`'s sampler has no token cap, so this is enforced by the view
  /// model: it counts stream events and calls `stopGeneration()` on reaching
  /// the limit.
  final int maxTokens;

  /// How many past question-and-answer pairs are replayed into the model's
  /// context when a session is opened or has outgrown the window.
  ///
  /// Unlike the sampler knobs above this is not pushed to `nobodywho` at all —
  /// `ChatViewModel` applies it by choosing what to hand `restoreHistory`.
  final int historyTurns;

  final String systemPrompt;

  SamplerSettings copyWith({
    double? temperature,
    double? topP,
    int? topK,
    int? maxTokens,
    int? historyTurns,
    String? systemPrompt,
  }) => SamplerSettings(
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    topK: topK ?? this.topK,
    maxTokens: maxTokens ?? this.maxTokens,
    historyTurns: historyTurns ?? this.historyTurns,
    systemPrompt: systemPrompt ?? this.systemPrompt,
  );

  Map<String, dynamic> toJson() => _$SamplerSettingsToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SamplerSettings &&
          temperature == other.temperature &&
          topP == other.topP &&
          topK == other.topK &&
          maxTokens == other.maxTokens &&
          historyTurns == other.historyTurns &&
          systemPrompt == other.systemPrompt;

  @override
  int get hashCode => Object.hash(
    temperature,
    topP,
    topK,
    maxTokens,
    historyTurns,
    systemPrompt,
  );
}

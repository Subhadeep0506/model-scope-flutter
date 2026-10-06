import 'package:json_annotation/json_annotation.dart';

part 'sampler_settings.g.dart';

const double _temperature = 0.70;
const double _topP = 0.90;
const int _topK = 40;
const int _maxTokens = 512;
const int _historyTurns = 10;
const String _systemPrompt =
    'You are a concise, helpful on-device assistant. Respond to user\'s queries as good as possible.';

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

  /// What an agent run samples at, whatever the Chat sliders say. Low because
  /// a step is instruction-following — call this tool, with these arguments —
  /// and because two runs of one agent should differ for reasons to do with
  /// the model rather than the sampler.
  static const double agentTemperature = 0.2;

  /// Slider ranges, also from the mockup.
  static const (double, double) temperatureRange = (0.0, 2.0);
  static const (double, double) topPRange = (0.0, 1.0);
  static const (int, int) topKRange = (1, 100);
  static const (int, int) maxTokensRange = (64, 4096);
  static const (int, int) historyTurnsRange = (0, 50);

  final double temperature;
  final double topP;
  final int topK;
  final int maxTokens;
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

  /// These settings as an agent run uses them. Everything else is the user's,
  /// so a wider context or a longer answer still follows what they chose.
  SamplerSettings forAgentRun() => copyWith(temperature: agentTemperature);

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

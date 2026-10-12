import 'package:json_annotation/json_annotation.dart';

part 'agent_template.g.dart';

@JsonEnum()
enum AgentInputType {
  @JsonValue('text')
  text('Text'),
  @JsonValue('number')
  number('Number'),

  @JsonValue('choice')
  choice('Choice'),

  @JsonValue('file')
  file('File');

  const AgentInputType(this.label);

  final String label;
}

@JsonEnum()
enum StepKind {
  @JsonValue('tool')
  tool('Tool'),

  @JsonValue('reason')
  reason('Reason');

  const StepKind(this.label);

  final String label;
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AgentInput {
  const AgentInput({
    required this.name,
    required this.label,
    this.type = AgentInputType.text,
    this.options = const <String>[],
    this.defaultValue,
    this.required = true,
  });

  factory AgentInput.fromJson(Map<String, dynamic> json) =>
      _$AgentInputFromJson(json);

  final String name;

  final String label;

  @JsonKey(defaultValue: AgentInputType.text)
  final AgentInputType type;

  @JsonKey(defaultValue: <String>[])
  final List<String> options;

  @JsonKey(name: 'default')
  final String? defaultValue;

  @JsonKey(defaultValue: true)
  final bool required;

  Map<String, dynamic> toJson() => _$AgentInputToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class PipelineStep {
  const PipelineStep({
    required this.id,
    required this.kind,
    this.tool,
    this.prompt,
    this.reads = const <String>[],
    this.model,
  });

  factory PipelineStep.fromJson(Map<String, dynamic> json) =>
      _$PipelineStepFromJson(json);

  final String id;

  final StepKind kind;

  final String? tool;

  final String? prompt;

  @JsonKey(defaultValue: <String>[])
  final List<String> reads;

  final String? model;

  Map<String, dynamic> toJson() => _$PipelineStepToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AnswerStep {
  const AnswerStep({
    required this.prompt,
    this.reads = const <String>[],
    this.model,
    this.schema,
    this.view,
  });

  factory AnswerStep.fromJson(Map<String, dynamic> json) =>
      _$AnswerStepFromJson(json);

  final String prompt;

  @JsonKey(defaultValue: <String>[])
  final List<String> reads;

  final String? model;

  final Map<String, dynamic>? schema;

  final String? view;

  bool get isStructured => schema != null;

  Map<String, dynamic> toJson() => _$AnswerStepToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AgentLimits {
  const AgentLimits({
    this.webResults = defaultWebResults,
    this.webSnippetChars = defaultWebSnippetChars,
    this.webPageChars = defaultWebPageChars,
    this.chunkChars = defaultChunkChars,
    this.chunkOverlapChars = defaultChunkOverlapChars,
    this.passages = defaultPassages,
  });

  factory AgentLimits.fromJson(Map<String, dynamic> json) =>
      _$AgentLimitsFromJson(json);

  static const int defaultWebResults = 3;
  static const int defaultWebSnippetChars = 400;
  static const int defaultWebPageChars = 2500;
  static const int defaultChunkChars = 700;
  static const int defaultChunkOverlapChars = 120;
  static const int defaultPassages = 4;

  static const (int, int) webResultsRange = (1, 10);
  static const (int, int) webSnippetCharsRange = (80, 2000);
  static const (int, int) webPageCharsRange = (500, 20000);
  static const (int, int) chunkCharsRange = (200, 4000);
  static const (int, int) chunkOverlapCharsRange = (0, 1000);
  static const (int, int) passagesRange = (1, 20);

  @JsonKey(defaultValue: defaultWebResults)
  final int webResults;

  @JsonKey(defaultValue: defaultWebSnippetChars)
  final int webSnippetChars;

  @JsonKey(defaultValue: defaultWebPageChars)
  final int webPageChars;

  @JsonKey(defaultValue: defaultChunkChars)
  final int chunkChars;

  @JsonKey(defaultValue: defaultChunkOverlapChars)
  final int chunkOverlapChars;

  @JsonKey(defaultValue: defaultPassages)
  final int passages;

  AgentLimits clamped() => AgentLimits(
    webResults: _hold(webResults, webResultsRange),
    webSnippetChars: _hold(webSnippetChars, webSnippetCharsRange),
    webPageChars: _hold(webPageChars, webPageCharsRange),
    chunkChars: _hold(chunkChars, chunkCharsRange),

    chunkOverlapChars: _hold(
      chunkOverlapChars,
      chunkOverlapCharsRange,
    ).clamp(0, _hold(chunkChars, chunkCharsRange) ~/ 2),
    passages: _hold(passages, passagesRange),
  );

  static int _hold(int value, (int, int) range) =>
      value.clamp(range.$1, range.$2);

  Map<String, dynamic> toJson() => _$AgentLimitsToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AgentTemplate {
  const AgentTemplate({
    required this.id,
    required this.name,
    required this.purpose,
    required this.systemPrompt,
    required this.pipeline,
    required this.answer,
    this.schemaVersion = currentSchemaVersion,
    this.description = '',
    this.icon = 'robot',
    this.inputs = const <AgentInput>[],
    this.createdAt,
    this.temperature,
    this.limits,
  });

  factory AgentTemplate.fromJson(Map<String, dynamic> json) =>
      _$AgentTemplateFromJson(json);

  static const int currentSchemaVersion = 1;

  @JsonKey(defaultValue: currentSchemaVersion)
  final int schemaVersion;

  final String id;

  final String name;

  final String purpose;

  @JsonKey(defaultValue: '')
  final String description;

  @JsonKey(defaultValue: 'robot')
  final String icon;

  final String systemPrompt;

  @JsonKey(defaultValue: <AgentInput>[])
  final List<AgentInput> inputs;

  final List<PipelineStep> pipeline;

  final AnswerStep answer;

  final DateTime? createdAt;

  final double? temperature;

  final AgentLimits? limits;

  AgentLimits get limitsOrDefault => (limits ?? const AgentLimits()).clamped();

  List<String> get toolNames {
    final names = <String>[];
    for (final step in pipeline) {
      final tool = step.tool;
      if (tool != null && !names.contains(tool)) names.add(tool);
    }
    return names;
  }

  int get stepCount => pipeline.length + 1;

  AgentInput? get fileInput {
    for (final input in inputs) {
      if (input.type == AgentInputType.file) return input;
    }
    return null;
  }

  AgentInput? inputNamed(String name) {
    for (final input in inputs) {
      if (input.name == name) return input;
    }
    return null;
  }

  Map<String, String> get defaultValues => <String, String>{
    for (final input in inputs) input.name: ?input.defaultValue,
  };

  Map<String, dynamic> toJson() => _$AgentTemplateToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AgentTemplate && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

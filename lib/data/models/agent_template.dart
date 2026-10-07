import 'package:json_annotation/json_annotation.dart';

part 'agent_template.g.dart';

/// What an agent asks the user for before it runs, as drawn in the detail
/// screen's `Configure inputs` panel. The values are the strings used in the
/// template files; an entry naming anything else is an authoring mistake, so
/// decoding throws.
@JsonEnum()
enum AgentInputType {
  @JsonValue('text')
  text('Text'),
  @JsonValue('number')
  number('Number'),

  /// A fixed set of options, e.g. `metric` or `imperial`. Needs [AgentInput
  /// .options] to be non-empty, which the validator checks.
  @JsonValue('choice')
  choice('Choice'),

  /// A file the user picks, through a real picker on the run screen.
  ///
  /// A template declaring one is indexed before its pipeline runs — see
  /// `AgentRunViewModel.run` — which is how Document QnA gets its document
  /// into the vector store. A step reading `input.<name>` still gets the path
  /// as text.
  @JsonValue('file')
  file('File');

  const AgentInputType(this.label);

  /// The caption on the type dropdown in the builder.
  final String label;
}

/// What a pipeline step does.
@JsonEnum()
enum StepKind {
  /// One turn with exactly one tool enabled. The model chooses the tool's
  /// arguments; it does not choose the tool, which the template already named.
  @JsonValue('tool')
  tool('Tool'),

  /// One turn with no tools at all — the model is asked to think about what
  /// earlier steps produced.
  @JsonValue('reason')
  reason('Reason');

  const StepKind(this.label);

  /// The caption on the Tool/Reason toggle in the builder.
  final String label;
}

/// One field the user fills in before a run.
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

  /// The identifier a step refers to, as `input.<name>`. Not shown to the user.
  final String name;

  /// What the field is called on screen, e.g. `Product name`.
  final String label;

  @JsonKey(defaultValue: AgentInputType.text)
  final AgentInputType type;

  /// The choices, when [type] is [AgentInputType.choice]. Empty otherwise.
  @JsonKey(defaultValue: <String>[])
  final List<String> options;

  /// What the field is pre-filled with, which is what `Run with defaults`
  /// runs. Null means the user has to type something.
  @JsonKey(name: 'default')
  final String? defaultValue;

  @JsonKey(defaultValue: true)
  final bool required;

  Map<String, dynamic> toJson() => _$AgentInputToJson(this);
}

/// One step of the pipeline.
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

  /// Unique within the pipeline. A later step refers to this one's output as
  /// `step.<id>`.
  final String id;

  final StepKind kind;

  /// Which tool to enable, for a [StepKind.tool] step. Null on a reason step.
  final String? tool;

  /// What to ask the model. Optional on a tool step — the builder shows no
  /// field there — in which case [AgentScope] generates a line naming the
  /// tool. Templates written by hand set it, because a small model needs the
  /// instruction.
  final String? prompt;

  /// Where this step's context comes from: `input.<name>` or `step.<id>`,
  /// rendered into the prompt as labelled blocks.
  @JsonKey(defaultValue: <String>[])
  final List<String> reads;

  /// Which model to run this step on.
  ///
  /// **Parsed and stored, ignored at runtime.** Every step of a run uses the
  /// agent's one model: swapping weights between steps means unloading and
  /// reloading a gigabyte-odd of GGUF, which costs seconds per step on a phone
  /// and risks the allocation failing. The field is kept so templates written
  /// now survive the day that changes.
  final String? model;

  Map<String, dynamic> toJson() => _$PipelineStepToJson(this);
}

/// The closing step, which every agent has and which always runs last — the
/// `Answer · always last` card in the builder. It never has tools: by this
/// point everything has been gathered and the model's job is to write it up.
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AnswerStep {
  const AnswerStep({
    required this.prompt,
    this.reads = const <String>[],
    this.model,
  });

  factory AnswerStep.fromJson(Map<String, dynamic> json) =>
      _$AnswerStepFromJson(json);

  final String prompt;

  /// Defaults to every step's output, in order, when left empty — which is
  /// what a summarising answer almost always wants.
  @JsonKey(defaultValue: <String>[])
  final List<String> reads;

  /// Ignored at runtime, for the reason given on [PipelineStep.model].
  final String? model;

  Map<String, dynamic> toJson() => _$AnswerStepToJson(this);
}

/// One agent, parsed from a single JSON file.
///
/// The same shape whether it was shipped in `assets/agents/` or written by the
/// user into the documents directory — nothing here says which, because
/// [AgentRepository] knows by where it loaded it. That is what lets a custom
/// agent be exported as a file and a built-in one be copied and edited.
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
  });

  factory AgentTemplate.fromJson(Map<String, dynamic> json) =>
      _$AgentTemplateFromJson(json);

  /// Bumped when a change to this format stops older files parsing. Nothing
  /// reads it yet; it exists so that the day one is needed, the files already
  /// say what they are.
  static const int currentSchemaVersion = 1;

  @JsonKey(defaultValue: currentSchemaVersion)
  final int schemaVersion;

  /// Unique across built-in and custom agents, and the file's own name.
  final String id;

  /// The card title, e.g. `Price Comparison`.
  final String name;

  /// The one line under the title, e.g. `Compare prices across retailers`.
  final String purpose;

  /// The paragraph in the card at the top of the detail screen. Optional:
  /// an agent built in the app has only a purpose until the user writes more.
  @JsonKey(defaultValue: '')
  final String description;

  /// A token the presentation layer maps to an icon. Kept as a string so this
  /// layer never imports Flutter.
  @JsonKey(defaultValue: 'robot')
  final String icon;

  /// Set on the chat before the run and left in place for every step — unlike
  /// history, which is reset between them.
  final String systemPrompt;

  @JsonKey(defaultValue: <AgentInput>[])
  final List<AgentInput> inputs;

  final List<PipelineStep> pipeline;

  final AnswerStep answer;

  /// When the user built this agent. Null on a built-in, which ships with the
  /// app and has no creation date of its own.
  final DateTime? createdAt;

  /// What to sample this agent at, overriding the low default a run uses.
  ///
  /// Null means take the default, which is right for the tool-calling agents:
  /// a step is instruction-following, and sampling loosely there only makes a
  /// small model ignore the tool. An agent that writes prose from retrieved
  /// material wants a little more, and an input named `temperature` overrides
  /// this again per run.
  final double? temperature;

  /// Every tool this agent can reach, in pipeline order and without repeats —
  /// the mono chips on the agent card.
  List<String> get toolNames {
    final names = <String>[];
    for (final step in pipeline) {
      final tool = step.tool;
      if (tool != null && !names.contains(tool)) names.add(tool);
    }
    return names;
  }

  /// Steps plus the answer, which is what the trace counts.
  int get stepCount => pipeline.length + 1;

  /// The file input this agent takes, or null when it takes none. A template
  /// with one is indexed before its pipeline runs.
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

  /// The values a run starts from when the user changes nothing, which is what
  /// `Run with defaults` sends.
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

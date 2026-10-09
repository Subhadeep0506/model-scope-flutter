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
    this.schema,
    this.view,
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

  /// The JSON Schema the answer must match — the `Structured response` toggle
  /// on the builder's answer card. Null means the answer is prose, which is
  /// what every agent did before this existed.
  ///
  /// Held as a raw map rather than a typed class on purpose: this is a JSON
  /// Schema, the app only passes it through to the sampler, and a typed model
  /// would need a case for every keyword a user might write.
  final Map<String, dynamic>? schema;

  /// Which component draws the result, e.g. `price_table`.
  ///
  /// A name rather than anything drawable, so `lib/data` never imports
  /// Flutter — the presentation layer resolves it, as it already does for an
  /// agent's icon. A name this build does not know, or none at all, falls
  /// back to a generic table, so an agent someone writes themselves still
  /// renders as something rather than as raw JSON.
  final String? view;

  /// Whether this answer is constrained to [schema].
  bool get isStructured => schema != null;

  Map<String, dynamic> toJson() => _$AnswerStepToJson(this);
}

/// How much text one run is allowed to push at the model.
///
/// A phone-sized context is the scarce resource here: at the default 4096
/// tokens, five search results with a long extract each, or one whole fetched
/// page, is enough to overflow it and end the run in an error. Every number
/// below is a cap on something that would otherwise be fixed in the code, and
/// each agent carries its own — a two-step web agent and a document agent want
/// very different budgets.
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

  /// What each slider in the builder's `Limits` card may be dragged between,
  /// and what [clamped] holds a hand-written file to.
  static const (int, int) webResultsRange = (1, 10);
  static const (int, int) webSnippetCharsRange = (80, 2000);
  static const (int, int) webPageCharsRange = (500, 20000);
  static const (int, int) chunkCharsRange = (200, 4000);
  static const (int, int) chunkOverlapCharsRange = (0, 1000);
  static const (int, int) passagesRange = (1, 20);

  /// How many pages `web_search` asks for.
  @JsonKey(defaultValue: defaultWebResults)
  final int webResults;

  /// How much of each search result's extract is kept.
  @JsonKey(defaultValue: defaultWebSnippetChars)
  final int webSnippetChars;

  /// How much of a page `read_web_page` returns before cutting it short.
  @JsonKey(defaultValue: defaultWebPageChars)
  final int webPageChars;

  /// How long each passage of an indexed document is.
  ///
  /// Applies when the document is encoded, not when it is searched, so
  /// changing it re-indexes rather than taking effect on the next question.
  @JsonKey(defaultValue: defaultChunkChars)
  final int chunkChars;

  /// How much each passage repeats of the one before, so a sentence split
  /// across a boundary is still retrievable whole.
  @JsonKey(defaultValue: defaultChunkOverlapChars)
  final int chunkOverlapChars;

  /// How many passages `search_document` returns.
  @JsonKey(defaultValue: defaultPassages)
  final int passages;

  /// This, with every number held to its range.
  ///
  /// Applied on the way out rather than in the constructor, because a template
  /// may be written by hand: a zero or a six-figure number in a JSON file must
  /// cost the user a sensible run, not a wedged one.
  AgentLimits clamped() => AgentLimits(
    webResults: _hold(webResults, webResultsRange),
    webSnippetChars: _hold(webSnippetChars, webSnippetCharsRange),
    webPageChars: _hold(webPageChars, webPageCharsRange),
    chunkChars: _hold(chunkChars, chunkCharsRange),
    // Never more than half a chunk, whatever the file says: the chunker halves
    // it anyway, and a slider that appears to do nothing is worse than one
    // that stops.
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
    this.limits,
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

  /// How much text this agent may push at the model, or null to take the
  /// defaults.
  ///
  /// Nullable rather than defaulted, like [temperature], so that every file
  /// written before this existed still parses — read it through
  /// [limitsOrDefault], never directly.
  final AgentLimits? limits;

  /// This agent's limits, with every number held to its range.
  AgentLimits get limitsOrDefault => (limits ?? const AgentLimits()).clamped();

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

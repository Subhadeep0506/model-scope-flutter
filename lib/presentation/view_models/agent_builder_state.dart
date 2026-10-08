import 'package:uuid/uuid.dart';

import '../../data/models/agent_template.dart';
import '../../domain/services/schema_fields.dart';

const Uuid _uuid = Uuid();

/// One input being edited.
///
/// Mutable, and carrying a [key] the file never sees. Both are because this is
/// a form: rows get typed into, reordered and deleted, and Flutter needs
/// something stable to tell row three from row four when row two goes away.
class DraftInput {
  DraftInput({
    String? key,
    this.name = '',
    this.label = '',
    this.type = AgentInputType.text,
    List<String>? options,
    this.defaultValue = '',
    this.required = true,
  }) : key = key ?? _uuid.v4(),
       options = options ?? <String>[];

  final String key;

  /// The identifier a step reads as `input.<name>`. Derived from [label] as
  /// the user types, so there is one less field to fill in — but kept
  /// separately, because an agent loaded for editing may have the two
  /// deliberately different.
  String name;

  String label;
  AgentInputType type;

  /// The choices, when [type] is a choice. The validator rejects an empty
  /// list, which is why picking Choice reveals an editor for it.
  final List<String> options;

  String defaultValue;
  bool required;

  AgentInput toInput() => AgentInput(
    name: name.trim(),
    label: label.trim(),
    type: type,
    options: <String>[
      for (final option in options)
        if (option.trim().isNotEmpty) option.trim(),
    ],
    defaultValue: defaultValue.trim().isEmpty ? null : defaultValue.trim(),
    required: required,
  );

  static DraftInput from(AgentInput input) => DraftInput(
    name: input.name,
    label: input.label,
    type: input.type,
    options: <String>[...input.options],
    defaultValue: input.defaultValue ?? '',
    required: input.required,
  );
}

/// One pipeline step being edited.
class DraftStep {
  DraftStep({
    String? key,
    this.id = '',
    this.kind = StepKind.tool,
    this.tool,
    this.prompt = '',
    List<String>? reads,
  }) : key = key ?? _uuid.v4(),
       reads = reads ?? <String>[];

  final String key;

  /// What later steps read as `step.<id>`.
  String id;

  StepKind kind;

  /// Null until a tool is picked, which the validator reports as a problem.
  String? tool;

  String prompt;

  /// `input.<name>` and `step.<id>` entries, in the order they were ticked.
  final List<String> reads;

  PipelineStep toStep() => PipelineStep(
    id: id.trim(),
    kind: kind,
    // A reason step with a tool left over from a toggle would confuse the
    // validator, so the tool is dropped unless the step is a tool step.
    tool: kind == StepKind.tool ? tool : null,
    prompt: prompt.trim().isEmpty ? null : prompt.trim(),
    reads: <String>[...reads],
  );

  static DraftStep from(PipelineStep step) => DraftStep(
    id: step.id,
    kind: step.kind,
    tool: step.tool,
    prompt: step.prompt ?? '',
    reads: <String>[...step.reads],
  );

  DraftStep copy() => DraftStep(
    id: id,
    kind: kind,
    tool: tool,
    prompt: prompt,
    reads: <String>[...reads],
  );
}

/// The closing step being edited, including its structured response.
class DraftAnswer {
  DraftAnswer({
    this.prompt = '',
    List<String>? reads,
    this.view,
    this.isStructured = false,
    List<SchemaField>? fields,
    this.rawSchema,
  }) : reads = reads ?? <String>[],
       fields = fields ?? <SchemaField>[];

  String prompt;
  final List<String> reads;

  /// Which component draws the result. Null falls back to the generic table.
  String? view;

  /// The `Structured response` toggle.
  bool isStructured;

  /// The rows in the `{} Fields` tab.
  final List<SchemaField> fields;

  /// Set only when the schema is one the rows cannot draw — an enum, a
  /// `$ref`, a constraint. While it is set it is the source of truth, so
  /// loading an exotic schema, saving, and loading again does not quietly
  /// simplify it into something the builder happens to understand.
  Map<String, dynamic>? rawSchema;

  /// What the template should carry, or null when the toggle is off.
  Map<String, dynamic>? toSchema() {
    if (!isStructured) return null;
    return rawSchema ?? schemaFromFields(fields);
  }

  AnswerStep toAnswer() => AnswerStep(
    prompt: prompt.trim(),
    reads: <String>[...reads],
    schema: toSchema(),
    view: isStructured ? view : null,
  );

  static DraftAnswer from(AnswerStep answer) {
    final schema = answer.schema;
    final fields = fieldsFromSchema(schema);
    return DraftAnswer(
      prompt: answer.prompt,
      reads: <String>[...answer.reads],
      view: answer.view,
      isStructured: schema != null,
      fields: fields ?? <SchemaField>[],
      // Held as raw only when the rows could not express it.
      rawSchema: schema != null && fields == null ? schema : null,
    );
  }
}

/// A whole agent being edited.
///
/// Separate from [AgentTemplate] because a form holds things a template
/// cannot: a name that is still empty, a step with no tool chosen, a schema
/// that does not parse yet. Converting happens once, on save.
class AgentDraft {
  AgentDraft({
    this.id,
    this.name = '',
    this.purpose = '',
    this.description = '',
    this.icon = 'robot',
    this.systemPrompt = '',
    List<DraftInput>? inputs,
    List<DraftStep>? steps,
    DraftAnswer? answer,
    this.createdAt,
    this.temperature,
  }) : inputs = inputs ?? <DraftInput>[],
       steps = steps ?? <DraftStep>[],
       answer = answer ?? DraftAnswer();

  /// Null until the agent has been saved once. Set then and never changed,
  /// so renaming an agent does not move its file or orphan its run history.
  String? id;

  String name;
  String purpose;

  /// The paragraph on the detail screen. The builder has no control for it,
  /// so it is carried through untouched for an agent that already has one.
  String description;

  String icon;
  String systemPrompt;

  final List<DraftInput> inputs;
  final List<DraftStep> steps;
  DraftAnswer answer;

  final DateTime? createdAt;

  /// Carried through from the file; the builder draws no control for it.
  final double? temperature;

  /// Whether this draft is editing something already saved.
  bool get isExisting => id != null;

  AgentTemplate toTemplate({required String id, DateTime? createdAt}) =>
      AgentTemplate(
        id: id,
        name: name.trim(),
        purpose: purpose.trim(),
        description: description.trim(),
        icon: icon,
        systemPrompt: systemPrompt.trim(),
        inputs: <AgentInput>[for (final input in inputs) input.toInput()],
        pipeline: <PipelineStep>[for (final step in steps) step.toStep()],
        answer: answer.toAnswer(),
        createdAt: createdAt ?? this.createdAt,
        temperature: temperature,
      );

  static AgentDraft from(AgentTemplate template, {String? id}) => AgentDraft(
    id: id,
    name: template.name,
    purpose: template.purpose,
    description: template.description,
    icon: template.icon,
    systemPrompt: template.systemPrompt,
    inputs: <DraftInput>[
      for (final input in template.inputs) DraftInput.from(input),
    ],
    steps: <DraftStep>[
      for (final step in template.pipeline) DraftStep.from(step),
    ],
    answer: DraftAnswer.from(template.answer),
    createdAt: template.createdAt,
    temperature: template.temperature,
  );

  /// Every reference a step at [stepIndex] is allowed to read.
  ///
  /// Inputs, plus the steps *before* it — a step cannot read one that has not
  /// run. Pass the pipeline length for the answer step, which reads anything.
  List<DraftReference> referencesBefore(int stepIndex) => <DraftReference>[
    for (final input in inputs)
      if (input.name.trim().isNotEmpty)
        DraftReference(
          reference: 'input.${input.name.trim()}',
          label: 'Input · ${_shown(input.label, input.name)}',
        ),
    for (final (index, step) in steps.indexed)
      if (index < stepIndex && step.id.trim().isNotEmpty)
        DraftReference(
          reference: 'step.${step.id.trim()}',
          label: 'Step · ${step.id.trim()}',
        ),
  ];

  static String _shown(String label, String name) =>
      label.trim().isNotEmpty ? label.trim() : name.trim();
}

/// One entry in a READS picker.
class DraftReference {
  const DraftReference({required this.reference, required this.label});

  /// `input.query` or `step.search`.
  final String reference;

  /// `Input · Query`, as the dropdown draws it.
  final String label;
}

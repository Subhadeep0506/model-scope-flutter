import 'package:uuid/uuid.dart';

import '../../data/models/agent_template.dart';
import '../../domain/services/schema_fields.dart';

const Uuid _uuid = Uuid();

/// One input being edited.
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
  String name;
  String label;
  AgentInputType type;
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
  String id;
  StepKind kind;
  String? tool;
  String prompt;
  final List<String> reads;

  PipelineStep toStep() => PipelineStep(
    id: id.trim(),
    kind: kind,
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
  bool isStructured;
  final List<SchemaField> fields;
  Map<String, dynamic>? rawSchema;

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

/// The context limits being edited — the `Limits` card's six sliders.
class DraftLimits {
  DraftLimits({
    this.webResults = AgentLimits.defaultWebResults,
    this.webSnippetChars = AgentLimits.defaultWebSnippetChars,
    this.webPageChars = AgentLimits.defaultWebPageChars,
    this.chunkChars = AgentLimits.defaultChunkChars,
    this.chunkOverlapChars = AgentLimits.defaultChunkOverlapChars,
    this.passages = AgentLimits.defaultPassages,
  });

  int webResults;
  int webSnippetChars;
  int webPageChars;
  int chunkChars;
  int chunkOverlapChars;
  int passages;

  AgentLimits toLimits() => AgentLimits(
    webResults: webResults,
    webSnippetChars: webSnippetChars,
    webPageChars: webPageChars,
    chunkChars: chunkChars,
    chunkOverlapChars: chunkOverlapChars,
    passages: passages,
  ).clamped();

  static DraftLimits from(AgentLimits limits) => DraftLimits(
    webResults: limits.webResults,
    webSnippetChars: limits.webSnippetChars,
    webPageChars: limits.webPageChars,
    chunkChars: limits.chunkChars,
    chunkOverlapChars: limits.chunkOverlapChars,
    passages: limits.passages,
  );
}

/// A whole agent being edited.
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
    DraftLimits? limits,
    this.createdAt,
    this.temperature,
  }) : inputs = inputs ?? <DraftInput>[],
       steps = steps ?? <DraftStep>[],
       answer = answer ?? DraftAnswer(),
       limits = limits ?? DraftLimits();
  String? id;

  String name;
  String purpose;
  String description;
  String icon;
  String systemPrompt;

  final List<DraftInput> inputs;
  final List<DraftStep> steps;
  DraftAnswer answer;
  final DraftLimits limits;
  final DateTime? createdAt;
  final double? temperature;
  bool get isExisting => id != null;
  static const Set<String> webToolNames = <String>{
    'web_search',
    'read_web_page',
  };
  static const String documentToolName = 'search_document';
  bool get usesWebTools => _usesAny(webToolNames);
  bool get usesDocumentTools => _usesAny(<String>{documentToolName});
  bool _usesAny(Set<String> tools) => steps.any(
    (step) => step.kind == StepKind.tool && tools.contains(step.tool),
  );

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
        limits: limits.toLimits(),
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
    limits: DraftLimits.from(template.limitsOrDefault),
    createdAt: template.createdAt,
    temperature: template.temperature,
  );

  /// Every reference a step at [stepIndex] is allowed to read.
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

class DraftReference {
  const DraftReference({required this.reference, required this.label});
  final String reference;
  final String label;
}

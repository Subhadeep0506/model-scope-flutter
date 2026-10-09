// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgentInput _$AgentInputFromJson(Map<String, dynamic> json) => AgentInput(
  name: json['name'] as String,
  label: json['label'] as String,
  type:
      $enumDecodeNullable(_$AgentInputTypeEnumMap, json['type']) ??
      AgentInputType.text,
  options:
      (json['options'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
  defaultValue: json['default'] as String?,
  required: json['required'] as bool? ?? true,
);

Map<String, dynamic> _$AgentInputToJson(AgentInput instance) =>
    <String, dynamic>{
      'name': instance.name,
      'label': instance.label,
      'type': _$AgentInputTypeEnumMap[instance.type]!,
      'options': instance.options,
      'default': instance.defaultValue,
      'required': instance.required,
    };

const _$AgentInputTypeEnumMap = {
  AgentInputType.text: 'text',
  AgentInputType.number: 'number',
  AgentInputType.choice: 'choice',
  AgentInputType.file: 'file',
};

PipelineStep _$PipelineStepFromJson(Map<String, dynamic> json) => PipelineStep(
  id: json['id'] as String,
  kind: $enumDecode(_$StepKindEnumMap, json['kind']),
  tool: json['tool'] as String?,
  prompt: json['prompt'] as String?,
  reads:
      (json['reads'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
  model: json['model'] as String?,
);

Map<String, dynamic> _$PipelineStepToJson(PipelineStep instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': _$StepKindEnumMap[instance.kind]!,
      'tool': instance.tool,
      'prompt': instance.prompt,
      'reads': instance.reads,
      'model': instance.model,
    };

const _$StepKindEnumMap = {StepKind.tool: 'tool', StepKind.reason: 'reason'};

AnswerStep _$AnswerStepFromJson(Map<String, dynamic> json) => AnswerStep(
  prompt: json['prompt'] as String,
  reads:
      (json['reads'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
  model: json['model'] as String?,
  schema: json['schema'] as Map<String, dynamic>?,
  view: json['view'] as String?,
);

Map<String, dynamic> _$AnswerStepToJson(AnswerStep instance) =>
    <String, dynamic>{
      'prompt': instance.prompt,
      'reads': instance.reads,
      'model': instance.model,
      'schema': instance.schema,
      'view': instance.view,
    };

AgentLimits _$AgentLimitsFromJson(Map<String, dynamic> json) => AgentLimits(
  webResults: (json['web_results'] as num?)?.toInt() ?? 3,
  webSnippetChars: (json['web_snippet_chars'] as num?)?.toInt() ?? 400,
  webPageChars: (json['web_page_chars'] as num?)?.toInt() ?? 2500,
  chunkChars: (json['chunk_chars'] as num?)?.toInt() ?? 700,
  chunkOverlapChars: (json['chunk_overlap_chars'] as num?)?.toInt() ?? 120,
  passages: (json['passages'] as num?)?.toInt() ?? 4,
);

Map<String, dynamic> _$AgentLimitsToJson(AgentLimits instance) =>
    <String, dynamic>{
      'web_results': instance.webResults,
      'web_snippet_chars': instance.webSnippetChars,
      'web_page_chars': instance.webPageChars,
      'chunk_chars': instance.chunkChars,
      'chunk_overlap_chars': instance.chunkOverlapChars,
      'passages': instance.passages,
    };

AgentTemplate _$AgentTemplateFromJson(Map<String, dynamic> json) =>
    AgentTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      purpose: json['purpose'] as String,
      systemPrompt: json['system_prompt'] as String,
      pipeline: (json['pipeline'] as List<dynamic>)
          .map((e) => PipelineStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      answer: AnswerStep.fromJson(json['answer'] as Map<String, dynamic>),
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'robot',
      inputs:
          (json['inputs'] as List<dynamic>?)
              ?.map((e) => AgentInput.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      temperature: (json['temperature'] as num?)?.toDouble(),
      limits: json['limits'] == null
          ? null
          : AgentLimits.fromJson(json['limits'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AgentTemplateToJson(AgentTemplate instance) =>
    <String, dynamic>{
      'schema_version': instance.schemaVersion,
      'id': instance.id,
      'name': instance.name,
      'purpose': instance.purpose,
      'description': instance.description,
      'icon': instance.icon,
      'system_prompt': instance.systemPrompt,
      'inputs': instance.inputs.map((e) => e.toJson()).toList(),
      'pipeline': instance.pipeline.map((e) => e.toJson()).toList(),
      'answer': instance.answer.toJson(),
      'created_at': instance.createdAt?.toIso8601String(),
      'temperature': instance.temperature,
      'limits': instance.limits?.toJson(),
    };

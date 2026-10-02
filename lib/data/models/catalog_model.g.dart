// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CatalogModel _$CatalogModelFromJson(Map<String, dynamic> json) => CatalogModel(
  repoId: json['repo_id'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
  capabilities:
      (json['capabilities'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$ModelCapabilityEnumMap, e))
          .toList() ??
      [],
  paramLabel: json['param_label'] as String?,
);

const _$ModelCapabilityEnumMap = {
  ModelCapability.textToText: 'text_to_text',
  ModelCapability.imageToText: 'image_to_text',
  ModelCapability.toolCalling: 'tool_calling',
};

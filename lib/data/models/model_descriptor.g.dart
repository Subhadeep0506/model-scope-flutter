// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_descriptor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelDescriptor _$ModelDescriptorFromJson(Map<String, dynamic> json) =>
    ModelDescriptor(
      repoId: json['repo_id'] as String,
      fileName: json['file_name'] as String,
      name: json['name'] as String,
      quantization: json['quantization'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      localPath: json['local_path'] as String,
      installedAt: DateTime.parse(json['installed_at'] as String),
      paramLabel: json['param_label'] as String?,
    );

Map<String, dynamic> _$ModelDescriptorToJson(ModelDescriptor instance) =>
    <String, dynamic>{
      'repo_id': instance.repoId,
      'file_name': instance.fileName,
      'name': instance.name,
      'quantization': instance.quantization,
      'size_bytes': instance.sizeBytes,
      'local_path': instance.localPath,
      'installed_at': instance.installedAt.toIso8601String(),
      'param_label': instance.paramLabel,
    };

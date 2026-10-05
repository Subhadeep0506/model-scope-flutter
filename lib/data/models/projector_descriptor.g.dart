// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'projector_descriptor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectorDescriptor _$ProjectorDescriptorFromJson(Map<String, dynamic> json) =>
    ProjectorDescriptor(
      repoId: json['repo_id'] as String,
      fileName: json['file_name'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      localPath: json['local_path'] as String,
      installedAt: DateTime.parse(json['installed_at'] as String),
    );

Map<String, dynamic> _$ProjectorDescriptorToJson(
  ProjectorDescriptor instance,
) => <String, dynamic>{
  'repo_id': instance.repoId,
  'file_name': instance.fileName,
  'size_bytes': instance.sizeBytes,
  'local_path': instance.localPath,
  'installed_at': instance.installedAt.toIso8601String(),
};

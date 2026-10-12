import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';
import 'gguf_file.dart';

part 'projector_descriptor.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class ProjectorDescriptor {
  const ProjectorDescriptor({
    required this.repoId,
    required this.fileName,
    required this.sizeBytes,
    required this.localPath,
    required this.installedAt,
  });

  factory ProjectorDescriptor.fromJson(Map<String, dynamic> json) =>
      _$ProjectorDescriptorFromJson(json);

  factory ProjectorDescriptor.installed({
    required GgufFile file,
    required String localPath,
    DateTime? at,
  }) => ProjectorDescriptor(
    repoId: file.repoId,
    fileName: file.fileName,
    sizeBytes: file.sizeBytes,
    localPath: localPath,
    installedAt: at ?? DateTime.now(),
  );

  final String repoId;

  final String fileName;

  final int sizeBytes;

  final String localPath;

  final DateTime installedAt;

  String get id => '$repoId/$fileName';

  String get sizeLabel => formatBytes(sizeBytes);

  Map<String, dynamic> toJson() => _$ProjectorDescriptorToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectorDescriptor &&
          repoId == other.repoId &&
          fileName == other.fileName &&
          localPath == other.localPath;

  @override
  int get hashCode => Object.hash(repoId, fileName, localPath);
}

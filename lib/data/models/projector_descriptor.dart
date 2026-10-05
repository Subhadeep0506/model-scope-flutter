import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';
import 'gguf_file.dart';

part 'projector_descriptor.g.dart';

/// An installed `mmproj` file — the projector that turns an image into tokens
/// a vision model can read. Keyed by repository rather than by file, because
/// the projector is trained against the model family: every quant downloaded
/// from the same repository shares it.
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

  /// Builds an entry from the file the user downloaded.
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

  /// `unsloth/Qwen3.5-2B-GGUF`, the repository this projector serves.
  final String repoId;

  /// The `mmproj` file inside [repoId], e.g. `mmproj-BF16.gguf`.
  final String fileName;

  final int sizeBytes;

  /// Absolute path to the projector on disk.
  final String localPath;

  final DateTime installedAt;

  /// Unique and stable, and the id of the matching catalog row.
  String get id => '$repoId/$fileName';

  /// `310 MB`.
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

import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';
import 'gguf_file.dart';
import 'hf_repo_summary.dart';

part 'model_descriptor.g.dart';

/// A GGUF model the user has downloaded and the app can load.
///
/// The app used to ship one hardcoded model copied out of the asset bundle.
/// Models now arrive from the Hugging Face catalog in Settings, so this is a
/// persisted record rather than a constant: everything needed to load the
/// weights, name them in the UI and delete them again lives here.
@JsonSerializable(fieldRename: FieldRename.snake)
class ModelDescriptor {
  const ModelDescriptor({
    required this.repoId,
    required this.fileName,
    required this.name,
    required this.quantization,
    required this.sizeBytes,
    required this.localPath,
    required this.installedAt,
    this.paramLabel,
  });

  factory ModelDescriptor.fromJson(Map<String, dynamic> json) =>
      _$ModelDescriptorFromJson(json);

  /// Builds an entry from the catalog row and file the user downloaded.
  factory ModelDescriptor.installed({
    required HfRepoSummary repo,
    required GgufFile file,
    required String localPath,
    DateTime? at,
  }) => ModelDescriptor(
    repoId: repo.id,
    fileName: file.fileName,
    name: repo.displayName,
    quantization: file.quantization,
    sizeBytes: file.sizeBytes,
    localPath: localPath,
    installedAt: at ?? DateTime.now(),
    paramLabel: repo.paramLabel,
  );

  /// `bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF`, shown in mono under the
  /// title of each installed-model row.
  final String repoId;

  /// The `.gguf` file inside [repoId].
  final String fileName;

  /// Display name, e.g. `Qwen2.5 Coder 1.5B Instruct`.
  final String name;

  /// Quantisation tag shown in mono, e.g. `Q4_K_M`.
  final String quantization;

  final int sizeBytes;

  /// Absolute path to the weights on disk, as returned by the downloader.
  ///
  /// This is inside `nobodywho`'s own model cache rather than a directory the
  /// app owns, so it is stored rather than derived — and re-checked on load,
  /// because a cache wipe outside the app would leave it dangling.
  final String localPath;

  final DateTime installedAt;

  /// `1.5B`. Null when the repository name does not state one.
  final String? paramLabel;

  /// Unique and stable: the same file from the same repo is the same model.
  String get id => '$repoId/$fileName';

  /// `1.12 GB`, matching the mono size chip in the mockup.
  String get sizeLabel => formatBytes(sizeBytes);

  Map<String, dynamic> toJson() => _$ModelDescriptorToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelDescriptor &&
          repoId == other.repoId &&
          fileName == other.fileName &&
          localPath == other.localPath;

  @override
  int get hashCode => Object.hash(repoId, fileName, localPath);
}

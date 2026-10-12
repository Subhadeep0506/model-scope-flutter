import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';
import 'catalog_model.dart';
import 'gguf_file.dart';

part 'model_descriptor.g.dart';

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
    this.isEmbedding = false,
  });

  factory ModelDescriptor.fromJson(Map<String, dynamic> json) =>
      _$ModelDescriptorFromJson(json);

  factory ModelDescriptor.installed({
    required CatalogModel model,
    required GgufFile file,
    required String localPath,
    DateTime? at,
  }) => ModelDescriptor(
    repoId: model.repoId,
    fileName: file.fileName,
    name: model.name,
    quantization: file.quantization,
    sizeBytes: file.sizeBytes,
    localPath: localPath,
    installedAt: at ?? DateTime.now(),
    paramLabel: model.paramLabel,
    isEmbedding: model.isEmbedding,
  );

  final String repoId;

  final String fileName;

  final String name;

  final String quantization;

  final int sizeBytes;

  final String localPath;

  final DateTime installedAt;

  final String? paramLabel;

  @JsonKey(defaultValue: false)
  final bool isEmbedding;

  String get id => '$repoId/$fileName';

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

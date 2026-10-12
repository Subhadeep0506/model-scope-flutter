import 'package:json_annotation/json_annotation.dart';

part 'catalog_model.g.dart';

@JsonEnum()
enum ModelCapability {
  @JsonValue('text_to_text')
  textToText('Text to text'),
  @JsonValue('image_to_text')
  imageToText('Image to text'),
  @JsonValue('tool_calling')
  toolCalling('Tool calling'),

  @JsonValue('text_embedding')
  textEmbedding('Embedding');

  const ModelCapability(this.label);

  final String label;
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class CatalogModel {
  const CatalogModel({
    required this.repoId,
    required this.name,
    required this.description,
    required this.capabilities,
    this.paramLabel,
  });

  factory CatalogModel.fromJson(Map<String, dynamic> json) =>
      _$CatalogModelFromJson(json);

  final String repoId;

  final String name;

  final String description;

  @JsonKey(defaultValue: <ModelCapability>[])
  final List<ModelCapability> capabilities;

  final String? paramLabel;

  String get author => repoId.split('/').first;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        repoId.toLowerCase().contains(needle);
  }

  bool has(ModelCapability capability) => capabilities.contains(capability);

  bool get isEmbedding => has(ModelCapability.textEmbedding);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CatalogModel && repoId == other.repoId;

  @override
  int get hashCode => repoId.hashCode;
}

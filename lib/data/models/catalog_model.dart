import 'package:json_annotation/json_annotation.dart';

part 'catalog_model.g.dart';

/// What a model can be asked to do, as drawn on the catalog's filter chips.
/// The values are the strings used in `assets/catalog/models.json`; an entry
/// naming anything else is a manifest mistake, so decoding throws.
@JsonEnum()
enum ModelCapability {
  @JsonValue('text_to_text')
  textToText('Text to text'),
  @JsonValue('image_to_text')
  imageToText('Image to text'),
  @JsonValue('tool_calling')
  toolCalling('Tool calling'),

  /// Turns text into vectors for the Document QnA agent. Not a chat model:
  /// one of these can never answer a question, so it is kept out of every
  /// model picker. See [CatalogModel.isEmbedding].
  @JsonValue('text_embedding')
  textEmbedding('Embedding');

  const ModelCapability(this.label);

  /// The chip caption, e.g. `Tool calling`.
  final String label;
}

/// One repository in the curated catalog, shipped with the app so browsing and
/// filtering cost no network — searching the whole Hub got the device
/// rate-limited. Counts and sizes are absent on purpose: they go stale, so they
/// are read live from the Hub and omitted when it cannot be reached.
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

  /// `bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF`.
  final String repoId;

  /// Display title, e.g. `Qwen2.5 Coder 1.5B Instruct`.
  final String name;

  /// The two-line summary under the title.
  final String description;

  @JsonKey(defaultValue: <ModelCapability>[])
  final List<ModelCapability> capabilities;

  /// `1.5B`. Null when the model does not state a parameter count.
  final String? paramLabel;

  /// The publisher, `bartowski`.
  String get author => repoId.split('/').first;

  /// Matches on title, repository id and publisher, so both `qwen` and
  /// `bartowski` find the same row. An empty query matches everything.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        repoId.toLowerCase().contains(needle);
  }

  bool has(ModelCapability capability) => capabilities.contains(capability);

  /// Whether this encodes text rather than answering it. Such a model is
  /// downloaded and deleted like any other, but must never be offered as the
  /// model a chat or an agent runs on.
  bool get isEmbedding => has(ModelCapability.textEmbedding);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CatalogModel && repoId == other.repoId;

  @override
  int get hashCode => repoId.hashCode;
}

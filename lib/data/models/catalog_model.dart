import 'package:json_annotation/json_annotation.dart';

part 'catalog_model.g.dart';

/// What a model can be asked to do, as drawn on the catalog's filter chips.
///
/// The values are the strings used in `assets/catalog/models.json`. An entry
/// naming a capability that is not listed here is a mistake in the manifest, so
/// decoding throws rather than guessing — see [CatalogRepository].
@JsonEnum()
enum ModelCapability {
  @JsonValue('text_to_text')
  textToText('Text to text'),
  @JsonValue('image_to_text')
  imageToText('Image to text'),
  @JsonValue('tool_calling')
  toolCalling('Tool calling');

  const ModelCapability(this.label);

  /// The chip caption, e.g. `Tool calling`.
  final String label;
}

/// One repository in the curated catalog.
///
/// The app used to browse the whole Hugging Face Hub, which meant a search
/// request per keystroke and a file-tree request per card on screen — enough to
/// get the device rate-limited before it had downloaded anything. The catalog is
/// now a list the app ships, so browsing and filtering cost no network at all;
/// the Hub is only asked about a repository the user has actually opened.
///
/// Everything here is authored rather than fetched. Download counts and file
/// sizes are deliberately absent: those go stale, so they are read live from the
/// Hub and simply omitted when it cannot be reached.
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

  /// Whether this row should survive the catalog's search field.
  ///
  /// Matches on title, full repository id and publisher, so both
  /// `qwen` and `bartowski` find the same row. An empty query matches everything.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        repoId.toLowerCase().contains(needle);
  }

  bool has(ModelCapability capability) => capabilities.contains(capability);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CatalogModel && repoId == other.repoId;

  @override
  int get hashCode => repoId.hashCode;
}

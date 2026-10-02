import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';

part 'hf_repo_summary.g.dart';

/// One row in the Hugging Face · GGUF sheet.
///
/// This is everything `GET /api/models` returns about a repository. Note what
/// is *not* here: file names, quantisations and sizes. Those need a second call
/// per repository — see `GgufFile` and `HuggingFaceRepository.filesOf`.
///
/// The field names are Hugging Face's, which mix camelCase and snake_case, so
/// each one is mapped explicitly rather than with `FieldRename.snake`.
@JsonSerializable(createToJson: false)
class HfRepoSummary {
  const HfRepoSummary({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.tags,
    required this.createdAt,
  });

  factory HfRepoSummary.fromJson(Map<String, dynamic> json) =>
      _$HfRepoSummaryFromJson(json);

  /// `bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF`.
  final String id;

  @JsonKey(defaultValue: 0)
  final int downloads;

  @JsonKey(defaultValue: 0)
  final int likes;

  @JsonKey(defaultValue: <String>[])
  final List<String> tags;

  @JsonKey(name: 'createdAt')
  final DateTime? createdAt;

  String get author => id.split('/').first;

  /// The repository name without its owner.
  String get name => id.contains('/') ? id.split('/').last : id;

  /// `182k downloads · 412 likes`, as drawn under each repo title.
  String get statsLabel =>
      '${formatCount(downloads)} downloads · ${formatCount(likes)} likes';

  /// A human title for the installed-models list: `Qwen2.5 Coder 1.5B Instruct`.
  ///
  /// Built from the repo name because Hugging Face has no display-name field.
  String get displayName => name
      .replaceAll(RegExp(r'[-_]?GGUF$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .trim();

  /// `1.5B`, `360M` — the parameter count, when the repo name states one.
  ///
  /// Many repos do not (`Phi-3.5-mini-instruct-gguf` says `mini`), so this is
  /// nullable and the chip is simply omitted rather than guessed at.
  String? get paramLabel {
    final size = _params;
    if (size == null) return null;
    return size.unit == 'B' ? '${size.value}B' : '${size.value}M';
  }

  /// The parameter count in billions, when the repo name states one. `360M`
  /// becomes `0.36`.
  ///
  /// Null means the name says nothing, not that the model is small — the
  /// catalog treats the two differently.
  double? get paramsInBillions {
    final size = _params;
    if (size == null) return null;
    final value = double.tryParse(size.value);
    if (value == null) return null;
    return size.unit == 'B' ? value : value / 1000;
  }

  /// Whether the name is a mixture-of-experts one of the `8x7B` form.
  ///
  /// The number after the `x` is the expert size, not the model: `Mixtral-8x7B`
  /// holds 47B parameters. [paramsInBillions] cannot say how many without
  /// knowing the architecture, so it reports null — and callers that filter on
  /// size must check this too, since null otherwise means *unstated*.
  bool get isMixtureOfExperts =>
      RegExp(r'\dx\d', caseSensitive: false).hasMatch(name);

  /// The parameter count as written in the name, or null when it is unstated.
  ({String value, String unit})? get _params {
    if (isMixtureOfExperts) return null;
    final match = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)\s*([BbMm])(?![\w])')
        .firstMatch(name);
    final value = match?.group(1);
    final unit = match?.group(2)?.toUpperCase();
    if (value == null || unit == null) return null;
    return (value: value, unit: unit);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HfRepoSummary && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A page of catalog results plus the opaque cursor that fetches the next one.
///
/// Hugging Face paginates with a `Link: <…&cursor=…>; rel="next"` response
/// header rather than a page or offset parameter, so [nextCursor] is carried
/// alongside the items. A `null` cursor means this is the last page.
class HfRepoPage {
  const HfRepoPage({required this.items, required this.nextCursor});

  static const HfRepoPage empty = HfRepoPage(
    items: <HfRepoSummary>[],
    nextCursor: null,
  );

  final List<HfRepoSummary> items;
  final String? nextCursor;
}

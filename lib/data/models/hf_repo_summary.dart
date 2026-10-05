import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';

part 'hf_repo_summary.g.dart';

/// The live stats for one repository, from `GET /api/models/{id}` — the only
/// fetched part of a catalog card, so the card still renders when the Hub is
/// unreachable. Field names are Hugging Face's, which mix camelCase and
/// snake_case, hence no `FieldRename.snake`.
@JsonSerializable(createToJson: false)
class HfRepoSummary {
  const HfRepoSummary({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.siblings,
  });

  factory HfRepoSummary.fromJson(Map<String, dynamic> json) =>
      _$HfRepoSummaryFromJson(json);

  /// `bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF`.
  final String id;

  @JsonKey(defaultValue: 0)
  final int downloads;

  @JsonKey(defaultValue: 0)
  final int likes;

  /// Every file in the repository. Only the `.gguf` count is used; the sizes
  /// needed to download one come from the tree endpoint, not this response.
  @JsonKey(defaultValue: <RepoSibling>[])
  final List<RepoSibling> siblings;

  /// `182k downloads · 412 likes`, as drawn under each card's description.
  String get statsLabel =>
      '${formatCount(downloads)} downloads · ${formatCount(likes)} likes';

  /// How many `.gguf` files the repository holds.
  int get ggufFileCount => siblings
      .where((sibling) => sibling.rfilename.toLowerCase().endsWith('.gguf'))
      .length;

  /// `3 files`, or `1 file`.
  String get fileCountLabel =>
      ggufFileCount == 1 ? '1 file' : '$ggufFileCount files';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HfRepoSummary && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// One file name inside a repository listing.
@JsonSerializable(createToJson: false)
class RepoSibling {
  const RepoSibling({required this.rfilename});

  factory RepoSibling.fromJson(Map<String, dynamic> json) =>
      _$RepoSiblingFromJson(json);

  @JsonKey(defaultValue: '')
  final String rfilename;
}

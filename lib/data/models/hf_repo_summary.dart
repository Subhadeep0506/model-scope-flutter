import 'package:json_annotation/json_annotation.dart';

import 'byte_size.dart';

part 'hf_repo_summary.g.dart';

/// The live stats for one repository, from `GET /api/models/{id}`.
///
/// This is the only part of a catalog card that is fetched. Everything else —
/// the title, the description, the parameter count, the capability chips —
/// comes from the manifest the app ships, so a card still renders in full when
/// the Hub is unreachable; it just loses the `182k downloads · 412 likes` row.
///
/// The field names are Hugging Face's, which mix camelCase and snake_case, so
/// each one is mapped explicitly rather than with `FieldRename.snake`.
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

  /// Every file in the repository, as `{"rfilename": "..."}` entries.
  ///
  /// Only the count of `.gguf` entries is used, and only to render `3 files` on
  /// the card — the sizes needed to actually download one come from the tree
  /// endpoint, which this response does not carry.
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

import 'package:json_annotation/json_annotation.dart';
import 'byte_size.dart';
part 'hf_repo_summary.g.dart';

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

  final String id;

  @JsonKey(defaultValue: 0)
  final int downloads;

  @JsonKey(defaultValue: 0)
  final int likes;

  @JsonKey(defaultValue: <RepoSibling>[])
  final List<RepoSibling> siblings;

  String get statsLabel =>
      '${formatCount(downloads)} downloads · ${formatCount(likes)} likes';

  int get ggufFileCount => siblings
      .where((sibling) => sibling.rfilename.toLowerCase().endsWith('.gguf'))
      .length;

  String get fileCountLabel =>
      ggufFileCount == 1 ? '1 file' : '$ggufFileCount files';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HfRepoSummary && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@JsonSerializable(createToJson: false)
class RepoSibling {
  const RepoSibling({required this.rfilename});

  factory RepoSibling.fromJson(Map<String, dynamic> json) =>
      _$RepoSiblingFromJson(json);

  @JsonKey(defaultValue: '')
  final String rfilename;
}

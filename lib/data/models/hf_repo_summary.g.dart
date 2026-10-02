// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hf_repo_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HfRepoSummary _$HfRepoSummaryFromJson(Map<String, dynamic> json) =>
    HfRepoSummary(
      id: json['id'] as String,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      siblings:
          (json['siblings'] as List<dynamic>?)
              ?.map((e) => RepoSibling.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

RepoSibling _$RepoSiblingFromJson(Map<String, dynamic> json) =>
    RepoSibling(rfilename: json['rfilename'] as String? ?? '');

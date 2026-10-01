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
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
    );

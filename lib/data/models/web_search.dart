import 'json_read.dart';

class WebSearchHit {
  const WebSearchHit({
    required this.title,
    required this.url,
    required this.snippet,
    this.score = 0,
    this.publishedDate,
  });

  factory WebSearchHit.fromJson(Map<String, dynamic> json) => WebSearchHit(
    title: readString(json['title'], fallback: 'Untitled'),
    url: readString(json['url']),
    snippet: readString(json['content']),
    score: readDouble(json['score']),
    publishedDate: readStringOrNull(json['published_date']),
  );

  final String title;
  final String url;

  final String snippet;

  final double score;

  final String? publishedDate;

  bool get isUseful => url.isNotEmpty && snippet.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WebSearchHit && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

class WebSearchResult {
  const WebSearchResult({required this.query, required this.hits, this.answer});

  factory WebSearchResult.fromJson(
    Map<String, dynamic> json, {
    String requestedQuery = '',
  }) {
    final hits = <WebSearchHit>[
      for (final entry in readObjectList(json['results']))
        WebSearchHit.fromJson(entry),
    ];
    return WebSearchResult(
      query: readStringOrNull(json['query']) ?? requestedQuery,
      hits: hits.where((hit) => hit.isUseful).toList(growable: false),
      answer: readStringOrNull(json['answer']),
    );
  }

  final String query;

  final List<WebSearchHit> hits;

  final String? answer;

  bool get isEmpty => hits.isEmpty && answer == null;
}

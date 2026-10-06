import 'json_read.dart';

/// One hit from a web search, built from an entry of Tavily's `results` array.
///
/// Tavily calls the extract `content`, which reads like the page body; it is a
/// few hundred characters chosen for the query, so it is [snippet] here.
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

  /// The part of the page Tavily judged relevant, not the page itself. Fetch
  /// the whole thing with the crawler when the snippet is not enough.
  final String snippet;

  /// Tavily's relevance score, 0 to 1. Results arrive already sorted by it, so
  /// it is kept for display and filtering rather than for re-sorting.
  final double score;

  /// Only ever present when the search asked for it, and null when Tavily
  /// could not date the page.
  final String? publishedDate;

  /// Whether this hit says anything at all. A result with no URL cannot be
  /// followed up and a result with no snippet tells a model nothing.
  bool get isUseful => url.isNotEmpty && snippet.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WebSearchHit && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// A whole answer to `POST /search`.
class WebSearchResult {
  const WebSearchResult({required this.query, required this.hits, this.answer});

  /// Keeps only the hits worth passing on, in the order Tavily ranked them.
  ///
  /// [requestedQuery] stands in when Tavily echoes none of its own, so an
  /// empty result can still name what was searched for — a model told only
  /// that nothing was found has no way to try different words.
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

  /// The query as Tavily ran it, which is not always the one that was sent —
  /// `auto_parameters` may rewrite it.
  final String query;

  final List<WebSearchHit> hits;

  /// Tavily's own one-paragraph answer, present only when the search asked for
  /// it. Left off by default: an on-device model should reason over the hits
  /// rather than repeat a cloud model's summary of them.
  final String? answer;

  bool get isEmpty => hits.isEmpty && answer == null;
}

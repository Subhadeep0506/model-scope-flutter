import 'dart:developer' as developer;

import '../../data/models/web_search.dart';
import '../../data/sources/tavily_api_client.dart';

class TavilyWebSearchService {
  TavilyWebSearchService(
    this._client,
    this._apiKey, {
    this.maxResults = 5,
    this.searchDepth = 'basic',
  });

  final TavilyApiClient _client;

  /// Returns the stored Tavily key, or an empty string when none is set.
  final Future<String> Function() _apiKey;

  /// How many hits a search asks for. Five is a deliberate ceiling: these go
  /// into the context of a model with a few thousand tokens to spend, and ten
  /// snippets would crowd out the conversation they are meant to inform.
  final int maxResults;

  /// `basic` at one credit, or `advanced` at two for deeper extraction.
  final String searchDepth;

  static const String _logName = 'TavilyWebSearchService';

  /// Whether a search can be run at all. Lets a caller grey out a control
  /// rather than offer one that is certain to fail.
  Future<bool> get isConfigured async => (await _apiKey()).isNotEmpty;

  Future<WebSearchResult> search(
    String query, {
    int? maxResults,
    String topic = 'general',
    String? recency,
    List<String> includeDomains = const <String>[],
    List<String> excludeDomains = const <String>[],
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const TavilyApiException('A search needs something to search for.');
    }

    final result = await _client.search(
      apiKey: await _requireKey(),
      query: trimmed,
      maxResults: maxResults ?? this.maxResults,
      searchDepth: searchDepth,
      topic: topic,
      timeRange: recency,
      includeDomains: includeDomains,
      excludeDomains: excludeDomains,
    );

    developer.log(
      'Searched "$trimmed": ${result.hits.length} hits',
      name: _logName,
    );
    return result;
  }

  /// The stored key, or a failure a caller can show as-is.
  Future<String> _requireKey() async {
    final key = await _apiKey();
    if (key.isEmpty) {
      throw const TavilyApiException(
        'No Tavily key is set. Add one under Settings, API keys to search '
        'the web.',
      );
    }
    return key;
  }
}

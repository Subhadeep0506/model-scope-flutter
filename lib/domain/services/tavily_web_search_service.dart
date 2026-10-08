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
  final Future<String> Function() _apiKey;
  final int maxResults;
  final String searchDepth;
  static const String _logName = 'TavilyWebSearchService';

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

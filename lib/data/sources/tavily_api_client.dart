import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/web_search.dart';

/// A call to Tavily failed in a way worth telling the user — or the model —
/// about. The message is written to be readable on its own, because a tool
/// hands it straight back to the model as the result of the call.
class TavilyApiException implements Exception {
  const TavilyApiException(this.message, {this.isQuota = false});

  final String message;
  final bool isQuota;

  @override
  String toString() => message;
}

/// Thin client over the Tavily search API.
class TavilyApiClient {
  const TavilyApiClient(this._client);
  final http.Client _client;
  static const String _host = 'api.tavily.com';

  Future<WebSearchResult> search({
    required String apiKey,
    required String query,
    int maxResults = 5,
    String searchDepth = 'basic',
    String topic = 'general',
    bool includeAnswer = false,
    String? timeRange,
    List<String> includeDomains = const <String>[],
    List<String> excludeDomains = const <String>[],
  }) async {
    final body = <String, Object?>{
      'query': query,
      'max_results': maxResults.clamp(1, 20),
      'search_depth': searchDepth,
      'topic': topic,
      'include_answer': includeAnswer,
      'time_range': ?timeRange,
      if (includeDomains.isNotEmpty) 'include_domains': includeDomains,
      if (excludeDomains.isNotEmpty) 'exclude_domains': excludeDomains,
    };

    final response = await _post(Uri.https(_host, '/search'), apiKey, body);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TavilyApiException('Tavily returned an unexpected response.');
    }
    return WebSearchResult.fromJson(decoded, requestedQuery: query);
  }

  Future<http.Response> _post(
    Uri uri,
    String apiKey,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } on SocketException {
      throw const TavilyApiException('No connection to Tavily.');
    } on http.ClientException catch (error) {
      throw TavilyApiException('Could not reach Tavily: ${error.message}');
    }

    return switch (response.statusCode) {
      200 => response,
      400 || 422 => throw TavilyApiException(
        'Tavily rejected the search: ${_detailOf(response.body)}',
      ),
      401 => throw const TavilyApiException(
        'That Tavily key was rejected. Check it under Settings, API keys.',
      ),
      429 => throw const TavilyApiException(
        'Tavily is rate-limiting this key. Try again in a moment.',
      ),
      432 || 433 => throw const TavilyApiException(
        'This Tavily key is out of credits for the month.',
        isQuota: true,
      ),
      _ => throw TavilyApiException('Tavily returned ${response.statusCode}.'),
    };
  }

  static String _detailOf(String body) {
    try {
      final detail = jsonDecode(body);
      if (detail is Map<String, dynamic>) {
        final inner = detail['detail'];
        if (inner is Map<String, dynamic> && inner['error'] is String) {
          return inner['error'] as String;
        }
        if (inner is String) return inner;
      }
    } on FormatException {
      // Not JSON. The generic sentence below is the honest answer.
    }
    return 'the request was not valid';
  }
}

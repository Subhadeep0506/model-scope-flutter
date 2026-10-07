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

/// What `/usage` says about a key: which plan it is on, and how much of the
/// allowance it has spent this billing cycle. [limit] is null on an unlimited
/// plan, which the caption words differently.
class TavilyUsage {
  const TavilyUsage({required this.plan, required this.used, this.limit});

  final String plan;
  final int used;
  final int? limit;
}

/// Thin client over the Tavily search API.
class TavilyApiClient {
  const TavilyApiClient(this._client);
  final http.Client _client;
  static const String _host = 'api.tavily.com';

  /// Checks a key without spending any of it.
  ///
  /// `/usage` reports the billing cycle rather than searching, so it costs no
  /// credits — which is the whole point of pointing Verify at it rather than
  /// at `/search`.
  Future<TavilyUsage> usage({required String apiKey}) async {
    final response = await _get(Uri.https(_host, '/usage'), apiKey);
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const TavilyApiException('Tavily returned an unexpected response.');
    }

    final key = body['key'];
    final account = body['account'];
    return TavilyUsage(
      plan: account is Map<String, dynamic> && account['current_plan'] is String
          ? account['current_plan'] as String
          : 'unknown',
      used: key is Map<String, dynamic> && key['usage'] is num
          ? (key['usage'] as num).toInt()
          : 0,
      // Absent or null both mean no cap, which is what null carries here.
      limit: key is Map<String, dynamic> && key['limit'] is num
          ? (key['limit'] as num).toInt()
          : null,
    );
  }

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
  ) => _send(
    () => _client.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ),
  );

  Future<http.Response> _get(Uri uri, String apiKey) => _send(
    () => _client.get(
      uri,
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
    ),
  );

  /// Runs [request] and turns anything other than a 200 into a sentence.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } on SocketException {
      throw const TavilyApiException('No connection to Tavily.');
    } on http.ClientException catch (error) {
      throw TavilyApiException('Could not reach Tavily: ${error.message}');
    }

    return switch (response.statusCode) {
      200 => response,
      400 || 422 => throw TavilyApiException(
        'Tavily rejected the request: ${_detailOf(response.body)}',
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

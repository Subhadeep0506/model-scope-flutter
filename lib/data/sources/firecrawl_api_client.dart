import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/scraped_page.dart';

/// A call to Firecrawl failed in a way worth telling the user — or the model —
/// about. Like [TavilyApiException], the message is written to stand alone,
/// because a tool returns it to the model verbatim.
class FirecrawlApiException implements Exception {
  const FirecrawlApiException(this.message, {this.isQuota = false});

  final String message;
  final bool isQuota;

  @override
  String toString() => message;
}

/// Thin client over the Firecrawl v2 API: one page at a time, or a batch job.
class FirecrawlApiClient {
  const FirecrawlApiClient(this._client);

  final http.Client _client;

  static const String _host = 'api.firecrawl.dev';

  Future<ScrapedPage> scrape({
    required String apiKey,
    required String url,
    bool onlyMainContent = true,
    Duration timeout = const Duration(seconds: 60),
    Duration maxAge = const Duration(days: 2),
    List<String> excludeTags = const <String>[],
  }) async {
    final response = await _post(Uri.https(_host, '/v2/scrape'), apiKey, {
      'url': url,
      'formats': <String>['markdown'],
      'onlyMainContent': onlyMainContent,
      'timeout': timeout.inMilliseconds,
      'maxAge': maxAge.inMilliseconds,
      if (excludeTags.isNotEmpty) 'excludeTags': excludeTags,
    });

    final body = _decodeObject(response.body);
    return ScrapedPage.fromJson(_dataOf(body), requestedUrl: url);
  }

  Future<String> startBatch({
    required String apiKey,
    required List<String> urls,
    bool onlyMainContent = true,
    int? maxConcurrency,
    Duration maxAge = const Duration(days: 2),
  }) async {
    final response = await _post(Uri.https(_host, '/v2/batch/scrape'), apiKey, {
      'urls': urls,
      'formats': <String>['markdown'],
      'onlyMainContent': onlyMainContent,
      'maxAge': maxAge.inMilliseconds,
      // One bad URL in a list should not cost the other nine their fetch.
      'ignoreInvalidURLs': true,
      'maxConcurrency': ?maxConcurrency,
    });

    final body = _decodeObject(response.body);
    final id = body['id'];
    if (id is! String || id.isEmpty) {
      throw const FirecrawlApiException(
        'Firecrawl accepted the batch but named no job to follow.',
      );
    }
    return id;
  }

  Future<BatchScrape> batchStatus({
    required String apiKey,
    required String jobId,
    String? page,
  }) async {
    final uri = page == null
        ? Uri.https(_host, '/v2/batch/scrape/$jobId')
        : Uri.parse(page);
    final response = await _get(uri, apiKey);
    return BatchScrape.fromJson(_decodeObject(response.body));
  }

  Future<List<BatchScrapeError>> batchErrors({
    required String apiKey,
    required String jobId,
  }) async {
    final uri = Uri.https(_host, '/v2/batch/scrape/$jobId/errors');
    final response = await _get(uri, apiKey);
    final body = _decodeObject(response.body);

    final decoded = body['errors'];
    return <BatchScrapeError>[
      if (decoded is List)
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) BatchScrapeError.fromJson(entry),
      // A robots.txt refusal is reported separately but is the same news to a
      // caller: that URL produced nothing.
      for (final blocked in _robotsBlocked(body))
        BatchScrapeError(url: blocked, reason: 'blocked by robots.txt'),
    ];
  }

  static List<String> _robotsBlocked(Map<String, dynamic> body) {
    final blocked = body['robotsBlocked'];
    if (blocked is! List) return const <String>[];
    return <String>[
      for (final entry in blocked)
        if (entry is String) entry,
    ];
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
      throw const FirecrawlApiException('No connection to Firecrawl.');
    } on http.ClientException catch (error) {
      throw FirecrawlApiException(
        'Could not reach Firecrawl: ${error.message}',
      );
    }

    return switch (response.statusCode) {
      200 || 201 => response,
      400 => throw FirecrawlApiException(
        'Firecrawl rejected the request: ${_errorOf(response.body)}',
      ),
      401 || 403 => throw const FirecrawlApiException(
        'That Firecrawl key was rejected. Check it under Settings, API keys.',
      ),
      402 => throw const FirecrawlApiException(
        'This Firecrawl key is out of credits.',
        isQuota: true,
      ),
      404 => throw const FirecrawlApiException(
        'Firecrawl has nothing at that address.',
      ),
      429 => throw const FirecrawlApiException(
        'Firecrawl is rate-limiting this key. Try again in a moment.',
      ),
      _ => throw FirecrawlApiException(
        'Firecrawl returned ${response.statusCode}.',
      ),
    };
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const FirecrawlApiException(
        'Firecrawl returned something that was not JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FirecrawlApiException(
        'Firecrawl returned an unexpected response.',
      );
    }
    return decoded;
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> body) {
    if (body['success'] == false) {
      throw FirecrawlApiException(
        'Firecrawl could not read the page: '
        '${_errorOf(jsonEncode(body))}',
      );
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const FirecrawlApiException(
        'Firecrawl returned no content for that page.',
      );
    }
    return data;
  }

  static String _errorOf(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Not JSON. The generic sentence below is the honest answer.
    }
    return 'no reason given';
  }
}

import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';
import 'package:model_scope_flutter/domain/services/tavily_web_search_service.dart';

void main() {
  const Map<String, Object?> emptyResult = <String, Object?>{
    'query': 'q',
    'results': <Map<String, Object?>>[],
  };

  /// A service over a client that records what it was sent.
  (TavilyWebSearchService, List<http.Request>) serviceRecording({
    required Future<String> Function() key,
    int maxResults = 5,
  }) {
    final sent = <http.Request>[];
    final service = TavilyWebSearchService(
      TavilyApiClient(
        MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode(emptyResult), 200);
        }),
      ),
      key,
      maxResults: maxResults,
    );
    return (service, sent);
  }

  test('reads the key on every search, not once at construction', () async {
    var stored = '';
    final (service, sent) = serviceRecording(key: () async => stored);

    check(await service.isConfigured).isFalse();
    // The key is pasted into Settings after the service was built, which is
    // the ordinary order of events for a first run.
    stored = 'tvly-pasted-later';

    await service.search('dart records');

    check(sent.single.headers['Authorization'])
        .equals('Bearer tvly-pasted-later');
  });

  test('refuses a search with no key, naming where to put one', () async {
    final (service, sent) = serviceRecording(key: () async => '');

    await check(service.search('q')).throws<TavilyApiException>(
      (it) => it.has((e) => e.message, 'message').contains('Settings'),
    );
    // And without spending a request finding out.
    check(sent).isEmpty();
  });

  test('refuses an empty query before reaching the network', () async {
    final (service, sent) = serviceRecording(key: () async => 'k');

    await check(service.search('   ')).throws<TavilyApiException>();
    check(sent).isEmpty();
  });

  test('trims the query, since a model often pads it', () async {
    final (service, sent) = serviceRecording(key: () async => 'k');

    await service.search('  dart records\n');

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    check(body['query']).equals('dart records');
  });

  test('applies its own result ceiling unless told otherwise', () async {
    final (service, sent) = serviceRecording(
      key: () async => 'k',
      maxResults: 3,
    );

    await service.search('q');
    await service.search('q', maxResults: 8);

    // Five by default is a context budget, not an API limit: these go into a
    // phone-sized context alongside the conversation they inform.
    check(jsonDecode(sent.first.body))
        .isA<Map<String, Object?>>()
        .has((body) => body['max_results'], 'max_results')
        .equals(3);
    check(jsonDecode(sent.last.body))
        .isA<Map<String, Object?>>()
        .has((body) => body['max_results'], 'max_results')
        .equals(8);
  });

  test('passes the recency and topic filters through', () async {
    final (service, sent) = serviceRecording(key: () async => 'k');

    await service.search('election', topic: 'news', recency: 'week');

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    check(body['topic']).equals('news');
    check(body['time_range']).equals('week');
  });
}

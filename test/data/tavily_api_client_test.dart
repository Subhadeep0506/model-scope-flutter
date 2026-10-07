import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';

void main() {
  /// A client that answers every request with [body] at [status], handing the
  /// request it was given to [onRequest] first.
  TavilyApiClient clientReturning(
    Object body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) => TavilyApiClient(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(jsonEncode(body), status, request: request);
    }),
  );

  /// A response with one usable hit, for tests about something else.
  Map<String, Object?> oneHit = <String, Object?>{
    'query': 'dart records',
    'results': <Map<String, Object?>>[
      <String, Object?>{
        'title': 'Records',
        'url': 'https://dart.dev/language/records',
        'content': 'Records are an anonymous, immutable, aggregate type.',
        'score': 0.98,
      },
    ],
  };

  group('search', () {
    test('sends the query and the key as a bearer token', () async {
      http.Request? sent;
      final client = clientReturning(oneHit, onRequest: (r) => sent = r);

      await client.search(apiKey: 'tvly-secret', query: 'dart records');

      check(sent?.url.toString()).equals('https://api.tavily.com/search');
      check(sent?.headers['Authorization']).equals('Bearer tvly-secret');
      final body = jsonDecode(sent?.body ?? '{}') as Map<String, dynamic>;
      check(body['query']).equals('dart records');
    });

    test('asks for no answer and no raw page bodies', () async {
      http.Request? sent;
      final client = clientReturning(oneHit, onRequest: (r) => sent = r);

      await client.search(apiKey: 'k', query: 'q');

      // The cheap shape: one credit, and extracts rather than whole pages.
      // The crawler fetches the page the model picks.
      final body = jsonDecode(sent?.body ?? '{}') as Map<String, dynamic>;
      check(body['include_answer']).equals(false);
      check(body['search_depth']).equals('basic');
      check(body.containsKey('include_raw_content')).isFalse();
    });

    test('clamps max_results into the range Tavily accepts', () async {
      http.Request? sent;
      final client = clientReturning(oneHit, onRequest: (r) => sent = r);

      // Tavily rejects anything above 20 outright, and a model asking for a
      // hundred results should get twenty rather than a 422.
      await client.search(apiKey: 'k', query: 'q', maxResults: 100);

      final body = jsonDecode(sent?.body ?? '{}') as Map<String, dynamic>;
      check(body['max_results']).equals(20);
    });

    test('omits the optional filters when nothing was asked of them', () async {
      http.Request? sent;
      final client = clientReturning(oneHit, onRequest: (r) => sent = r);

      await client.search(apiKey: 'k', query: 'q');

      final body = jsonDecode(sent?.body ?? '{}') as Map<String, dynamic>;
      check(body.containsKey('time_range')).isFalse();
      check(body.containsKey('include_domains')).isFalse();
      check(body.containsKey('exclude_domains')).isFalse();
    });

    test('reads the fields a hit is shown by', () async {
      final client = clientReturning(<String, Object?>{
        'query': 'who won',
        'answer': 'They did.',
        'results': <Map<String, Object?>>[
          <String, Object?>{
            'title': 'The result',
            'url': 'https://example.com/a',
            'content': 'A short extract.',
            'score': 0.9,
            'published_date': '2026-10-01',
          },
        ],
      });

      final result = await client.search(apiKey: 'k', query: 'who won');

      check(result.query).equals('who won');
      check(result.answer).equals('They did.');
      check(result.hits).length.equals(1);
      check(result.hits.first.title).equals('The result');
      check(result.hits.first.url).equals('https://example.com/a');
      check(result.hits.first.snippet).equals('A short extract.');
      check(result.hits.first.publishedDate).equals('2026-10-01');
    });

    test('keeps Tavily ordering and drops hits with nothing in them', () async {
      final client = clientReturning(<String, Object?>{
        'query': 'q',
        'results': <Map<String, Object?>>[
          <String, Object?>{
            'title': 'First',
            'url': 'https://example.com/1',
            'content': 'Something.',
          },
          // No URL: nothing can be done with it, and a model told about it
          // would have no way to read further.
          <String, Object?>{'title': 'Second', 'content': 'Something else.'},
          <String, Object?>{
            'title': 'Third',
            'url': 'https://example.com/3',
            'content': 'More.',
          },
        ],
      });

      final result = await client.search(apiKey: 'k', query: 'q');

      check(result.hits.map((hit) => hit.title).toList())
          .deepEquals(<String>['First', 'Third']);
    });

    test('survives a response missing every optional field', () async {
      final client = clientReturning(<String, Object?>{
        'results': <Map<String, Object?>>[
          <String, Object?>{'url': 'https://example.com', 'content': 'Text.'},
        ],
      });

      final result = await client.search(apiKey: 'k', query: 'q');

      // Including the query echo, which falls back to what was sent so an
      // empty result can still name what was searched for.
      check(result.query).equals('q');
      check(result.hits.first.title).equals('Untitled');
      check(result.hits.first.score).equals(0);
      check(result.hits.first.publishedDate).isNull();
      check(result.answer).isNull();
    });

    test('names the key when Tavily rejects it', () async {
      final client = clientReturning(<String, Object?>{}, status: 401);

      await check(client.search(apiKey: 'bad', query: 'q'))
          .throws<TavilyApiException>(
            (it) => it.has((e) => e.message, 'message').contains('Settings'),
          );
    });

    test('flags a spent key, which retrying cannot fix', () async {
      final client = clientReturning(<String, Object?>{}, status: 432);

      await check(client.search(apiKey: 'k', query: 'q'))
          .throws<TavilyApiException>(
            (it) => it.has((e) => e.isQuota, 'isQuota').isTrue(),
          );
    });

    test('repeats the complaint Tavily made about a bad request', () async {
      final client = clientReturning(<String, Object?>{
        'detail': <String, Object?>{
          'error': 'include_domains_mode requires include_domains',
        },
      }, status: 400);

      await check(client.search(apiKey: 'k', query: 'q'))
          .throws<TavilyApiException>(
            (it) => it
                .has((e) => e.message, 'message')
                .contains('include_domains_mode'),
          );
    });

    test('rate limiting is reported as temporary', () async {
      final client = clientReturning(<String, Object?>{}, status: 429);

      await check(client.search(apiKey: 'k', query: 'q'))
          .throws<TavilyApiException>(
            (it) => it.has((e) => e.isQuota, 'isQuota').isFalse(),
          );
    });
  });

  group('usage', () {
    Map<String, Object?> usageBody({Object? limit = 4000}) => <String, Object?>{
      'key': <String, Object?>{'usage': 412, 'limit': limit},
      'account': <String, Object?>{'current_plan': 'Bootstrap'},
    };

    test('asks the usage endpoint, which bills nothing', () async {
      http.Request? sent;
      final client = clientReturning(usageBody(), onRequest: (r) => sent = r);

      await client.usage(apiKey: 'tvly-secret');

      // Deliberately not /search: verifying a key must not spend a credit.
      check(sent?.url.toString()).equals('https://api.tavily.com/usage');
      check(sent?.method).equals('GET');
      check(sent?.headers['Authorization']).equals('Bearer tvly-secret');
    });

    test('reads the plan and the spend', () async {
      final client = clientReturning(usageBody());

      final usage = await client.usage(apiKey: 'k');

      check(usage.plan).equals('Bootstrap');
      check(usage.used).equals(412);
      check(usage.limit).equals(4000);
    });

    test('an unlimited plan reports no cap rather than zero', () async {
      final client = clientReturning(usageBody(limit: null));

      check((await client.usage(apiKey: 'k')).limit).isNull();
    });

    test('survives a response missing every field', () async {
      final client = clientReturning(<String, Object?>{});

      final usage = await client.usage(apiKey: 'k');

      check(usage.plan).equals('unknown');
      check(usage.used).equals(0);
      check(usage.limit).isNull();
    });

    test('names the key when Tavily rejects it', () async {
      final client = clientReturning(<String, Object?>{}, status: 401);

      await check(client.usage(apiKey: 'bad')).throws<TavilyApiException>(
        (it) => it.has((e) => e.message, 'message').contains('Settings'),
      );
    });

    test('a response that is not an object is not a pass', () async {
      final client = clientReturning(<String>['not', 'an', 'object']);

      await check(client.usage(apiKey: 'k')).throws<TavilyApiException>();
    });
  });
}

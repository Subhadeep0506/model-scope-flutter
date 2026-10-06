import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/models/scraped_page.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';

void main() {
  /// A client that answers every request with [body] at [status].
  FirecrawlApiClient clientReturning(
    Object body, {
    int status = 200,
    void Function(http.BaseRequest request)? onRequest,
  }) => FirecrawlApiClient(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(jsonEncode(body), status, request: request);
    }),
  );

  /// A successful scrape of a page holding [markdown].
  Map<String, Object?> pageOf(
    String markdown, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => <String, Object?>{
    'success': true,
    'data': <String, Object?>{'markdown': markdown, 'metadata': metadata},
  };

  group('scrape', () {
    test('asks for markdown only, with the main content filter on', () async {
      http.BaseRequest? sent;
      final client = clientReturning(
        pageOf('# Hi'),
        onRequest: (r) => sent = r,
      );

      await client.scrape(apiKey: 'fc-secret', url: 'https://example.com');

      check(sent?.url.toString()).equals('https://api.firecrawl.dev/v2/scrape');
      check(sent?.headers['Authorization']).equals('Bearer fc-secret');

      final body = jsonDecode(
        (sent as http.Request?)?.body ?? '{}',
      ) as Map<String, dynamic>;
      check(body['url']).equals('https://example.com');
      check(body['formats'] as List<Object?>).deepEquals(<String>['markdown']);
      check(body['onlyMainContent']).equals(true);
    });

    test('lets Firecrawl answer from its cache by default', () async {
      http.BaseRequest? sent;
      final client = clientReturning(
        pageOf('# Hi'),
        onRequest: (r) => sent = r,
      );

      await client.scrape(apiKey: 'k', url: 'https://example.com');

      // Two days, which costs a fraction of a fresh fetch and is the right
      // trade for almost anything an agent reads.
      final body = jsonDecode(
        (sent as http.Request?)?.body ?? '{}',
      ) as Map<String, dynamic>;
      check(body['maxAge']).equals(const Duration(days: 2).inMilliseconds);
    });

    test('reads the body and the metadata a citation needs', () async {
      final client = clientReturning(
        pageOf(
          '# Records\nAn immutable aggregate type.',
          metadata: <String, Object?>{
            'title': 'Records',
            'description': 'Dart records.',
            'statusCode': 200,
            'sourceURL': 'https://dart.dev/records',
            'url': 'https://dart.dev/language/records',
          },
        ),
      );

      final page = await client.scrape(
        apiKey: 'k',
        url: 'https://dart.dev/records',
      );

      check(page.markdown).startsWith('# Records');
      check(page.title).equals('Records');
      check(page.description).equals('Dart records.');
      check(page.statusCode).equals(200);
      // The address after redirects, which is the honest citation.
      check(page.url).equals('https://dart.dev/language/records');
    });

    test('falls back to the address that was asked for', () async {
      final client = clientReturning(pageOf('Text.'));

      final page = await client.scrape(apiKey: 'k', url: 'https://example.com');

      check(page.url).equals('https://example.com');
      check(page.title).isNull();
    });

    test('a page reached but empty is not an error', () async {
      final client = clientReturning(pageOf(''));

      final page = await client.scrape(apiKey: 'k', url: 'https://example.com');

      // A paywall or a JavaScript shell. The tool layer turns this into a
      // sentence; the client has nothing to complain about.
      check(page.isEmpty).isTrue();
    });

    test('a 200 saying success:false is still a failure', () async {
      final client = clientReturning(<String, Object?>{
        'success': false,
        'error': 'This site is not supported',
      });

      await check(client.scrape(apiKey: 'k', url: 'https://example.com'))
          .throws<FirecrawlApiException>(
            (it) =>
                it.has((e) => e.message, 'message').contains('not supported'),
          );
    });

    test('names the key when Firecrawl rejects it', () async {
      final client = clientReturning(<String, Object?>{}, status: 401);

      await check(client.scrape(apiKey: 'bad', url: 'https://example.com'))
          .throws<FirecrawlApiException>(
            (it) => it.has((e) => e.message, 'message').contains('Settings'),
          );
    });

    test('flags an empty balance, which retrying cannot fix', () async {
      final client = clientReturning(<String, Object?>{}, status: 402);

      await check(client.scrape(apiKey: 'k', url: 'https://example.com'))
          .throws<FirecrawlApiException>(
            (it) => it.has((e) => e.isQuota, 'isQuota').isTrue(),
          );
    });

    test(
      'a response that is not JSON is reported, not thrown through',
      () async {
        final client = FirecrawlApiClient(
          MockClient((request) async => http.Response('<html>502</html>', 200)),
        );

        await check(client.scrape(apiKey: 'k', url: 'https://example.com'))
            .throws<FirecrawlApiException>();
      },
    );
  });

  group('startBatch', () {
    test('submits every URL and ignores the invalid ones', () async {
      http.BaseRequest? sent;
      final client = clientReturning(<String, Object?>{
        'success': true,
        'id': 'job-7',
      }, onRequest: (r) => sent = r);

      final id = await client.startBatch(
        apiKey: 'k',
        urls: <String>['https://a.com', 'https://b.com'],
      );

      check(id).equals('job-7');
      final body = jsonDecode(
        (sent as http.Request?)?.body ?? '{}',
      ) as Map<String, dynamic>;
      check(body['urls'] as List<Object?>)
          .deepEquals(<String>['https://a.com', 'https://b.com']);
      // One bad URL should not cost the others their fetch.
      check(body['ignoreInvalidURLs']).equals(true);
      check(body.containsKey('maxConcurrency')).isFalse();
    });

    test('a batch accepted without a job id is a failure', () async {
      final client = clientReturning(<String, Object?>{'success': true});

      await check(
        client.startBatch(apiKey: 'k', urls: <String>['https://a.com']),
      ).throws<FirecrawlApiException>(
        (it) => it.has((e) => e.message, 'message').contains('no job'),
      );
    });
  });

  group('batchStatus', () {
    test('reports progress and the pages gathered so far', () async {
      final client = clientReturning(<String, Object?>{
        'status': 'scraping',
        'total': 3,
        'completed': 1,
        'next': 'https://api.firecrawl.dev/v2/batch/scrape/job-7?skip=1',
        'data': <Map<String, Object?>>[
          <String, Object?>{
            'markdown': 'First page.',
            'metadata': <String, Object?>{'url': 'https://a.com'},
          },
        ],
      });

      final poll = await client.batchStatus(apiKey: 'k', jobId: 'job-7');

      check(poll.status).equals(BatchScrapeStatus.scraping);
      check(poll.status.isFinished).isFalse();
      check(poll.completed).equals(1);
      check(poll.total).equals(3);
      check(poll.pages).length.equals(1);
      check(poll.next).isNotNull();
    });

    test(
      'follows the next link it is handed rather than rebuilding it',
      () async {
        Uri? asked;
        final client = clientReturning(<String, Object?>{
          'status': 'completed',
        }, onRequest: (r) => asked = r.url);

        await client.batchStatus(
          apiKey: 'k',
          jobId: 'job-7',
          page: 'https://api.firecrawl.dev/v2/batch/scrape/job-7?skip=10',
        );

        check(asked?.queryParameters['skip']).equals('10');
      },
    );

    test('an unknown status keeps the poller waiting', () async {
      final client = clientReturning(<String, Object?>{'status': 'queued'});

      final poll = await client.batchStatus(apiKey: 'k', jobId: 'job-7');

      // A status name Firecrawl adds later should not read as a failure.
      check(poll.status).equals(BatchScrapeStatus.scraping);
    });
  });

  group('batchErrors', () {
    test('merges the refusals Firecrawl reports in two places', () async {
      final client = clientReturning(<String, Object?>{
        'errors': <Map<String, Object?>>[
          <String, Object?>{'url': 'https://a.com', 'error': 'Timed out'},
        ],
        'robotsBlocked': <String>['https://b.com'],
      });

      final errors = await client.batchErrors(apiKey: 'k', jobId: 'job-7');

      check(errors).length.equals(2);
      check(errors.first.reason).equals('Timed out');
      check(errors.last.url).equals('https://b.com');
      check(errors.last.reason).contains('robots.txt');
    });

    test('a job that failed nothing reports nothing', () async {
      final client = clientReturning(<String, Object?>{
        'errors': <Map<String, Object?>>[],
      });

      check(await client.batchErrors(apiKey: 'k', jobId: 'job-7')).isEmpty();
    });
  });
}

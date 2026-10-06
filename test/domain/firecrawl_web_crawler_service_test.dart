import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';
import 'package:model_scope_flutter/domain/services/firecrawl_web_crawler_service.dart';

void main() {
  Map<String, Object?> pageOf(String markdown, {String url = ''}) =>
      <String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'markdown': markdown,
          'metadata': <String, Object?>{if (url.isNotEmpty) 'url': url},
        },
      };

  /// A service whose every request is answered by [respond], with the request
  /// recorded first. [respond] is given the requests seen so far, so a test can
  /// script a job that finishes on the third poll.
  (FirecrawlWebCrawlerService, List<http.BaseRequest>) serviceAnswering(
    Object Function(http.BaseRequest request, int callNumber) respond, {
    String key = 'fc-test',
  }) {
    final sent = <http.BaseRequest>[];
    final service = FirecrawlWebCrawlerService(
      FirecrawlApiClient(
        MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode(respond(request, sent.length - 1)),
            200,
          );
        }),
      ),
      () async => key,
    );
    return (service, sent);
  }

  group('read', () {
    test('adds https to a bare hostname rather than refusing it', () async {
      final (service, sent) = serviceAnswering((_, _) => pageOf('Text.'));

      await service.read('example.com/page');

      // Models hand over bare hostnames often enough to be worth absorbing.
      final body = jsonDecode(
        (sent.single as http.Request).body,
      ) as Map<String, dynamic>;
      check(body['url']).equals('https://example.com/page');
    });

    test('refuses a search phrase before spending a credit on it', () async {
      final (service, sent) = serviceAnswering((_, _) => pageOf('Text.'));

      await check(
        service.read('how tall is everest'),
      ).throws<FirecrawlApiException>(
        (it) =>
            it.has((e) => e.message, 'message').contains('not a web address'),
      );
      check(sent).isEmpty();
    });

    test('refuses a bare word, which is a search and not an address', () async {
      final (service, sent) = serviceAnswering((_, _) => pageOf('Text.'));

      await check(service.read('everest')).throws<FirecrawlApiException>();
      check(sent).isEmpty();
    });

    test('refuses a scheme that is not the web', () async {
      final (service, _) = serviceAnswering((_, _) => pageOf('Text.'));

      // No reading the device's own disk through a tool call.
      await check(service.read('file:///etc/passwd'))
          .throws<FirecrawlApiException>();
    });

    test('refuses to read with no key, naming where to put one', () async {
      final (service, sent) = serviceAnswering(
        (_, _) => pageOf('Text.'),
        key: '',
      );

      check(await service.isConfigured).isFalse();
      await check(service.read('https://example.com'))
          .throws<FirecrawlApiException>(
            (it) => it.has((e) => e.message, 'message').contains('Settings'),
          );
      check(sent).isEmpty();
    });
  });

  group('readAll', () {
    test('polls until the job stops running, then collects it', () async {
      final (service, sent) = serviceAnswering((request, call) {
        if (call == 0) return <String, Object?>{'id': 'job-7'};
        // Two polls still scraping, then done.
        if (call < 3) {
          return <String, Object?>{
            'status': 'scraping',
            'total': 2,
            'completed': call,
          };
        }
        if (request.url.path.endsWith('/errors')) {
          return <String, Object?>{'errors': <Map<String, Object?>>[]};
        }
        return <String, Object?>{
          'status': 'completed',
          'data': <Map<String, Object?>>[
            <String, Object?>{
              'markdown': 'One.',
              'metadata': <String, Object?>{'url': 'https://a.com'},
            },
          ],
        };
      });

      final outcome = await service.readAll(<String>[
        'https://a.com',
        'https://b.com',
      ], pollInterval: Duration.zero);

      check(outcome.pages).length.equals(1);
      check(outcome.pages.single.url).equals('https://a.com');
      check(outcome.errors).isEmpty();
      check(sent.first.url.path).equals('/v2/batch/scrape');
    });

    test('follows the next link so a large batch is not truncated', () async {
      final (service, _) = serviceAnswering((request, call) {
        if (call == 0) return <String, Object?>{'id': 'job-7'};
        if (request.url.path.endsWith('/errors')) {
          return <String, Object?>{'errors': <Map<String, Object?>>[]};
        }
        // The status poll, then page one, then page two.
        final isSecondPage = request.url.queryParameters['skip'] == '1';
        return <String, Object?>{
          'status': 'completed',
          if (!isSecondPage)
            'next': 'https://api.firecrawl.dev/v2/batch/scrape/job-7?skip=1',
          'data': <Map<String, Object?>>[
            <String, Object?>{
              'markdown': isSecondPage ? 'Two.' : 'One.',
              'metadata': <String, Object?>{
                'url': isSecondPage ? 'https://b.com' : 'https://a.com',
              },
            },
          ],
        };
      });

      final outcome = await service.readAll(<String>[
        'https://a.com',
        'https://b.com',
      ], pollInterval: Duration.zero);

      // Returning half a batch silently is how an agent comes to state
      // something it never read.
      check(outcome.pages.map((page) => page.url).toList())
          .deepEquals(<String>['https://a.com', 'https://b.com']);
    });

    test(
      'reports the URLs that failed alongside the pages that did not',
      () async {
        final (service, _) = serviceAnswering((request, call) {
          if (call == 0) return <String, Object?>{'id': 'job-7'};
          if (request.url.path.endsWith('/errors')) {
            return <String, Object?>{
              'errors': <Map<String, Object?>>[
                <String, Object?>{'url': 'https://b.com', 'error': 'Timed out'},
              ],
              'robotsBlocked': <String>['https://c.com'],
            };
          }
          return <String, Object?>{
            'status': 'completed',
            'data': <Map<String, Object?>>[
              <String, Object?>{
                'markdown': 'One.',
                'metadata': <String, Object?>{'url': 'https://a.com'},
              },
            ],
          };
        });

        final outcome = await service.readAll(<String>[
          'https://a.com',
          'https://b.com',
          'https://c.com',
        ], pollInterval: Duration.zero);

        check(outcome.pages).length.equals(1);
        check(outcome.errors.map((error) => error.url).toList())
            .deepEquals(<String>['https://b.com', 'https://c.com']);
      },
    );

    test(
      'a job that fails still hands back what it managed to gather',
      () async {
        final (service, _) = serviceAnswering((request, call) {
          if (call == 0) return <String, Object?>{'id': 'job-7'};
          if (request.url.path.endsWith('/errors')) {
            return <String, Object?>{
              'errors': <Map<String, Object?>>[
                <String, Object?>{'url': 'https://b.com', 'error': 'Refused'},
              ],
            };
          }
          return <String, Object?>{
            'status': 'failed',
            'data': <Map<String, Object?>>[
              <String, Object?>{
                'markdown': 'One.',
                'metadata': <String, Object?>{'url': 'https://a.com'},
              },
            ],
          };
        });

        final outcome = await service.readAll(<String>[
          'https://a.com',
          'https://b.com',
        ], pollInterval: Duration.zero);

        // The page that did come back is worth having, and the errors list
        // explains the rest.
        check(outcome.pages).length.equals(1);
        check(outcome.errors).length.equals(1);
      },
    );

    test('gives up on a job that never finishes', () async {
      final (service, _) = serviceAnswering((request, call) {
        if (call == 0) return <String, Object?>{'id': 'job-7'};
        return <String, Object?>{
          'status': 'scraping',
          'total': 5,
          'completed': 1,
        };
      });

      await check(
        service.readAll(
          <String>['https://a.com'],
          pollInterval: Duration.zero,
          deadline: Duration.zero,
        ),
      ).throws<FirecrawlApiException>(
        (it) => it.has((e) => e.message, 'message').contains('1 of 5'),
      );
    });

    test('refuses an empty batch', () async {
      final (service, sent) = serviceAnswering((_, _) => <String, Object?>{});

      await check(service.readAll(const <String>[]))
          .throws<FirecrawlApiException>();
      check(sent).isEmpty();
    });
  });
}

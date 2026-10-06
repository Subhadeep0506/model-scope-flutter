import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';
import 'package:model_scope_flutter/domain/services/firecrawl_web_crawler_service.dart';
import 'package:model_scope_flutter/domain/services/tavily_web_search_service.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/tool_registry.dart';

void main() {
  /// The registry the app builds, over services whose keys are whatever the
  /// test says. No request is ever made: asking whether a key is set does not
  /// touch the network.
  ToolRegistry standard({String tavily = '', String firecrawl = ''}) {
    final client = MockClient(
      (_) async => throw StateError('the registry must not call out'),
    );
    return ToolRegistry.standard(
      search: TavilyWebSearchService(
        TavilyApiClient(client),
        () async => tavily,
      ),
      crawler: FirecrawlWebCrawlerService(
        FirecrawlApiClient(client),
        () async => firecrawl,
      ),
    );
  }

  group('what this build ships', () {
    test('registers the five tools an agent may name', () {
      check(standard().names).deepEquals(<String>[
        'calculator',
        'date_math',
        'read_web_page',
        'unit_convert',
        'web_search',
      ]);
    });

    test('counts them for the TOOLS tile', () {
      check(standard().count).equals(5);
    });

    test('hands back the tool behind a name', () {
      final tool = standard().byName('web_search');

      check(tool).isNotNull().has((t) => t.name, 'name').equals('web_search');
      check(standard().byName('pdf_parse')).isNull();
      check(standard().has('calculator')).isTrue();
      check(standard().has('pdf_parse')).isFalse();
    });
  });

  group('whether a tool can run', () {
    test('a tool needing no key is always ready', () async {
      for (final name in <String>['calculator', 'date_math', 'unit_convert']) {
        check(await standard().blockerFor(name), because: name).isNull();
      }
    });

    test('a missing key is reported in the design own words', () async {
      final registry = standard();

      check(await registry.blockerFor('web_search'))
          .equals('Needs Tavily key — set it in Settings');
      check(await registry.blockerFor('read_web_page'))
          .equals('Needs Firecrawl key — set it in Settings');
    });

    test('a key that is set clears the blocker', () async {
      final registry = standard(tavily: 'tvly-x', firecrawl: 'fc-x');

      check(await registry.blockerFor('web_search')).isNull();
      check(await registry.blockerFor('read_web_page')).isNull();
    });

    test('the key is read per call, not held', () async {
      var stored = '';
      final registry = ToolRegistry.standard(
        search: TavilyWebSearchService(
          TavilyApiClient(MockClient((_) async => http.Response('{}', 200))),
          () async => stored,
        ),
        crawler: FirecrawlWebCrawlerService(
          FirecrawlApiClient(MockClient((_) async => http.Response('{}', 200))),
          () async => '',
        ),
      );

      check(await registry.blockerFor('web_search')).isNotNull();
      // Pasted into Settings after the registry was built, which is the
      // ordinary order of events on a first run.
      stored = 'tvly-pasted-later';

      check(await registry.blockerFor('web_search')).isNull();
    });

    test(
      'a tool this build does not have is said so, not blamed on a key',
      () async {
        // Two different failures: one the user can fix in Settings, one they
        // cannot fix at all.
        check(await standard().blockerFor('pdf_parse'))
            .equals('pdf_parse is not a tool in this build');
      },
    );
  });

  test('an empty registry has nothing and blocks everything', () async {
    check(ToolRegistry.empty.names).isEmpty();
    check(ToolRegistry.empty.count).equals(0);
    check(await ToolRegistry.empty.blockerFor('web_search')).isNotNull();
  });

  test('a registry built by hand keeps the tools it was given', () {
    final registry = ToolRegistry(
      tools: <ToolDefinition>[
        ToolDefinition(
          name: 'only_one',
          description: 'For a test.',
          function: ({required String input}) async => 'ok',
        ),
      ],
    );

    check(registry.names).deepEquals(<String>['only_one']);
  });
}

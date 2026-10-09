import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';
import 'package:model_scope_flutter/domain/services/firecrawl_web_crawler_service.dart';
import 'package:model_scope_flutter/domain/services/tavily_web_search_service.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/web_tools.dart';

void main() {
  /// Calls [tool] the way `package:nobodywho` does — by name, through
  /// [Function.apply] — rather than through a typed reference. That is the
  /// path a real tool call takes, and it is the one that fails if the
  /// signature is ever widened past what the schema generator accepts.
  Future<String> invoke(ToolDefinition tool, Map<Symbol, Object?> arguments) =>
      Function.apply(tool.function, const <Object?>[], arguments)
          as Future<String>;

  TavilyWebSearchService searchOver(
    MockClient client, {
    String key = 'tvly-test',
  }) => TavilyWebSearchService(TavilyApiClient(client), () async => key);

  FirecrawlWebCrawlerService crawlerOver(
    MockClient client, {
    String key = 'fc-test',
  }) => FirecrawlWebCrawlerService(FirecrawlApiClient(client), () async => key);

  MockClient answering(Object body, {int status = 200}) =>
      MockClient((request) async => http.Response(jsonEncode(body), status));

  /// Tavily's shape. The query is left out so the client's fallback to the one
  /// that was actually sent is the thing under test.
  Map<String, Object?> hitsOf(List<Map<String, Object?>> results) =>
      <String, Object?>{'results': results};

  Map<String, Object?> pageOf(
    String markdown, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => <String, Object?>{
    'success': true,
    'data': <String, Object?>{'markdown': markdown, 'metadata': metadata},
  };

  group('the limits a run sets', () {
    test('the result count reaches Tavily', () async {
      // What the agent's `WEB RESULTS` slider is for: the number has to leave
      // the device, or a lower setting costs nothing and the context still
      // fills up.
      Map<String, Object?>? sent;
      final tool = webSearchTool(
        searchOver(
          MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(jsonEncode(hitsOf(const [])), 200);
          }),
        ),
        settings: WebSearchSettings(maxResults: 2),
      );

      await invoke(tool, <Symbol, Object?>{#query: 'q'});

      check(sent).isNotNull()['max_results'].equals(2);
    });

    test('a limit changed after the tool was built is still used', () async {
      // The registry builds a tool once and a run writes its limits later, so
      // the numbers have to be read per call rather than captured.
      final settings = WebSearchSettings(maxResults: 2);
      final sent = <int>[];
      final tool = webSearchTool(
        searchOver(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            sent.add(body['max_results'] as int);
            return http.Response(jsonEncode(hitsOf(const [])), 200);
          }),
        ),
        settings: settings,
      );

      await invoke(tool, <Symbol, Object?>{#query: 'q'});
      settings.apply(maxResults: 6);
      await invoke(tool, <Symbol, Object?>{#query: 'q'});

      check(sent).deepEquals(<int>[2, 6]);
    });

    test('both web tools share one set of limits', () {
      // Built from one holder, so a run writes the budget once and the search
      // and the page read that follows it agree about it.
      final settings = WebSearchSettings();
      final tools = webTools(
        search: searchOver(answering(hitsOf(const []))),
        crawler: crawlerOver(answering(pageOf(''))),
        settings: settings,
      );

      check(tools).length.equals(2);
      settings.apply(maxResults: 9, pageLimit: 1000);
      check(settings.maxResults).equals(9);
      check(settings.pageLimit).equals(1000);
    });

    test('a nonsensical number is held to something workable', () {
      final settings = WebSearchSettings()
        ..apply(maxResults: 0, snippetLimit: 1, pageLimit: -5);

      check(settings.maxResults).equals(1);
      check(settings.snippetLimit).equals(80);
      check(settings.pageLimit).equals(200);
    });
  });

  group('what the model is told', () {
    test('each tool takes one required named String', () {
      final search = webSearchTool(searchOver(answering(hitsOf(const []))));
      final read = readWebPageTool(crawlerOver(answering(pageOf(''))));

      // `nobodywho` builds the JSON schema by parsing this exact string. An
      // optional parameter or a type outside String/int/double/bool and their
      // lists is not something it is known to handle, so the shape is pinned.
      check(search.function.runtimeType.toString())
          .contains('{required String query}');
      check(read.function.runtimeType.toString())
          .contains('{required String url}');
    });

    test('every parameter carries a description, by name', () {
      final tools = webTools(
        search: searchOver(answering(hitsOf(const []))),
        crawler: crawlerOver(answering(pageOf(''))),
      );

      check(tools.map((tool) => tool.name).toList())
          .deepEquals(<String>['web_search', 'read_web_page']);
      // A description keyed by a name the function does not have would reach
      // the model attached to nothing.
      check(tools.first.parameterDescriptions.keys.toList())
          .deepEquals(<String>['query']);
      check(tools.last.parameterDescriptions.keys.toList())
          .deepEquals(<String>['url']);
    });

    test('each description points at the other tool', () {
      final tools = webTools(
        search: searchOver(answering(hitsOf(const []))),
        crawler: crawlerOver(answering(pageOf(''))),
      );

      // The two are only useful together: search returns extracts, and the
      // model has to know that reading one in full is a second call.
      check(tools.first.description).contains('read_web_page');
      check(tools.last.description).contains('web_search');
    });
  });

  group('web_search', () {
    test('numbers the results and gives each one its address', () async {
      final tool = webSearchTool(
        searchOver(
          answering(
            hitsOf(<Map<String, Object?>>[
              <String, Object?>{
                'title': 'Records',
                'url': 'https://dart.dev/language/records',
                'content': 'An immutable aggregate type.',
              },
              <String, Object?>{
                'title': 'Patterns',
                'url': 'https://dart.dev/language/patterns',
                'content': 'Destructuring.',
              },
            ]),
          ),
        ),
      );

      final answer = await invoke(tool, <Symbol, Object?>{#query: 'records'});

      check(answer).contains('1. Records');
      check(answer).contains('https://dart.dev/language/records');
      check(answer).contains('2. Patterns');
      check(answer).contains('An immutable aggregate type.');
    });

    test(
      'says so when there is nothing, rather than returning blank',
      () async {
        final tool = webSearchTool(searchOver(answering(hitsOf(const []))));

        final answer = await invoke(tool, <Symbol, Object?>{
          #query: 'asdfqwer',
        });

        // A model handed an empty string fills the silence from its weights,
        // which is the failure searching was meant to prevent.
        check(answer).contains('No results');
        check(answer).contains('asdfqwer');
      },
    );

    test('cuts a long snippet to its budget', () async {
      final tool = webSearchTool(
        searchOver(
          answering(
            hitsOf(<Map<String, Object?>>[
              <String, Object?>{
                'title': 'Long',
                'url': 'https://example.com',
                'content': List<String>.filled(200, 'word').join(' '),
              },
            ]),
          ),
        ),
        settings: WebSearchSettings(snippetLimit: 80),
      );

      final answer = await invoke(tool, <Symbol, Object?>{#query: 'q'});

      check(answer).contains('…');
      check(answer.length).isLessThan(300);
    });

    test('a missing key comes back as a sentence, not an exception', () async {
      final tool = webSearchTool(
        searchOver(answering(hitsOf(const [])), key: ''),
      );

      // A tool that throws has its exception text returned to the model
      // anyway, but reads as an answer. Saying it plainly is the difference
      // between the model relaying the problem and inventing around it.
      final answer = await invoke(tool, <Symbol, Object?>{#query: 'q'});

      check(answer).contains('No Tavily key is set');
      check(answer).contains('Settings');
    });

    test('a rejected key comes back as a sentence too', () async {
      final tool = webSearchTool(
        searchOver(answering(<String, Object?>{}, status: 401)),
      );

      final answer = await invoke(tool, <Symbol, Object?>{#query: 'q'});

      check(answer).startsWith('The web search failed.');
    });
  });

  group('read_web_page', () {
    test('puts the title and the source above the text', () async {
      final tool = readWebPageTool(
        crawlerOver(
          answering(
            pageOf(
              '# Records\nAn immutable aggregate type.',
              metadata: <String, Object?>{
                'title': 'Records',
                'url': 'https://dart.dev/language/records',
              },
            ),
          ),
        ),
      );

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'https://dart.dev/records',
      });

      // The citation sits in front of the model while it quotes the content,
      // rather than having to be recalled from the argument it passed.
      check(answer).startsWith('# Records');
      check(answer).contains('Source: https://dart.dev/language/records');
      check(answer).contains('An immutable aggregate type.');
    });

    test('cuts a long page and says that it did', () async {
      final body = List<String>.filled(500, 'A sentence of text.').join('\n');
      final tool = readWebPageTool(
        crawlerOver(answering(pageOf(body))),
        settings: WebSearchSettings(pageLimit: 200),
      );

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'https://example.com',
      });

      check(answer).contains('Cut short');
      check(answer).contains(body.length.toString());
      check(answer.length).isLessThan(500);
    });

    test('leaves a page that already fits entirely alone', () async {
      final tool = readWebPageTool(crawlerOver(answering(pageOf('Short.'))));

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'https://example.com',
      });

      check(answer).contains('Short.');
      check(answer).not((it) => it.contains('Cut short'));
    });

    test('explains a page that was reached but held nothing', () async {
      final tool = readWebPageTool(crawlerOver(answering(pageOf(''))));

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'https://example.com',
      });

      check(answer).contains('no readable text');
      check(answer).contains('login');
    });

    test('refuses something that is not a web address, in words', () async {
      final tool = readWebPageTool(crawlerOver(answering(pageOf('x'))));

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'how tall is everest',
      });

      check(answer).contains('not a web address');
    });

    test('a missing key comes back as a sentence', () async {
      final tool = readWebPageTool(
        crawlerOver(answering(pageOf('x')), key: ''),
      );

      final answer = await invoke(tool, <Symbol, Object?>{
        #url: 'https://example.com',
      });

      check(answer).contains('No Firecrawl key is set');
    });
  });
}

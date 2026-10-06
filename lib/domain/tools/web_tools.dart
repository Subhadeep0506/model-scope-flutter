/// The two tools that let a model reach past its weights: one to find pages,
/// one to read them.
///
/// Both take a single required `String`, which is as narrow as a tool surface
/// gets. That is deliberate. These run against a four-billion-parameter model
/// on a phone, and every extra field is another chance for it to emit an
/// argument the API rejects. Depth, domain filters, timeouts and result counts
/// are all set in Dart on the services, where they can be reasoned about once
/// rather than guessed at per call.
///
/// Every character returned is spent out of a context measured in thousands of
/// tokens, so both tools cut their output to a budget and say when they have.
library;

import '../../data/models/scraped_page.dart';
import '../../data/models/web_search.dart';
import '../../data/sources/firecrawl_api_client.dart';
import '../../data/sources/tavily_api_client.dart';
import '../services/firecrawl_web_crawler_service.dart';
import '../services/tavily_web_search_service.dart';
import 'tool_definition.dart';

/// How much of a search snippet survives. Five of these plus titles and URLs
/// comes to roughly 600 tokens.
const int kSnippetLimit = 400;

/// How much of a page survives. A news article runs to about this; a
/// documentation page runs to ten times it, and the first quarter is where the
/// answer usually is.
const int kPageLimit = 4000;

/// Searches the web with [service].
ToolDefinition webSearchTool(
  TavilyWebSearchService service, {
  int snippetLimit = kSnippetLimit,
}) {
  Future<String> run({required String query}) async {
    try {
      final result = await service.search(query);
      return formatSearchResult(result, snippetLimit: snippetLimit);
    } on TavilyApiException catch (error) {
      return 'The web search failed. $error';
    }
  }

  return ToolDefinition(
    name: 'web_search',
    description:
        'Search the web and get back a numbered list of pages, each with a '
        'short extract. Use this whenever the answer depends on current '
        'events or on facts you are unsure of. It returns extracts, not whole '
        'pages: to read one in full, call read_web_page with its URL.',
    function: run,
    parameterDescriptions: const <String, String>{
      'query':
          'What to search for, as a plain search phrase of a few words. '
          'Not a question and not a URL.',
    },
  );
}

/// Reads one page with [service].
ToolDefinition readWebPageTool(
  FirecrawlWebCrawlerService service, {
  int pageLimit = kPageLimit,
}) {
  Future<String> run({required String url}) async {
    try {
      final page = await service.read(url);
      return formatPage(page, pageLimit: pageLimit);
    } on FirecrawlApiException catch (error) {
      return 'That page could not be read. $error';
    }
  }

  return ToolDefinition(
    name: 'read_web_page',
    description:
        'Fetch one web page and return its text. Use this to read a page you '
        'already have the address of — usually one that web_search returned. '
        'Long pages are cut short, and the reply says so when they are.',
    function: run,
    parameterDescriptions: const <String, String>{
      'url':
          'The full web address of the page to read, for example '
          'https://example.com/article. One address, not a search phrase.',
    },
  );
}

/// Every web tool, ready to be handed to a chat.
List<ToolDefinition> webTools({
  required TavilyWebSearchService search,
  required FirecrawlWebCrawlerService crawler,
}) => <ToolDefinition>[webSearchTool(search), readWebPageTool(crawler)];

/// Renders [result] as the numbered list a model reads.
///
/// An empty result is reported as such rather than returned blank: a model
/// given nothing tends to fill the silence from its weights, which is the
/// failure a search was meant to prevent.
String formatSearchResult(
  WebSearchResult result, {
  int snippetLimit = kSnippetLimit,
}) {
  if (result.hits.isEmpty) {
    return 'No results were found for "${result.query}". Try different words.';
  }

  final lines = <String>[
    'Results for "${result.query}":',
    if (result.answer case final answer?) '\nSummary: $answer',
  ];
  for (final (index, hit) in result.hits.indexed) {
    lines.add('\n${index + 1}. ${hit.title}');
    lines.add('   ${hit.url}');
    if (hit.publishedDate case final date?) lines.add('   Published: $date');
    lines.add('   ${truncate(hit.snippet, snippetLimit)}');
  }
  return lines.join('\n');
}

/// Renders [page] with its address at the top, so a model quoting the content
/// has the citation in front of it rather than having to recall the argument
/// it passed.
String formatPage(ScrapedPage page, {int pageLimit = kPageLimit}) {
  if (page.isEmpty) {
    return 'The page at ${page.url} was reached but held no readable text. '
        'It may need a login, or be built entirely in JavaScript.';
  }

  final body = truncate(page.markdown, pageLimit);
  final wasCut = body.length < page.markdown.length;
  return <String>[
    if (page.title case final title?) '# $title',
    'Source: ${page.url}',
    if (wasCut)
      '(Cut short: about the first $pageLimit of '
          '${page.markdown.length} characters.)',
    '',
    body,
  ].join('\n');
}

/// [text] cut to [limit] characters, at the last line break before the cut so
/// the result does not end mid-sentence. Returns [text] when it already fits.
String truncate(String text, int limit) {
  if (text.length <= limit) return text;

  final head = text.substring(0, limit);
  final lastBreak = head.lastIndexOf('\n');
  // Only honour the break when it keeps most of the budget; a page whose first
  // line runs past the limit would otherwise come back almost empty.
  final cut = lastBreak > limit ~/ 2 ? head.substring(0, lastBreak) : head;
  return '${cut.trimRight()}…';
}

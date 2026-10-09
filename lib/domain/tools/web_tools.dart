library;

import '../../data/models/agent_template.dart';
import '../../data/models/scraped_page.dart';
import '../../data/models/web_search.dart';
import '../../data/sources/firecrawl_api_client.dart';
import '../../data/sources/tavily_api_client.dart';
import '../services/firecrawl_web_crawler_service.dart';
import '../services/tavily_web_search_service.dart';
import 'tool_definition.dart';

const int kMaxResults = AgentLimits.defaultWebResults;
const int kSnippetLimit = AgentLimits.defaultWebSnippetChars;
const int kPageLimit = AgentLimits.defaultWebPageChars;

/// What the current agent run wants from the web.
///
/// Held in one mutable object the run writes before it starts, for the same
/// reason [RetrievalSettings] is: a tool is built once in the registry and
/// knows nothing about the run calling it, so the numbers have to be read per
/// call rather than captured when the tool was made.
class WebSearchSettings {
  WebSearchSettings({
    this.maxResults = kMaxResults,
    this.snippetLimit = kSnippetLimit,
    this.pageLimit = kPageLimit,
  });

  /// How many pages a search asks Tavily for.
  int maxResults;

  /// How much of each result's extract survives into the model's context.
  int snippetLimit;

  /// How much of a fetched page does.
  int pageLimit;

  void apply({int? maxResults, int? snippetLimit, int? pageLimit}) {
    this.maxResults = (maxResults ?? this.maxResults).clamp(1, 20);
    this.snippetLimit = (snippetLimit ?? this.snippetLimit).clamp(80, 20000);
    this.pageLimit = (pageLimit ?? this.pageLimit).clamp(200, 100000);
  }
}

ToolDefinition webSearchTool(
  TavilyWebSearchService service, {
  WebSearchSettings? settings,
}) {
  final limits = settings ?? WebSearchSettings();

  Future<String> run({required String query}) async {
    try {
      final result = await service.search(query, maxResults: limits.maxResults);
      return formatSearchResult(result, snippetLimit: limits.snippetLimit);
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

ToolDefinition readWebPageTool(
  FirecrawlWebCrawlerService service, {
  WebSearchSettings? settings,
}) {
  final limits = settings ?? WebSearchSettings();

  Future<String> run({required String url}) async {
    try {
      final page = await service.read(url);
      return formatPage(page, pageLimit: limits.pageLimit);
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

List<ToolDefinition> webTools({
  required TavilyWebSearchService search,
  required FirecrawlWebCrawlerService crawler,
  WebSearchSettings? settings,
}) {
  // One holder for both tools, so an agent's limits are written once and a
  // search and the page read that follows it agree about the budget.
  final limits = settings ?? WebSearchSettings();
  return <ToolDefinition>[
    webSearchTool(search, settings: limits),
    readWebPageTool(crawler, settings: limits),
  ];
}

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

String truncate(String text, int limit) {
  if (text.length <= limit) return text;

  final head = text.substring(0, limit);
  final lastBreak = head.lastIndexOf('\n');
  final cut = lastBreak > limit ~/ 2 ? head.substring(0, lastBreak) : head;
  return '${cut.trimRight()}…';
}

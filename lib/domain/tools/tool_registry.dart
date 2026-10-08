import '../../data/repositories/document_index_repository.dart';
import '../services/embedding_service.dart';
import '../services/firecrawl_web_crawler_service.dart';
import '../services/open_meteo_weather_service.dart';
import '../services/tavily_web_search_service.dart';
import 'calc_tools.dart';
import 'document_tools.dart';
import 'tool_definition.dart';
import 'weather_tools.dart';
import 'web_tools.dart';

typedef ToolBlocker = String;

class ToolRegistry {
  ToolRegistry({
    required List<ToolDefinition> tools,
    this.readiness = const <String, Future<bool> Function()>{},
    this.blockers = const <String, ToolBlocker>{},
  }) : _tools = <String, ToolDefinition>{
         for (final tool in tools) tool.name: tool,
       };

  factory ToolRegistry.standard({
    required TavilyWebSearchService search,
    required FirecrawlWebCrawlerService crawler,
    required OpenMeteoWeatherService weather,
    required DocumentIndexRepository documents,
    required EmbeddingService embedder,
    required RetrievalSettings retrieval,
    required Future<bool> Function() hasEmbeddingModel,
  }) => ToolRegistry(
    tools: <ToolDefinition>[
      ...webTools(search: search, crawler: crawler),
      weatherTool(weather),
      searchDocumentTool(
        index: documents,
        embedder: embedder,
        settings: retrieval,
      ),
      calculatorTool(),
      dateMathTool(),
      unitConvertTool(),
    ],
    readiness: <String, Future<bool> Function()>{
      'web_search': () => search.isConfigured,
      'read_web_page': () => crawler.isConfigured,
      'search_document': hasEmbeddingModel,
    },
    blockers: const <String, ToolBlocker>{
      'web_search': 'Needs Tavily key — set it in Settings',
      'read_web_page': 'Needs Firecrawl key — set it in Settings',
      'search_document': 'Needs an embedding model — download one in Settings',
    },
  );

  final Map<String, ToolDefinition> _tools;
  final Map<String, Future<bool> Function()> readiness;

  final Map<String, ToolBlocker> blockers;
  static final ToolRegistry empty = ToolRegistry(
    tools: const <ToolDefinition>[],
  );
  ToolDefinition? byName(String name) => _tools[name];

  bool has(String name) => _tools.containsKey(name);
  List<String> get names => _tools.keys.toList()..sort();

  int get count => _tools.length;
  Future<ToolBlocker?> blockerFor(String name) async {
    if (!has(name)) return '$name is not a tool in this build';

    final check = readiness[name];
    if (check == null) return null;
    return await check()
        ? null
        : blockers[name] ?? 'Needs a key — set it in Settings';
  }
}

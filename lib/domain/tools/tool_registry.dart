import '../services/firecrawl_web_crawler_service.dart';
import '../services/tavily_web_search_service.dart';
import 'calc_tools.dart';
import 'tool_definition.dart';
import 'web_tools.dart';

/// Why a tool cannot be used right now, in the words the design puts in the
/// amber banner under a step in the pipeline builder.
typedef ToolBlocker = String;

/// Every tool an agent template may name, by name.
///
/// A template refers to a tool as a string, because a template is a JSON file
/// that outlives any particular build. This is the one place those strings
/// become real functions — so an agent naming a tool that was renamed, or that
/// this build does not ship, is caught here and reported rather than failing
/// mid-run.
///
/// Availability is a separate question from existence. `web_search` exists in
/// every build but cannot run without a Tavily key, and the user can fix that
/// in Settings; [blockerFor] is what the validator asks so the agent card can
/// say so before the run rather than after.
class ToolRegistry {
  ToolRegistry({
    required List<ToolDefinition> tools,
    this.readiness = const <String, Future<bool> Function()>{},
    this.blockers = const <String, ToolBlocker>{},
  }) : _tools = <String, ToolDefinition>{
         for (final tool in tools) tool.name: tool,
       };

  /// Everything this build ships: the two web tools, which need a key, and the
  /// three offline ones, which do not.
  factory ToolRegistry.standard({
    required TavilyWebSearchService search,
    required FirecrawlWebCrawlerService crawler,
  }) => ToolRegistry(
    tools: <ToolDefinition>[
      ...webTools(search: search, crawler: crawler),
      calculatorTool(),
      dateMathTool(),
      unitConvertTool(),
    ],
    readiness: <String, Future<bool> Function()>{
      'web_search': () => search.isConfigured,
      'read_web_page': () => crawler.isConfigured,
    },
    // Worded as the pipeline builder's amber banner words it.
    blockers: const <String, ToolBlocker>{
      'web_search': 'Needs Tavily key — set it in Settings',
      'read_web_page': 'Needs Firecrawl key — set it in Settings',
    },
  );

  final Map<String, ToolDefinition> _tools;

  /// Asks each gated tool whether its key is set. Checked per call rather than
  /// cached, so a key pasted into Settings takes effect without a restart. A
  /// tool with no entry here needs nothing and is always ready.
  final Map<String, Future<bool> Function()> readiness;

  /// What to say when a tool's readiness check comes back false.
  final Map<String, ToolBlocker> blockers;

  /// A registry holding nothing, for a test that wants every tool to be
  /// missing.
  static final ToolRegistry empty = ToolRegistry(
    tools: const <ToolDefinition>[],
  );

  /// The tool called [name], or null when this build has no such tool.
  ToolDefinition? byName(String name) => _tools[name];

  bool has(String name) => _tools.containsKey(name);

  /// Every registered name, sorted so the count on the Agent bench and any
  /// listing of them are stable.
  List<String> get names => _tools.keys.toList()..sort();

  int get count => _tools.length;

  /// Why [name] cannot run, or null when it can.
  ///
  /// Two different failures, deliberately worded apart: a tool this build does
  /// not have is a template problem the user cannot fix, while a missing key
  /// is a Settings problem they can.
  Future<ToolBlocker?> blockerFor(String name) async {
    if (!has(name)) return '$name is not a tool in this build';

    final check = readiness[name];
    if (check == null) return null;
    return await check()
        ? null
        : blockers[name] ?? 'Needs a key — set it in Settings';
  }
}

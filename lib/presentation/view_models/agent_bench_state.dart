import '../../data/models/agent_run.dart';
import '../../data/repositories/agent_repository.dart';

/// One card on the Agent bench: the agent, when it last ran, and what — if
/// anything — stops it running now.
class AgentListing {
  const AgentListing({required this.agent, this.lastRun, this.blocker});

  final Agent agent;

  /// The most recent run of this agent, or null when it has never run — which
  /// is what puts `never run` on the card.
  final AgentRun? lastRun;

  /// The one amber line under the card: `Needs Tavily key — set it in
  /// Settings`. Null when the agent can run right now.
  final String? blocker;

  String get id => agent.id;

  bool get canRun => blocker == null;
}

/// Everything the Agent bench draws.
class AgentBenchState {
  const AgentBenchState({
    required this.custom,
    required this.builtIn,
    required this.runCount,
    required this.averageRunMs,
    required this.toolCount,
  });

  static const AgentBenchState empty = AgentBenchState(
    custom: <AgentListing>[],
    builtIn: <AgentListing>[],
    runCount: 0,
    averageRunMs: 0,
    toolCount: 0,
  );

  /// Agents the user built, drawn under `My agents`. Empty in this build,
  /// which is what the dashed empty-state card is for.
  final List<AgentListing> custom;

  /// Agents shipped in `assets/agents/`, drawn under `Built-in`.
  final List<AgentListing> builtIn;

  /// The `RUNS` tile: every run still in the history file, across all agents.
  final int runCount;

  /// The `AVG RUN` tile, in milliseconds.
  final int averageRunMs;

  /// The `TOOLS n registered` tile.
  final int toolCount;

  /// The overline: `4 AGENTS AVAILABLE`.
  int get agentCount => custom.length + builtIn.length;

  /// `4.30s`, the figure on the AVG RUN tile.
  String get averageRunLabel => '${(averageRunMs / 1000).toStringAsFixed(2)}s';
}

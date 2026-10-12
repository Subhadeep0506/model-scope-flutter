import '../../data/models/agent_run.dart';
import '../../data/repositories/agent_repository.dart';

/// One card on the Agent bench: the agent, when it last ran, and what — if
/// anything — stops it running now.
class AgentListing {
  const AgentListing({required this.agent, this.lastRun, this.blocker});

  final Agent agent;
  final AgentRun? lastRun;
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
  final List<AgentListing> custom;
  final List<AgentListing> builtIn;
  final int runCount;
  final int averageRunMs;
  final int toolCount;
  int get agentCount => custom.length + builtIn.length;
  String get averageRunLabel => '${(averageRunMs / 1000).toStringAsFixed(2)}s';
}

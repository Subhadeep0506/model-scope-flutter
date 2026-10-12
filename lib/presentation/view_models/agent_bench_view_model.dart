import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/agent_run.dart';
import 'agent_bench_state.dart';

/// Builds the Agent bench: the cards, and the three figures above them.
class AgentBenchViewModel extends AsyncNotifier<AgentBenchState> {
  @override
  Future<AgentBenchState> build() async {
    final agents = await ref.watch(agentsProvider.future);
    final runs = await ref.watch(agentRunsProvider.future);
    final library = await ref.watch(modelLibraryViewModelProvider.future);
    final validator = ref.watch(agentValidatorProvider);

    final listings = <AgentListing>[];
    for (final agent in agents) {
      final availability = await validator.check(
        agent.template,
        hasModel: library.chatModels.isNotEmpty,
        values: agent.template.defaultValues,
      );
      listings.add(
        AgentListing(
          agent: agent,
          lastRun: _lastRunOf(runs, agent.id),
          blocker: availability.firstBlocker,
        ),
      );
    }

    return AgentBenchState(
      custom: <AgentListing>[
        for (final listing in listings)
          if (!listing.agent.isBuiltIn) listing,
      ],
      builtIn: <AgentListing>[
        for (final listing in listings)
          if (listing.agent.isBuiltIn) listing,
      ],
      runCount: runs.length,
      averageRunMs: _meanDuration(runs),
      toolCount: ref.watch(toolRegistryProvider).count,
    );
  }

  /// The history is newest first, so the first match is the latest run.
  static AgentRun? _lastRunOf(List<AgentRun> runs, String agentId) {
    for (final run in runs) {
      if (run.agentId == agentId) return run;
    }
    return null;
  }

  static int _meanDuration(List<AgentRun> runs) {
    if (runs.isEmpty) return 0;
    final total = runs.fold<int>(0, (sum, run) => sum + run.durationMs);
    return (total / runs.length).round();
  }
}

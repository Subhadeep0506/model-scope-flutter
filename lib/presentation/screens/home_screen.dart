import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/byte_size.dart';
import '../../data/models/home_stats.dart';
import '../widgets/activity_row.dart';
import '../widgets/home_actions.dart';
import '../widgets/home_header.dart';
import '../widgets/latency_trend_card.dart';
import '../widgets/model_usage_card.dart';
import '../widgets/section_heading.dart';
import '../widgets/stat_tile.dart';
import '../widgets/throughput_bar_card.dart';

/// The dashboard: what this device has actually run.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final stats = ref.watch(homeStatsProvider);
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            _Block(top: metrics.gapLg, child: const HomeHeader()),
            _Block(
              top: metrics.gapXl,
              child: _heading(context, 'Runtime stats'),
            ),
            _StatGrid(stats: stats),
            _Block(
              top: metrics.gapXl,
              child: _heading(context, 'Latency trend · 7 days'),
            ),
            _Block(
              top: metrics.gapMd,
              child: LatencyTrendCard(trend: stats.latencyTrend),
            ),
            _Block(
              top: metrics.gapXl,
              child: _heading(context, 'Throughput by size'),
            ),
            _Block(
              top: metrics.gapMd,
              child: ThroughputBarCard(bars: stats.throughputBySize),
            ),
            _Block(
              top: metrics.gapXl,
              child: SectionHeading(
                title: 'Models used',
                color: context.palette.ink,
                actionLabel: 'Manage',
                onAction: () => context.go(Routes.settings),
              ),
            ),
            _ModelList(usage: stats.modelUsage, now: now),
            _Block(
              top: metrics.gapXl,
              child: _heading(context, 'Recent activity'),
            ),
            _ActivityList(activity: stats.activity, now: now),
            _Block(
              top: metrics.gapXl,
              bottom: metrics.gapXl,
              child: HomeActions(
                onNewChat: () => _newChat(context, ref),
                onRunAgent: () => context.go(Routes.agent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _heading(BuildContext context, String title) =>
      SectionHeading(title: title, color: context.palette.ink);

  static Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final session = await ref.read(sessionsViewModelProvider.notifier).create();
    router.push(Routes.sessionOf(session.id));
  }
}

/// One page-padded row in the scroll view, as Settings builds its blocks.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        top,
        metrics.pagePadding,
        bottom,
      ),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final HomeStats stats;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final tiles = _tiles(stats);

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        0,
      ),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: metrics.gapMd,
          crossAxisSpacing: metrics.gapMd,
          mainAxisExtent: MediaQuery.textScalerOf(context)
              .scale(metrics.statTile),
        ),
        itemCount: tiles.length,
        itemBuilder: (_, index) => tiles[index],
      ),
    );
  }

  static List<Widget> _tiles(HomeStats stats) => <Widget>[
    StatTile(
      label: 'TOKENS GENERATED',
      value: formatCount(stats.totalTokens),
      // Lifetime, not "across stored sessions": the figures come from the
      // usage ledger now, so deleting a chat no longer lowers them.
      caption: 'on this device, all time',
      accent: true,
    ),
    StatTile(
      label: 'AVG LATENCY',
      value: '${stats.averageLatencyMs}ms',
      caption: 'time to first token',
    ),
    StatTile(
      label: 'PEAK THROUGHPUT',
      value: stats.peakTokensPerSecond.toStringAsFixed(1),
      unit: 'tok/s',
      caption: stats.peakModelName ?? 'no replies yet',
    ),
    StatTile(
      label: 'AGENT RUNS',
      value: '${stats.agentRuns}',
      caption: 'across ${stats.agentCount} agents',
    ),
    StatTile(
      label: 'MODELS',
      value: '${stats.modelCount}',
      caption: '${stats.modelBytesLabel} on disk',
    ),
    StatTile(
      label: 'CHATS TODAY',
      value: '${stats.repliesToday}',
      caption:
          '${stats.sessionCount} '
          '${stats.sessionCount == 1 ? 'session' : 'sessions'} stored',
    ),
  ];
}

class _ModelList extends StatelessWidget {
  const _ModelList({required this.usage, required this.now});

  final List<ModelUsage> usage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    if (usage.isEmpty) {
      return _Block(
        top: metrics.gapMd,
        child: const _Note('No models yet. Add one to start chatting.'),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        0,
      ),
      sliver: SliverList.separated(
        itemCount: usage.length,
        separatorBuilder: (_, _) => SizedBox(height: metrics.gapSm),
        itemBuilder: (_, index) => ModelUsageCard(
          key: ValueKey<String>(usage[index].modelId),
          usage: usage[index],
          now: now,
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.activity, required this.now});

  final List<ActivityEntry> activity;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    if (activity.isEmpty) {
      return _Block(
        top: metrics.gapMd,
        child: const _Note('Nothing has happened on this device yet.'),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        0,
      ),
      sliver: SliverList.separated(
        itemCount: activity.length,
        separatorBuilder: (_, _) => SizedBox(height: metrics.gapSm),
        itemBuilder: (_, index) =>
            ActivityRow(entry: activity[index], now: now),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: context.metrics.gapSm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );
}

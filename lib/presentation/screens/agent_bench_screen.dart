import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../view_models/agent_bench_state.dart';
import '../widgets/agent_bench_header.dart';
import '../widgets/agent_card.dart';
import '../widgets/section_heading.dart';
import '../widgets/stat_tile.dart';

/// The Agent tab: every agent this build can run, and how they have got on.
class AgentBenchScreen extends ConsumerWidget {
  const AgentBenchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bench = ref.watch(agentBenchViewModelProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (bench) {
          AsyncError(:final error) => _Note(text: '$error', centred: true),
          AsyncLoading() when !bench.hasValue => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => _Bench(state: bench.value ?? AgentBenchState.empty),
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.agentNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New agent'),
        backgroundColor: context.palette.primary,
        foregroundColor: context.palette.onPrimary,
      ),
    );
  }
}

class _Bench extends StatelessWidget {
  const _Bench({required this.state});

  final AgentBenchState state;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final now = DateTime.now();

    return CustomScrollView(
      slivers: <Widget>[
        _Block(
          top: metrics.gapLg,
          child: AgentBenchHeader(count: state.agentCount),
        ),
        _Block(
          top: metrics.gapLg,
          child: _StatRow(state: state),
        ),
        _Block(
          top: metrics.gapXl,
          child: SectionHeading(title: 'My agents', color: context.palette.ink),
        ),
        _Block(
          top: metrics.gapMd,
          child: state.custom.isEmpty
              ? const _EmptyCustom()
              : _Cards(listings: state.custom, now: now),
        ),
        _Block(
          top: metrics.gapXl,
          child: SectionHeading(title: 'Built-in', color: context.palette.ink),
        ),
        _Block(
          top: metrics.gapMd,
          // Room for the button floating over the end of the list.
          bottom: metrics.gapXl * 3,
          child: state.builtIn.isEmpty
              ? const _Note(text: 'No agents are bundled with this build.')
              : _Cards(listings: state.builtIn, now: now),
        ),
      ],
    );
  }
}

/// The three figures above the list. A row rather than Home's 2-wide grid:
/// the mockup fits all three across, and they are short enough to.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.state});

  final AgentBenchState state;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(metrics.statTile),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'RUNS',
              value: '${state.runCount}',
              caption: 'recorded',
              accent: true,
            ),
          ),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: StatTile(
              label: 'AVG RUN',
              value: state.averageRunLabel,
              caption: 'per run',
            ),
          ),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: StatTile(
              label: 'TOOLS',
              value: '${state.toolCount}',
              caption: 'registered',
            ),
          ),
        ],
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.listings, required this.now});

  final List<AgentListing> listings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Column(
      children: <Widget>[
        for (final (index, listing) in listings.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: metrics.gapMd),
          AgentCard(
            key: ValueKey<String>(listing.id),
            listing: listing,
            now: now,
            onOpen: () => context.push(Routes.agentOf(listing.id)),
          ),
        ],
      ],
    );
  }
}

/// The dashed placeholder where custom agents will go.
class _EmptyCustom extends StatelessWidget {
  const _EmptyCustom();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return DottedBorderBox(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.gapLg,
          vertical: metrics.gapXl,
        ),
        child: Center(
          child: Text(
            'No custom agents yet — build one from tools',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.muted),
          ),
        ),
      ),
    );
  }
}

/// A hairline dashed rectangle. Written here rather than pulled in as a
/// package: it is wanted in exactly one place, and the drawing is nine lines.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRectPainter(
      color: context.palette.outline,
      radius: context.metrics.radiusCard,
    ),
    child: child,
  );
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    for (final metric in outline.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// One page-padded row in the scroll view, as Home builds its blocks.
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

class _Note extends StatelessWidget {
  const _Note({required this.text, this.centred = false});

  final String text;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: EdgeInsets.all(context.metrics.pagePadding),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    );
    return centred ? Center(child: body) : body;
  }
}

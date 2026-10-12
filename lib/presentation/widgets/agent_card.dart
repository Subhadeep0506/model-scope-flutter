import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/relative_time.dart';
import '../view_models/agent_bench_state.dart';
import 'agent_icon.dart';
import 'icon_tile.dart';
import 'mono_chip.dart';
import 'mono_label.dart';
import 'section_card.dart';

class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.listing,
    required this.now,
    required this.onOpen,
  });

  final AgentListing listing;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final theme = Theme.of(context);
    final template = listing.agent.template;

    return SectionCard(
      onTap: onOpen,
      padding: EdgeInsets.all(metrics.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconTile(icon: agentIconFor(template.icon), size: 40),
              SizedBox(width: metrics.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(template.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(template.purpose, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Icon(Icons.chevron_right_rounded, size: 20, color: palette.muted),
            ],
          ),
          if (template.toolNames.isNotEmpty || listing.agent.isEdited) ...[
            SizedBox(height: metrics.gapMd),
            Wrap(
              spacing: metrics.gapSm,
              runSpacing: metrics.gapSm,
              children: <Widget>[
                for (final tool in template.toolNames) MonoChip(tool),

                if (listing.agent.isEdited)
                  MonoChip('EDITED', color: palette.primary),
              ],
            ),
          ],
          SizedBox(height: metrics.gapMd),
          _Footer(listing: listing, now: now),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.listing, required this.now});

  final AgentListing listing;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final blocker = listing.blocker;

    if (blocker != null) {
      return Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 14, color: palette.warning),
          const SizedBox(width: 6),
          Expanded(
            child: MonoLabel(blocker, color: palette.warning, maxLines: 1),
          ),
        ],
      );
    }

    final run = listing.lastRun;
    if (run == null) return const MonoLabel('never run');

    return MonoLabel(
      'last run ${formatAgo(run.startedAt, now)} · ${run.summary}',
      color: run.succeeded ? null : palette.danger,
      maxLines: 1,
    );
  }
}

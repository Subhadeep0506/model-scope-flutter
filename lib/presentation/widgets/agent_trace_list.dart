import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';
import '../../data/models/agent_run.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// The `TRACE` block: the heading, the total, and one row per step.
///
/// A row says what a step did and how long it took. What was actually sent and
/// returned is the log's job — [onShowLogs] is what reaches it, and is null on
/// a run read back from history, whose logs were never kept.
class AgentTraceList extends StatelessWidget {
  const AgentTraceList({
    super.key,
    required this.entries,
    required this.totalLabel,
    required this.isRunning,
    this.onShowLogs,
  });

  final List<TraceEntry> entries;

  /// `4.20s total`.
  final String totalLabel;

  /// Draws a spinner under the last row while more are still coming.
  final bool isRunning;

  final VoidCallback? onShowLogs;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final showLogs = onShowLogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const MonoLabel('TRACE', variant: MonoStyle.overline),
            const Spacer(),
            MonoLabel(totalLabel, color: palette.primary),
            if (showLogs != null) ...<Widget>[
              SizedBox(width: metrics.gapSm),
              TextButton.icon(
                onPressed: showLogs,
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Show logs'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  padding: EdgeInsets.symmetric(horizontal: metrics.gapSm),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: metrics.gapSm),
        for (final (index, entry) in entries.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: metrics.gapSm),
          _TraceRow(entry: entry),
        ],
        if (isRunning) ...<Widget>[
          SizedBox(height: metrics.gapMd),
          const _Working(),
        ],
        if (entries.isEmpty && !isRunning)
          Padding(
            padding: EdgeInsets.symmetric(vertical: metrics.gapSm),
            child: Text(
              'Nothing was traced.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.muted),
            ),
          ),
      ],
    );
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.entry});

  final TraceEntry entry;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final mark = entry.ok ? palette.primary : palette.danger;

    return Semantics(
      label: '${entry.kind.label} ${entry.label}',
      value: entry.ok ? 'succeeded' : 'failed',
      excludeSemantics: true,
      child: SectionCard(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.gapMd,
          vertical: metrics.gapMd,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: mark.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(metrics.radiusPill),
              ),
              child: Icon(
                entry.ok ? Icons.check_rounded : Icons.close_rounded,
                size: 15,
                color: mark,
              ),
            ),
            SizedBox(width: metrics.gapMd),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: entry.kind.label,
                      style: AppTypography.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _kindColour(entry.kind, palette),
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${entry.label}',
                      style: AppTypography.mono(
                        fontSize: 12,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: metrics.gapSm),
            MonoLabel(entry.durationLabel, maxLines: 1),
          ],
        ),
      ),
    );
  }

  /// The four kinds are coloured apart so a trace can be read down the left
  /// without reading the labels — which is how you spot a run that thought
  /// three times and never called a tool.
  static Color _kindColour(TraceKind kind, AppPalette palette) =>
      switch (kind) {
        TraceKind.thought => palette.warning,
        TraceKind.tool => palette.primary,
        TraceKind.result => palette.muted,
        TraceKind.answer => palette.primary,
      };
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: metrics.gapMd),
        const MonoLabel('working…'),
      ],
    );
  }
}

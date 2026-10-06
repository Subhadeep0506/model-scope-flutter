import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';
import '../../data/models/agent_log.dart';
import 'mono_label.dart';
import 'sheet_scaffold.dart';

/// Everything a run actually sent and received, behind the `Show logs` button.
///
/// The trace says a step called `web_search("sony wh-1000xm5")` and took a
/// second. This says which prompt produced that call, what arguments the model
/// chose, and the whole of what came back — which is what separates "the model
/// ignored the tool" from "the tool returned nothing useful".
///
/// Only reachable while the run that produced the lines is still on screen:
/// logs are not written to the history file. See [AgentLogEntry] for why.
class AgentLogSheet extends StatelessWidget {
  const AgentLogSheet({super.key, required this.entries});

  final List<AgentLogEntry> entries;

  static Future<void> show(BuildContext context, List<AgentLogEntry> entries) =>
      SheetScaffold.show<void>(context, AgentLogSheet(entries: entries));

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SheetScaffold.body(
      title: 'Run log',
      titleAlign: TextAlign.left,
      action: _CopyAll(entries: entries),
      body: entries.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                0,
                metrics.pagePadding,
                metrics.pagePadding,
              ),
              itemCount: entries.length,
              separatorBuilder: (_, _) => SizedBox(height: metrics.gapMd),
              itemBuilder: (_, index) => _LogRow(entry: entries[index]),
            ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AgentLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            MonoLabel(entry.timeLabel),
            SizedBox(width: metrics.gapSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: entry.isError
                    ? palette.danger.withValues(alpha: 0.14)
                    : palette.pill,
                borderRadius: BorderRadius.circular(metrics.radiusPill),
              ),
              child: MonoLabel(
                entry.channel,
                variant: MonoStyle.tag,
                color: entry.isError ? palette.danger : palette.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Selectable so one prompt or one tool result can be lifted out on its
        // own, without copying the whole log.
        SelectableText(
          entry.text,
          style: AppTypography.mono(
            fontSize: 12,
            color: entry.isError ? palette.danger : palette.ink,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _CopyAll extends StatelessWidget {
  const _CopyAll({required this.entries});

  final List<AgentLogEntry> entries;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: entries.isEmpty ? null : () => _copy(context),
    icon: const Icon(Icons.copy_rounded, size: 16),
    label: const Text('Copy all'),
    style: TextButton.styleFrom(
      foregroundColor: context.palette.primary,
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.bodySmall,
    ),
  );

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: <String>[for (final entry in entries) entry.asText].join('\n'),
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Copied ${entries.length} log lines.')),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(context.metrics.pagePadding),
    child: Text(
      'Nothing was logged for this run.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );
}

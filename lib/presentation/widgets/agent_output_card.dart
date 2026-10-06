import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'markdown_text.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// The `>_ OUTPUT` block holding an agent's final text.
///
/// Rendered as markdown like every other model reply in this app — a model
/// asked to rank offers will write a list, and printing the asterisks would
/// be reading the model's formatting back at the user.
class AgentOutputCard extends StatelessWidget {
  const AgentOutputCard({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.isThinking = false,
    this.error,
  });

  final String text;

  /// True while tokens are still arriving, which holds finished blocks still
  /// rather than re-laying them out on every token.
  final bool isStreaming;

  /// True while the model is still inside its reasoning block, which this card
  /// never shows. Says `Thinking…` rather than `Writing…`, so a long pause
  /// before the first word of the answer is accounted for.
  final bool isThinking;

  /// Printed above the text when the run stopped early. The text stays, since
  /// a partial answer is still worth reading.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final theme = Theme.of(context);
    final failure = error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.terminal_rounded, size: 15, color: palette.muted),
            SizedBox(width: metrics.gapSm),
            const MonoLabel('OUTPUT', variant: MonoStyle.overline),
          ],
        ),
        SizedBox(height: metrics.gapSm),
        SectionCard(
          color: palette.selectedTile,
          padding: EdgeInsets.all(metrics.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (failure != null) ...<Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: palette.danger,
                    ),
                    SizedBox(width: metrics.gapSm),
                    Expanded(
                      child: Text(
                        failure,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                if (text.isNotEmpty) SizedBox(height: metrics.gapMd),
              ],
              if (text.isNotEmpty)
                MarkdownText(
                  text: text,
                  style: theme.textTheme.bodyLarge ?? const TextStyle(),
                  isStreaming: isStreaming,
                )
              else if (failure == null)
                Text(
                  switch ((isStreaming, isThinking)) {
                    (_, true) => 'Thinking…',
                    (true, _) => 'Writing…',
                    _ => 'The agent produced no text.',
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

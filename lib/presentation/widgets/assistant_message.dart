import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/generation_metrics.dart';
import '../../domain/services/thinking_parser.dart';
import 'markdown_text.dart';
import 'mono_label.dart';

class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    super.key,
    required this.message,
    required this.onRegenerate,
  });

  final ChatMessage message;

  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final failure = message.error;
    final stats = message.metrics;
    final split = splitThinking(message.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (split.thinking.isNotEmpty) ...<Widget>[
          _ThinkingBlock(
            text: split.thinking,

            isLive: split.isOpen && message.isStreaming,
          ),
          SizedBox(height: metrics.gapSm),
        ],
        if (split.answer.isNotEmpty)
          MarkdownText(
            text: split.answer,
            style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
            isStreaming: message.isStreaming,
          ),

        if (message.isStreaming && split.answer.isEmpty)
          const _StreamingIndicator(),
        if (failure != null) _Failure(message: failure),
        if (stats != null && !message.isStreaming) ...<Widget>[
          SizedBox(height: metrics.gapSm),
          _MetricsRow(
            stats: stats,

            text: split.answer,
            onRegenerate: onRegenerate,
          ),
        ],
      ],
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({required this.text, required this.isLive});

  final String text;
  final bool isLive;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool? _chosen;

  bool get _expanded => _chosen ?? widget.isLive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final label = widget.isLive ? 'Thinking…' : 'Thought process';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: _expanded,
          label: '$label, ${_expanded ? 'hide' : 'show'}',
          child: InkWell(
            onTap: () => setState(() => _chosen = !_expanded),
            borderRadius: metrics.controlShape,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: metrics.gapXs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: palette.muted,
                  ),
                  SizedBox(width: metrics.gapXs),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: palette.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) _ThoughtText(text: widget.text),
      ],
    );
  }
}

class _ThoughtText extends StatelessWidget {
  const _ThoughtText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final body = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return Container(
      margin: EdgeInsets.only(top: metrics.gapXs),
      padding: EdgeInsets.only(left: metrics.gapMd),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.outline)),
      ),
      child: MarkdownText(
        text: text,
        style: body.copyWith(color: palette.muted),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.stats,
    required this.text,
    required this.onRegenerate,
  });

  final GenerationMetrics stats;
  final String text;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(child: MonoLabel(stats.label, maxLines: 1)),
        _MetricAction(
          icon: Icons.copy_rounded,
          tooltip: 'Copy reply',
          onPressed: text.isEmpty ? null : () => _copy(context),
        ),
        _MetricAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Regenerate reply',
          onPressed: onRegenerate,
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(const SnackBar(content: Text('Reply copied')));
  }
}

class _MetricAction extends StatelessWidget {
  const _MetricAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    color: context.palette.muted,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    padding: EdgeInsets.zero,
  );
}

class _StreamingIndicator extends StatelessWidget {
  const _StreamingIndicator();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Generating a reply',
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.palette.primary,
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: palette.danger),
    );
  }
}

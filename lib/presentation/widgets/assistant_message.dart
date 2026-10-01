import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/generation_metrics.dart';
import 'mono_label.dart';

/// A reply: plain body text across the full content width, with the measured
/// metrics and its two actions underneath.
class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    super.key,
    required this.message,
    required this.onRegenerate,
  });

  final ChatMessage message;

  /// `null` while another reply is in flight.
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final failure = message.error;
    final stats = message.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (message.text.isNotEmpty)
          Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
        if (message.isStreaming && message.text.isEmpty) const _Thinking(),
        if (failure != null) _Failure(message: failure),
        if (stats != null && !message.isStreaming) ...<Widget>[
          SizedBox(height: metrics.gapSm),
          _MetricsRow(
            stats: stats,
            text: message.text,
            onRegenerate: onRegenerate,
          ),
        ],
      ],
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
    // A loose [Flexible] keeps the two actions tight against the metrics
    // instead of pushing them to the far edge, as in the mockup.
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

class _Thinking extends StatelessWidget {
  const _Thinking();

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

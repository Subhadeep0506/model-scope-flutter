import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'mono_label.dart';
import 'square_icon_button.dart';

/// Transcript header: back, the session overline and title, and the control
/// that opens the Sampling sheet.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.startedAt,
    required this.onBack,
    required this.onTune,
  });

  static final DateFormat _time = DateFormat('h:mm a');

  final String title;
  final DateTime startedAt;
  final VoidCallback onBack;
  final VoidCallback onTune;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SquareIconButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to chats',
          borderColor: palette.outline,
          onPressed: onBack,
        ),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MonoLabel(
                'SESSION · ${_time.format(startedAt)}',
                variant: MonoStyle.overline,
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        SizedBox(width: metrics.gapMd),
        SquareIconButton(
          icon: Icons.tune_rounded,
          label: 'Sampling settings',
          borderColor: palette.outline,
          onPressed: onTune,
        ),
      ],
    );
  }
}

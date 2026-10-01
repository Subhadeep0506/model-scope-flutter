import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_message.dart';
import 'attachment_chip.dart';

/// A question, drawn as a filled bubble hugging the right edge.
///
/// Replies deliberately have no bubble, which is what gives the transcript its
/// asymmetry in the mockup.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final attachment = message.attachmentName;

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          // Wide messages stop at the measured 68%; short ones still hug.
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * metrics.bubbleMaxWidthFactor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (attachment != null) ...<Widget>[
                AttachmentChip(fileName: attachment),
                SizedBox(height: metrics.gapXs),
              ],
              _Bubble(text: message.text),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapLg,
        vertical: metrics.gapMd,
      ),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: metrics.cardShape,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: palette.onPrimary),
      ),
    );
  }
}

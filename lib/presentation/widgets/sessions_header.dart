import 'package:flutter/material.dart';

import '../../config/theme/app_palette.dart';
import 'mono_label.dart';
import 'square_icon_button.dart';

/// The Chats screen title block: a live session count, the heading, and the
/// filled `+` that starts a new conversation.
class SessionsHeader extends StatelessWidget {
  const SessionsHeader({
    super.key,
    required this.count,
    required this.onCreate,
  });

  final int count;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MonoLabel(
                '$count LOCAL SESSION${count == 1 ? '' : 'S'}',
                variant: MonoStyle.overline,
              ),
              const SizedBox(height: 2),
              Text('Chats', style: Theme.of(context).textTheme.displaySmall),
            ],
          ),
        ),
        SquareIconButton(
          icon: Icons.add_rounded,
          label: 'New chat',
          iconSize: 24,
          background: palette.primary,
          foreground: palette.onPrimary,
          onPressed: onCreate,
        ),
      ],
    );
  }
}

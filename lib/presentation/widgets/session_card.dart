import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/di/providers.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_session.dart';
import 'icon_tile.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One row of the Chats list.
class SessionCard extends ConsumerWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  /// Matches the mockup: `Sep 30, 2026, 12:08 PM`.
  static final DateFormat _stamp = DateFormat('MMM d, y, h:mm a');

  final ChatSession session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    // The model may since have been removed in Settings. The session is still
    // readable, so it lists — it just cannot name what produced it.
    final model = ref.watch(installedModelProvider(session.modelId));

    return SectionCard(
      onTap: onOpen,
      height: metrics.sessionCard,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapLg,
      ),
      child: Row(
        children: <Widget>[
          const IconTile(icon: Icons.chat_bubble_outline_rounded),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: _Summary(
              title: session.title,
              subtitle:
                  '${model?.name ?? 'Removed model'} · '
                  '${session.messageCount} msgs',
              stamp: _stamp.format(session.updatedAt),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: palette.muted),
          SizedBox(width: metrics.gapSm),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: palette.muted,
            tooltip: 'Delete ${session.title}',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.subtitle,
    required this.stamp,
  });

  final String title;
  final String subtitle;
  final String stamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 3),
        MonoLabel(stamp, maxLines: 1),
      ],
    );
  }
}

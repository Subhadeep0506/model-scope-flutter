import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_session.dart';
import '../widgets/session_card.dart';
import '../widgets/session_filter_bar.dart';
import '../widgets/sessions_header.dart';

/// The Chats list.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final sessions = ref.watch(sessionsViewModelProvider);
    final visible = ref.watch(filteredSessionsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                metrics.gapLg,
                metrics.pagePadding,
                metrics.gapLg,
              ),
              child: SessionsHeader(
                count: visible.length,
                onCreate: () => _create(context, ref),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
              child: const SessionFilterBar(),
            ),
            SizedBox(height: metrics.gapLg),
            Expanded(
              child: switch (sessions) {
                AsyncError(:final error) => _Message(text: '$error'),
                AsyncLoading() when !sessions.hasValue => const Center(
                  child: CircularProgressIndicator(),
                ),
                _ => _SessionList(sessions: visible),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final session = await ref.read(sessionsViewModelProvider.notifier).create();
    router.push(Routes.sessionOf(session.id));
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.sessions});

  final List<ChatSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return const _Message(text: 'No sessions match those filters.');
    }

    final metrics = context.metrics;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.gapXl,
      ),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => SizedBox(height: metrics.gapMd),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return SessionCard(
          key: ValueKey<String>(session.id),
          session: session,
          onOpen: () => context.push(Routes.sessionOf(session.id)),
          onDelete: () => _delete(context, ref, session),
        );
      },
    );
  }

  /// Asks before deleting, as removing a model in Settings does. A transcript
  /// is not recoverable, so the decision is made up front rather than left to
  /// a snackbar the user has to catch in time.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ChatSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${session.title}"?'),
        content: Text(
          'This removes ${session.messageCount} '
          '${session.messageCount == 1 ? 'message' : 'messages'} and cannot '
          'be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(sessionsViewModelProvider.notifier).delete(session.id);
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.all(metrics.pagePadding),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    );
  }
}

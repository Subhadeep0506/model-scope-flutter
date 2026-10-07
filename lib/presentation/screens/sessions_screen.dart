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
                onCreate: () => createSession(context, ref),
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
                // `visible` is what the filters left; `stored` is whether
                // there is anything at all. The two empty states read
                // differently, so the list needs both.
                _ => _SessionList(
                  sessions: visible,
                  stored: sessions.value?.length ?? 0,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts a chat and opens it. Shared by the header's `+` and the button on
/// the empty state, so both do exactly the same thing.
Future<void> createSession(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final session = await ref.read(sessionsViewModelProvider.notifier).create();
  router.push(Routes.sessionOf(session.id));
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.sessions, required this.stored});

  final List<ChatSession> sessions;

  /// How many sessions exist before filtering, which is what separates "none
  /// yet" from "none of them match".
  final int stored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return stored == 0
          ? const _NoChatsYet()
          : const _Message(text: 'No sessions match those filters.');
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

/// What a fresh install shows. Nothing is seeded any more, so this is the
/// first thing a new user sees on the Chat tab — and it has to offer the way
/// in, not just report that there is nothing here.
class _NoChatsYet extends ConsumerWidget {
  const _NoChatsYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.all(metrics.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 40,
            color: palette.muted,
          ),
          SizedBox(height: metrics.gapLg),
          Text('No chats yet', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: metrics.gapSm),
          Text(
            'Start one to try a model you have installed.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.muted),
          ),
          SizedBox(height: metrics.gapXl),
          FilledButton.icon(
            onPressed: () => createSession(context, ref),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Start a chat'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: EdgeInsets.symmetric(horizontal: metrics.gapXl),
              shape: RoundedRectangleBorder(borderRadius: metrics.controlShape),
            ),
          ),
        ],
      ),
    );
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

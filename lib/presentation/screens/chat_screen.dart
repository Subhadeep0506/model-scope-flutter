import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/chat_message.dart';
import '../view_models/chat_state.dart';
import '../widgets/assistant_message.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_header.dart';
import '../widgets/loaded_models_sheet.dart';
import '../widgets/model_strip.dart';
import '../widgets/sampling_sheet.dart';
import '../widgets/user_bubble.dart';

/// The transcript: header, model strip, messages, composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(chatViewModelProvider.notifier).open(widget.sessionId),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest tokens in view as they arrive.
  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final state = ref.watch(chatViewModelProvider);
    final temperature = ref.watch(samplerViewModelProvider).value?.temperature;
    final session = state.session;

    ref.listen<ChatState>(chatViewModelProvider, (previous, next) {
      if (next.messages.length != previous?.messages.length ||
          next.isStreaming) {
        _followTail();
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                metrics.gapMd,
                metrics.pagePadding,
                metrics.gapMd,
              ),
              child: ChatHeader(
                title: session?.title ?? 'Chat',
                startedAt: session?.createdAt ?? DateTime.now(),
                onBack: _back,
                onTune: () => SamplingSheet.show(context),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
              child: ModelStrip(
                model: ref.watch(activeModelProvider),
                temperature: temperature ?? 0,
                onTap: () => LoadedModelsSheet.show(context),
              ),
            ),
            if (state.notice case final notice?) _Notice(text: notice),
            SizedBox(height: metrics.gapLg),
            Expanded(
              child: _Body(state: state, controller: _scroll),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ChatComposer(
        enabled: state.canSend,
        isStreaming: state.isStreaming,
        attachmentName: state.attachmentName,
        onSend: ref.read(chatViewModelProvider.notifier).send,
        onStop: ref.read(chatViewModelProvider.notifier).stop,
        onAttach: _attach,
        onRemoveAttachment: () =>
            ref.read(chatViewModelProvider.notifier).attach(null),
      ),
    );
  }

  void _back() {
    ref.read(chatViewModelProvider.notifier).close();
    context.pop();
  }

  Future<void> _attach() async {
    final kind = await AttachSheet.show(context);
    if (kind == null) return;
    final name = await ref.read(attachmentPickerProvider).pick(kind);
    if (name == null) return;
    ref.read(chatViewModelProvider.notifier).attach(name);
  }
}

/// One line about how the model loaded, under the model strip.
///
/// Not an error card: the chat works, the user is simply told that it is not
/// running the way Settings asked — otherwise a slow reply looks like a bug.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapSm,
        metrics.pagePadding,
        0,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: context.palette.warning,
          ),
          SizedBox(width: metrics.gapSm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// The transcript itself, or whatever stands in for it.
class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.controller});

  final ChatState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = state.error;
    if (error != null) {
      return _ModelError(
        message: error,
        onRetry: ref.read(chatViewModelProvider.notifier).reload,
      );
    }
    if (state.status == ChatStatus.noModel) {
      return const _NoModel();
    }
    if (state.status == ChatStatus.preparing) {
      return const _Preparing();
    }
    if (state.messages.isEmpty) {
      return const _EmptyTranscript();
    }
    return _Transcript(messages: state.messages, controller: controller);
  }
}

class _Transcript extends ConsumerWidget {
  const _Transcript({required this.messages, required this.controller});

  final List<ChatMessage> messages;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final canRegenerate = ref.watch(chatViewModelProvider).canRegenerate;
    final notifier = ref.read(chatViewModelProvider.notifier);

    return ListView.separated(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.gapXl,
      ),
      itemCount: messages.length,
      separatorBuilder: (_, _) => SizedBox(height: metrics.gapLg),
      itemBuilder: (context, index) {
        final message = messages[index];
        if (message.isUser) {
          return UserBubble(
            key: ValueKey<String>(message.id),
            message: message,
          );
        }
        return AssistantMessage(
          key: ValueKey<String>(message.id),
          message: message,
          // Only the newest reply can be replaced.
          onRegenerate: canRegenerate && index == messages.length - 1
              ? notifier.regenerate
              : null,
        );
      },
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        SizedBox(height: context.metrics.gapLg),
        Text(
          'Loading the model…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript();

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
        child: Text(
          'Ask the model something to start this session.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: context.palette.muted),
        ),
      ),
    );
  }
}

/// Shown on a first run, before anything has been downloaded.
///
/// Deliberately not an error: there is nothing wrong, the user simply has not
/// picked a model yet, so this points at the place where they can.
class _NoModel extends StatelessWidget {
  const _NoModel();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(metrics.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.download_rounded, color: palette.muted, size: 32),
            SizedBox(height: metrics.gapMd),
            Text(
              'No model installed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: metrics.gapSm),
            Text(
              'Download a GGUF model from Hugging Face to start chatting.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: palette.muted),
            ),
            SizedBox(height: metrics.gapLg),
            OutlinedButton(
              onPressed: () => context.go(Routes.settings),
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of the transcript when the weights could not be loaded, with
/// the paths the loader looked in so the fix is obvious.
class _ModelError extends StatelessWidget {
  const _ModelError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(metrics.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: palette.danger, size: 32),
            SizedBox(height: metrics.gapMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: metrics.gapLg),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

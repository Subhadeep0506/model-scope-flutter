import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../view_models/chat_state.dart';
import 'image_thumbnail.dart';
import 'square_icon_button.dart';

/// The bottom bar: attach, the message field, and send. It owns only its text
/// controller and reports every action upwards, so chat behaviour stays in one
/// place.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.enabled,
    required this.isStreaming,
    required this.attachments,
    required this.canAttach,
    required this.hasVision,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onRemoveAttachment,
  });

  final bool enabled;
  final bool isStreaming;

  /// Images waiting to go out with the next message.
  final List<String> attachments;

  /// Whether another image can be picked — false for a model that cannot read
  /// one, and false again once the cap is reached.
  final bool canAttach;

  /// Whether the loaded model can read images at all. Separates "no room left"
  /// from "this model is blind", which the button says out loud.
  final bool hasVision;

  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
  }

  /// A disabled button announces why it is disabled, since there is no caption
  /// left to carry the explanation.
  String get _attachLabel {
    if (widget.canAttach) return 'Attach an image';
    if (!widget.hasVision) {
      return 'Attach an image — this model cannot read images';
    }
    if (widget.attachments.length >= ChatState.maxImages) {
      return 'Attach an image — limit of ${ChatState.maxImages} reached';
    }
    return 'Attach an image';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final attachments = widget.attachments;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: metrics.sheetShape,
        border: Border(top: BorderSide(color: palette.outline)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        metrics.gapSm,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (attachments.isNotEmpty) ...<Widget>[
              _Attachments(
                paths: attachments,
                onRemove: widget.onRemoveAttachment,
              ),
              SizedBox(height: metrics.gapSm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SquareIconButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: _attachLabel,
                  borderColor: palette.outline,
                  onPressed: widget.canAttach ? widget.onAttach : null,
                ),
                SizedBox(width: metrics.gapMd),
                Expanded(
                  child: _Field(controller: _controller, onSubmitted: _submit),
                ),
                SizedBox(width: metrics.gapMd),
                _SendButton(
                  controller: _controller,
                  enabled: widget.enabled,
                  isStreaming: widget.isStreaming,
                  onSend: _submit,
                  onStop: widget.onStop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSubmitted(),
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Message the model...',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.gapMd,
          vertical: metrics.gapMd,
        ),
      ),
    );
  }
}

/// Send while idle, stop while tokens are arriving.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.controller,
    required this.enabled,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (isStreaming) {
      return SquareIconButton(
        icon: Icons.stop_rounded,
        label: 'Stop generating',
        background: palette.primary,
        foreground: palette.onPrimary,
        onPressed: onStop,
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ready = enabled && value.text.trim().isNotEmpty;
        return SquareIconButton(
          icon: Icons.arrow_upward_rounded,
          label: 'Send message',
          background: ready ? palette.primary : palette.primaryIdle,
          foreground: palette.onPrimary,
          onPressed: ready ? onSend : null,
        );
      },
    );
  }
}

/// The images queued for the next message, at most three, so a plain row is
/// enough — there is never anything to scroll.
class _Attachments extends StatelessWidget {
  const _Attachments({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Wrap(
      spacing: metrics.gapSm,
      runSpacing: metrics.gapSm,
      children: <Widget>[
        for (final path in paths)
          ImageThumbnail(
            key: ValueKey<String>(path),
            path: path,
            onRemove: () => onRemove(path),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'attachment_chip.dart';
import 'square_icon_button.dart';

/// The bottom bar: attach, the message field, and send.
///
/// Dumb by design — it owns only its text controller and reports every action
/// upwards, so all chat behaviour stays in the view model.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.enabled,
    required this.isStreaming,
    required this.attachmentName,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onRemoveAttachment,
  });

  final bool enabled;
  final bool isStreaming;
  final String? attachmentName;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final VoidCallback onRemoveAttachment;

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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final attachment = widget.attachmentName;

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
            if (attachment != null) ...<Widget>[
              AttachmentChip(
                fileName: attachment,
                onRemove: widget.onRemoveAttachment,
              ),
              SizedBox(height: metrics.gapXs),
              const _AttachmentNote(),
              SizedBox(height: metrics.gapSm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SquareIconButton(
                  icon: Icons.attach_file_rounded,
                  label: 'Attach a file',
                  borderColor: palette.outline,
                  onPressed: widget.enabled ? widget.onAttach : null,
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

class _AttachmentNote extends StatelessWidget {
  const _AttachmentNote();

  @override
  Widget build(BuildContext context) => Text(
    'Recorded for reference only — this model is text-only, so the file is '
    'not sent to it.',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

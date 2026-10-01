import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/api_keys.dart';
import 'icon_tile.dart';
import 'section_card.dart';

/// One credential: a labelled, obscured field with a reveal toggle and Verify.
///
/// The value is written to the secure store after a typing pause rather than on
/// every keystroke, so pasting a token is one write and not forty.
class ApiKeyCard extends ConsumerStatefulWidget {
  const ApiKeyCard({super.key, required this.kind});

  final ApiKeyKind kind;

  @override
  ConsumerState<ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends ConsumerState<ApiKeyCard> {
  static const Duration _typingPause = Duration(milliseconds: 500);

  final TextEditingController _field = TextEditingController();
  Timer? _timer;
  bool _obscured = true;
  bool _primed = false;

  @override
  void deactivate() {
    // Flush while `ref` is still usable, so leaving the tab keeps the key.
    _flush();
    super.deactivate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _timer?.cancel();
    _timer = Timer(_typingPause, _flush);
  }

  void _flush() {
    _timer?.cancel();
    unawaited(
      ref
          .read(apiKeysViewModelProvider.notifier)
          .setKey(widget.kind, _field.text),
    );
  }

  /// Saves immediately: verifying what is on screen, not what was last typed.
  Future<void> _verify() async {
    _flush();
    await ref.read(apiKeysViewModelProvider.notifier).verify(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final state = ref.watch(apiKeysViewModelProvider).value;

    if (state != null && !_primed) {
      _primed = true;
      _field.text = state.keyOf(widget.kind);
    }

    final verification =
        state?.verificationOf(widget.kind) ?? const VerifyIdle();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Title(kind: widget.kind),
          SizedBox(height: metrics.gapMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _keyField(context)),
              SizedBox(width: metrics.gapSm),
              _VerifyButton(
                kind: widget.kind,
                state: verification,
                onPressed: _verify,
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          _Caption(kind: widget.kind, state: verification),
        ],
      ),
    );
  }

  Widget _keyField(BuildContext context) {
    final palette = context.palette;

    return TextField(
      controller: _field,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: _onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: widget.kind.hint,
        fillColor: palette.fieldFill,
        suffixIcon: IconButton(
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
            color: palette.muted,
          ),
          tooltip: _obscured ? 'Show key' : 'Hide key',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.kind});

  final ApiKeyKind kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        IconTile(
          icon: Icons.key_outlined,
          size: 24,
          iconSize: 15,
          background: Colors.transparent,
          foreground: palette.primary,
        ),
        SizedBox(width: metrics.gapXs),
        Text(kind.label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _VerifyButton extends StatelessWidget {
  const _VerifyButton({
    required this.kind,
    required this.state,
    required this.onPressed,
  });

  final ApiKeyKind kind;
  final VerifyState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final checking = state is VerifyChecking;

    return Tooltip(
      message: kind.isVerifiable
          ? 'Check this key against ${kind.label}'
          : 'Nothing in this build uses a ${kind.label} key yet',
      child: OutlinedButton(
        // Disabled rather than hidden for the two keys this build only stores:
        // the field still works, there is simply nothing to check it against.
        onPressed: kind.isVerifiable && !checking ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.symmetric(horizontal: context.metrics.gapMd),
        ),
        child: checking
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Verify'),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.kind, required this.state});

  final ApiKeyKind kind;
  final VerifyState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (text, colour) = switch (state) {
      VerifyPassed(:final accountName) => (
        'Verified as $accountName',
        palette.primary,
      ),
      VerifyFailed(:final reason) => (reason, palette.danger),
      _ => (kind.caption, palette.muted),
    };

    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colour),
    );
  }
}

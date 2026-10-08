import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';
import '../../domain/services/structured_summary.dart';
import 'markdown_text.dart';
import 'mono_label.dart';
import 'section_card.dart';
import 'structured/structured_view.dart';

/// The `>_ OUTPUT` block holding an agent's final answer.
///
/// Draws one of three things. An agent with no schema gets markdown, as every
/// agent did before structured answers existed. An agent with a schema gets
/// the component its `view` names, drawn from the JSON. And a structured
/// answer that will not parse falls back to markdown too — a run that failed
/// to produce the shape is exactly the run whose raw text is worth reading.
class AgentOutputCard extends StatefulWidget {
  const AgentOutputCard({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.isThinking = false,
    this.error,
    this.isStructured = false,
    this.view,
  });

  final String text;

  /// True while tokens are still arriving, which holds finished blocks still
  /// rather than re-laying them out on every token.
  final bool isStreaming;

  /// True while the model is still inside its reasoning block, which this card
  /// never shows. Says `Thinking…` rather than `Writing…`, so a long pause
  /// before the first word of the answer is accounted for.
  final bool isThinking;

  /// Printed above the text when the run stopped early. The text stays, since
  /// a partial answer is still worth reading.
  final String? error;

  /// Whether this agent's answer step was constrained to a schema.
  final bool isStructured;

  /// Which component draws it. An unknown name falls back to a plain table.
  final String? view;

  @override
  State<AgentOutputCard> createState() => _AgentOutputCardState();
}

class _AgentOutputCardState extends State<AgentOutputCard> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final failure = widget.error;

    // Parsed up front, because whether this is structured in practice — not
    // just in the template — decides both the header and the body.
    final data = widget.isStructured ? decodeStructured(widget.text) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.terminal_rounded, size: 15, color: palette.muted),
            SizedBox(width: metrics.gapSm),
            const MonoLabel('OUTPUT', variant: MonoStyle.overline),
            if (data != null) ...<Widget>[
              const Spacer(),
              _RawToggle(
                showingRaw: _showRaw,
                onChanged: (value) => setState(() => _showRaw = value),
              ),
            ],
          ],
        ),
        SizedBox(height: metrics.gapSm),
        SectionCard(
          color: palette.selectedTile,
          padding: EdgeInsets.all(metrics.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (failure != null) ...<Widget>[
                _Failure(text: failure),
                if (widget.text.isNotEmpty) SizedBox(height: metrics.gapMd),
              ],
              _body(context, data),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic>? data) {
    final theme = Theme.of(context);

    if (data != null) {
      return _showRaw
          ? _RawJson(text: widget.text)
          : viewFor(widget.view).build(context, data);
    }

    // A structured answer still arriving is half-written JSON, which tells
    // the user nothing and cannot be drawn as a table. The spinner is the
    // honest thing to show until it parses.
    if (widget.isStructured && widget.isStreaming) {
      return const _Building();
    }

    if (widget.text.isNotEmpty) {
      return MarkdownText(
        text: widget.text,
        style: theme.textTheme.bodyLarge ?? const TextStyle(),
        isStreaming: widget.isStreaming,
      );
    }

    if (widget.error != null) return const SizedBox.shrink();

    return Text(
      switch ((widget.isStreaming, widget.isThinking)) {
        (_, true) => 'Thinking…',
        (true, _) => 'Writing…',
        _ => 'The agent produced no text.',
      },
      style: theme.textTheme.bodyMedium?.copyWith(color: context.palette.muted),
    );
  }
}

/// Swaps the drawn component for the JSON behind it.
///
/// This app is here to watch models succeed and fail. A table that quietly
/// dropped a field the model got wrong would hide the very thing being
/// measured, so what the model actually returned is always one tap away.
class _RawToggle extends StatelessWidget {
  const _RawToggle({required this.showingRaw, required this.onChanged});

  final bool showingRaw;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      toggled: showingRaw,
      child: Tooltip(
        message: showingRaw ? 'Show the result' : 'Show the raw JSON',
        // Its own Material, so the card can be dropped anywhere — the ink
        // splash should not depend on what happens to be above it.
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!showingRaw),
            borderRadius: context.metrics.controlShape,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.metrics.gapSm,
                vertical: 4,
              ),
              child: MonoLabel(
                '{ }',
                variant: MonoStyle.overline,
                color: showingRaw ? palette.primary : palette.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RawJson extends StatelessWidget {
  const _RawJson({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      SelectableText(_pretty(text), style: context.mono.meta);

  /// Re-encoded with indentation: a constrained model emits valid JSON but
  /// not readable JSON, and this is the view someone opens to read it.
  static String _pretty(String raw) {
    final data = decodeStructured(raw);
    if (data == null) return raw;
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

class _Building extends StatelessWidget {
  const _Building();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: <Widget>[
        SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.muted,
          ),
        ),
        SizedBox(width: context.metrics.gapMd),
        Text(
          'Building the result…',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.muted),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.error_outline_rounded, size: 16, color: palette.danger),
        SizedBox(width: context.metrics.gapSm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.danger),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';

/// Markdown, drawn in the app's own type and colour.
///
/// Models answer in markdown, so every message body goes through here rather
/// than through a plain [Text]. One widget for all three places a message is
/// drawn — the reply, the reasoning behind it and the question — so the
/// mapping onto the design tokens is written once.
///
/// Links are styled but deliberately inert: this app runs offline, and nothing
/// a local model writes should be able to navigate away from it.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.text,
    required this.style,
    this.isStreaming = false,
    this.onFilled = false,
  });

  final String text;

  /// Base style for body copy. Headings, code and the rest are derived from it.
  final TextStyle style;

  /// True while tokens are still arriving, which lets the renderer hold
  /// finished blocks still instead of re-laying them out on every token.
  final bool isStreaming;

  /// True on a filled background — the user's own bubble. [AppPalette.pill]
  /// and [AppPalette.outline] both vanish against [AppPalette.primary], so the
  /// code and quote surfaces switch to a wash of the text colour instead.
  final bool onFilled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    final ink = style.color ?? palette.ink;
    final surface = onFilled ? ink.withValues(alpha: 0.14) : palette.pill;
    final rule = onFilled ? ink.withValues(alpha: 0.35) : palette.outline;
    final accent = onFilled ? ink : palette.primary;
    final mono = AppTypography.mono();

    return GptMarkdown(
      text,
      style: style,
      // Settled blocks stay put while the tail grows. No reveal animation:
      // the app reports tokens per second, so text has to appear when the
      // token actually arrived, not at some smooth synthetic rate.
      isStreaming: isStreaming,
      styleSheet: GptMarkdownStyleSheet(
        heading: HeadingStyle(
          // The app's TextTheme leaves the headline slots unset, so without
          // this a heading would fall back to the platform face mid-reply.
          textStyle: AppTypography.sans(
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        inlineCode: InlineCodeStyle(
          fontFamily: mono.fontFamily,
          color: ink,
          backgroundColor: surface,
          borderColor: rule,
          borderRadius: Radius.circular(metrics.radiusPill),
        ),
        codeBlock: CodeBlockStyle(
          fontFamily: mono.fontFamily,
          textColor: ink,
          backgroundColor: surface,
          borderColor: rule,
          borderRadius: Radius.circular(metrics.radiusCard),
          padding: EdgeInsets.all(metrics.gapMd),
          languageStyle: context.mono.tag,
          showLanguageLabel: true,
          showCopyButton: true,
        ),
        blockQuote: BlockQuoteStyle(
          barColor: rule,
          textStyle: style.copyWith(color: ink.withValues(alpha: 0.85)),
        ),
        table: TableStyle(
          borderColor: rule,
          cellPadding: EdgeInsets.symmetric(
            horizontal: metrics.gapSm,
            vertical: metrics.gapXs,
          ),
          headerTextStyle: style.copyWith(fontWeight: FontWeight.w600),
        ),
        list: ListStyle(bulletColor: accent),
        hr: HrStyle(color: rule),
        link: LinkStyle(color: accent),
      ),
    );
  }
}

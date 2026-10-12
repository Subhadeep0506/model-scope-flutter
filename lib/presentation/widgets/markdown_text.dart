import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';

class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.text,
    required this.style,
    this.isStreaming = false,
    this.onFilled = false,
  });

  final String text;

  final TextStyle style;

  final bool isStreaming;

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

      isStreaming: isStreaming,
      styleSheet: GptMarkdownStyleSheet(
        heading: HeadingStyle(
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

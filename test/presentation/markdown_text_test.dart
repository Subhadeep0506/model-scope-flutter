import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/presentation/widgets/markdown_text.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// Pumps [text] as a reply would be drawn, on a surface tall enough that
  /// nothing is skipped for being off-screen.
  Future<void> pumpMarkdown(
    WidgetTester tester,
    String text, {
    bool isStreaming = false,
    bool onFilled = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        Scaffold(
          body: SingleChildScrollView(
            child: MarkdownText(
              text: text,
              style: const TextStyle(fontSize: 15),
              isStreaming: isStreaming,
              onFilled: onFilled,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Markdown renders formatted runs as rich text, so an assertion on a styled
  /// word has to be told to look inside it.
  Finder rich(String text) => find.textContaining(text, findRichText: true);

  group('formatting', () {
    testWidgets('renders a heading, bold, a list and a quote', (tester) async {
      await pumpMarkdown(tester, '''
## Quantisation

Q8_0 keeps **eight bits** per weight.

- smaller file
- faster load

> Rule of thumb: half the bits, half the size.
''');

      check(tester.takeException()).isNull();
      check(rich('Quantisation').evaluate()).isNotEmpty();
      check(rich('eight bits').evaluate()).isNotEmpty();
      check(rich('smaller file').evaluate()).isNotEmpty();
      check(rich('half the bits').evaluate()).isNotEmpty();
    });

    testWidgets('renders a fenced code block with its language', (
      tester,
    ) async {
      await pumpMarkdown(tester, '''
Here is the call:

```dart
void main() => print('hi');
```
''');

      check(tester.takeException()).isNull();
      check(rich("print('hi')").evaluate()).isNotEmpty();
      // The language label is what tells you which highlighter ran.
      check(rich('dart').evaluate()).isNotEmpty();
    });

    testWidgets('renders a table', (tester) async {
      await pumpMarkdown(tester, '''
| Quant | Size |
| --- | --- |
| Q8_0 | 399 MB |
| Q4_K_M | 271 MB |
''');

      check(tester.takeException()).isNull();
      check(rich('Q4_K_M').evaluate()).isNotEmpty();
      check(rich('271 MB').evaluate()).isNotEmpty();
    });
  });

  group('what a small model actually emits', () {
    // A 270M model produces broken markdown constantly. A renderer that threw
    // on it would take the whole transcript down with it, so each of these
    // asserts only that the text survives and nothing is raised.
    testWidgets('survives an unclosed code fence', (tester) async {
      await pumpMarkdown(tester, 'Try this:\n\n```dart\nvoid main() {');

      check(tester.takeException()).isNull();
      check(rich('void main()').evaluate()).isNotEmpty();
    });

    testWidgets('survives a stray asterisk and a lone hash', (tester) async {
      await pumpMarkdown(tester, '2 * 3 = 6, and **this never closes\n\n#');

      check(tester.takeException()).isNull();
      check(rich('2 * 3 = 6').evaluate()).isNotEmpty();
    });

    testWidgets('survives empty and whitespace-only text', (tester) async {
      await pumpMarkdown(tester, '');
      check(tester.takeException()).isNull();

      await pumpMarkdown(tester, '   \n\n  ');
      check(tester.takeException()).isNull();
    });

    testWidgets('leaves dollar amounts alone', (tester) async {
      // Maths is read from \( \) only, so prose about money stays prose.
      await pumpMarkdown(tester, r'It costs $5 to $10 per month.');

      check(tester.takeException()).isNull();
      check(rich(r'$5').evaluate()).isNotEmpty();
      check(rich(r'$10').evaluate()).isNotEmpty();
    });

    testWidgets('renders bracketed LaTeX as maths', (tester) async {
      await pumpMarkdown(tester, r'Pythagoras: \(x^2 + y^2 = z^2\)');

      // The delimiters are consumed rather than printed, which is the whole
      // difference between rendering the maths and showing the source. The
      // surrounding prose is asserted too, so this cannot pass by rendering
      // nothing at all.
      check(tester.takeException()).isNull();
      check(rich('Pythagoras').evaluate()).isNotEmpty();
      check(rich(r'\(').evaluate()).isEmpty();
    });

    testWidgets('keeps a snake_case identifier intact', (tester) async {
      await pumpMarkdown(tester, 'Set max_new_tokens before running.');

      check(tester.takeException()).isNull();
      check(rich('max_new_tokens').evaluate()).isNotEmpty();
    });
  });

  group('variants', () {
    testWidgets('a half-written reply renders while streaming', (tester) async {
      await pumpMarkdown(tester, '## Quantis', isStreaming: true);

      check(tester.takeException()).isNull();
      check(rich('Quantis').evaluate()).isNotEmpty();
    });

    testWidgets('the reasoning variant is upright, not italic', (tester) async {
      // Italic fought with markdown's own emphasis, so it was dropped; this
      // pins that down rather than leaving it to drift back.
      await pumpMarkdown(tester, 'Working through it.');

      final styles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.style?.fontStyle)
          .toList();
      // Asserted non-empty first: "no italic among no text" would otherwise
      // pass for the wrong reason.
      check(styles).isNotEmpty();
      check(styles).not((it) => it.contains(FontStyle.italic));
    });

    testWidgets('the filled variant renders on a bubble', (tester) async {
      await pumpMarkdown(tester, 'Summarise **this** for me.', onFilled: true);

      check(tester.takeException()).isNull();
      check(rich('Summarise').evaluate()).isNotEmpty();
    });
  });
}

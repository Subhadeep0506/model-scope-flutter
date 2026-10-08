import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/presentation/widgets/agent_output_card.dart';
import 'package:model_scope_flutter/presentation/widgets/markdown_text.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  Future<void> pumpCard(
    WidgetTester tester, {
    required String text,
    bool isStructured = false,
    String? view,
    bool isStreaming = false,
    String? error,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: AgentOutputCard(
            text: text,
            isStructured: isStructured,
            view: view,
            isStreaming: isStreaming,
            error: error,
          ),
        ),
      ),
    );
    // A spinner never settles, so a streaming card is pumped once instead of
    // waited on.
    if (isStreaming) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  const String priceJson = '''
    {"product": "Sony WH-1000XM5",
     "currency": "₹",
     "offers": [{"retailer": "Retailer C", "price": 25750,
                 "shipping": "Free", "stock": "In stock"}],
     "cheapest_retailer": "Retailer C"}
  ''';

  testWidgets('an agent with no schema still gets markdown', (tester) async {
    await pumpCard(tester, text: '**Retailer C** is cheapest.');

    check(find.byType(MarkdownText).evaluate()).isNotEmpty();
    check(find.text('{ }').evaluate()).isEmpty();
  });

  testWidgets('a structured answer draws its component', (tester) async {
    await pumpCard(
      tester,
      text: priceJson,
      isStructured: true,
      view: 'price_table',
    );

    check(find.text('Retailer C').evaluate()).isNotEmpty();
    check(find.text('₹ 25,750').evaluate()).isNotEmpty();
    check(find.byType(MarkdownText).evaluate()).isEmpty();
  });

  testWidgets('the brace toggle swaps in the raw JSON', (tester) async {
    await pumpCard(
      tester,
      text: priceJson,
      isStructured: true,
      view: 'price_table',
    );

    await tester.tap(find.text('{ }'));
    await tester.pumpAndSettle();

    // What the model actually returned, re-indented to be readable. A table
    // that quietly dropped a field it got wrong would hide the measurement.
    check(find.textContaining('"cheapest_retailer"').evaluate()).isNotEmpty();
    check(find.text('Retailer C').evaluate()).isEmpty();

    await tester.tap(find.text('{ }'));
    await tester.pumpAndSettle();
    check(find.text('Retailer C').evaluate()).isNotEmpty();
  });

  testWidgets('output that will not parse falls back to markdown', (
    tester,
  ) async {
    // A model that refused the shape, or a schema the backend would not take.
    await pumpCard(
      tester,
      text: 'Retailer C is cheapest at 25,750.',
      isStructured: true,
      view: 'price_table',
    );

    check(find.byType(MarkdownText).evaluate()).isNotEmpty();
    check(find.textContaining('Retailer C is cheapest').evaluate())
        .isNotEmpty();
    // Nothing to show raw, so no toggle.
    check(find.text('{ }').evaluate()).isEmpty();
  });

  testWidgets('a structured answer still arriving shows a spinner', (
    tester,
  ) async {
    await pumpCard(
      tester,
      text: '{"offers": [{"retail',
      isStructured: true,
      view: 'price_table',
      isStreaming: true,
    );

    // Half-written JSON tells the user nothing and cannot be drawn.
    check(find.textContaining('Building the result').evaluate()).isNotEmpty();
    check(find.byType(CircularProgressIndicator).evaluate()).isNotEmpty();
  });

  testWidgets('a prose answer still streams as it arrives', (tester) async {
    await pumpCard(tester, text: 'Retailer C', isStreaming: true);

    check(find.textContaining('Building the result').evaluate()).isEmpty();
    check(find.byType(MarkdownText).evaluate()).isNotEmpty();
  });

  testWidgets('an unknown view falls back to a table, not raw JSON', (
    tester,
  ) async {
    await pumpCard(
      tester,
      text: '{"rows": [{"name": "Alpha"}]}',
      isStructured: true,
      view: 'a_view_from_a_later_build',
    );

    check(find.text('Alpha').evaluate()).isNotEmpty();
    check(find.text('NAME').evaluate()).isNotEmpty();
  });

  testWidgets('a failed run shows the error above what it managed', (
    tester,
  ) async {
    await pumpCard(
      tester,
      text: priceJson,
      isStructured: true,
      view: 'price_table',
      error: 'Stopped before it finished.',
    );

    check(find.text('Stopped before it finished.').evaluate()).isNotEmpty();
    // The partial result is still worth reading.
    check(find.text('Retailer C').evaluate()).isNotEmpty();
  });

  testWidgets('an empty answer says so rather than drawing nothing', (
    tester,
  ) async {
    await pumpCard(tester, text: '');

    check(find.text('The agent produced no text.').evaluate()).isNotEmpty();
  });

  testWidgets('lays out without overflow at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const SingleChildScrollView(
            child: AgentOutputCard(
              text: priceJson,
              isStructured: true,
              view: 'price_table',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    check(tester.takeException()).isNull();
  });
}

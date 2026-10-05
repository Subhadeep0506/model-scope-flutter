import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/presentation/widgets/loaded_models_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/sampling_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/sheet_scaffold.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// Pumps a button that opens [open], then taps it.
  Future<void> openSheet(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open, {
    FakeSettingsRepository? settings,
    FakeModelLibraryRepository? library,
  }) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(<ChatSession>[sessionWith()]),
          settings: settings,
          library: library,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('LoadedModelsSheet', () {
    testWidgets('lists the installed model as selected', (tester) async {
      await openSheet(tester, (context) => LoadedModelsSheet.show(context));

      check(find.text('Installed models').evaluate()).isNotEmpty();
      check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
      check(find.text('Q8_0 · 399 MB').evaluate()).isNotEmpty();
      check(find.byIcon(Icons.check_rounded).evaluate()).isNotEmpty();
    });

    testWidgets('marks a model whose repository has a projector', (
      tester,
    ) async {
      await openSheet(
        tester,
        (context) => LoadedModelsSheet.show(context),
        library: FakeModelLibraryRepository.of(
          <ModelDescriptor>[fakeInstalledModel()],
          projectors: <ProjectorDescriptor>[fakeProjector()],
        ),
      );

      check(find.text('Q8_0 · 399 MB · Vision').evaluate()).isNotEmpty();
    });

    testWidgets('leaves a text-only model unmarked', (tester) async {
      await openSheet(tester, (context) => LoadedModelsSheet.show(context));

      check(find.text('Q8_0 · 399 MB').evaluate()).isNotEmpty();
      check(find.textContaining('Vision').evaluate()).isEmpty();
    });

    testWidgets('offers Settings when nothing is installed', (tester) async {
      await openSheet(
        tester,
        (context) => LoadedModelsSheet.show(context),
        library: FakeModelLibraryRepository(),
      );

      check(find.text('No models installed yet.').evaluate()).isNotEmpty();
      check(find.text('Open settings').evaluate()).isNotEmpty();
    });

    testWidgets('closes from the header square', (tester) async {
      await openSheet(tester, (context) => LoadedModelsSheet.show(context));

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      check(find.text('Installed models').evaluate()).isEmpty();
    });
  });

  group('SamplingSheet', () {
    testWidgets('shows the stored values in mono', (tester) async {
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: FakeSettingsRepository(
          const SamplerSettings(
            temperature: 1.20,
            topP: 0.55,
            topK: 12,
            maxTokens: 256,
          ),
        ),
      );

      check(find.text('TEMPERATURE').evaluate()).isNotEmpty();
      check(find.text('1.20').evaluate()).isNotEmpty();
      check(find.text('0.55').evaluate()).isNotEmpty();
      check(find.text('12').evaluate()).isNotEmpty();
      check(find.text('256').evaluate()).isNotEmpty();
    });

    testWidgets('dragging a slider saves once, on release', (tester) async {
      final settings = FakeSettingsRepository();
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );
      final before = settings.saveCalls;

      // Drag the temperature thumb to the right.
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pumpAndSettle();

      // One write for the whole gesture, not one per frame.
      check(settings.saveCalls - before).equals(1);
      check(settings.stored.temperature)
          .isGreaterThan(SamplerSettings.defaultTemperature);
    });

    testWidgets('reset puts every knob back to its default', (tester) async {
      final settings = FakeSettingsRepository(
        const SamplerSettings(temperature: 1.9, topK: 7, maxTokens: 64),
      );
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );

      // Five sliders and the prompt field put the button below the fold
      // of the capped sheet, so it has to be scrolled to before it can be hit.
      await tester.ensureVisible(find.text('Reset to defaults'));
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();

      check(settings.stored).equals(const SamplerSettings());
      check(find.text('0.70').evaluate()).isNotEmpty();
    });

    testWidgets('the edited system prompt is flushed when the sheet closes', (
      tester,
    ) async {
      final settings = FakeSettingsRepository();
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );

      // Type, then dismiss before the debounce would have fired.
      await tester.enterText(find.byType(TextField), 'Answer in one sentence.');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      check(settings.stored.systemPrompt).equals('Answer in one sentence.');
    });

    testWidgets('lays out without overflow at 200% text scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: SamplingSheet()),
          ),
          overrides: fakeOverrides(
            llm: FakeLlmService(),
            sessions: FakeSessionRepository(<ChatSession>[sessionWith()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      check(tester.takeException()).isNull();
    });
  });

  group('sheet height', () {
    testWidgets('a tall sheet stops short of the top of the window', (
      tester,
    ) async {
      // A phone-shaped window, where the status bar is the thing a
      // full-height sheet runs under.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // Sampling is the tallest of the sheets with a scrolling body.
      await openSheet(tester, (context) => SamplingSheet.show(context));

      // The title row has to clear the system bars, so the sheet is
      // capped rather than grown to its content.
      final height = tester.getSize(find.byType(SheetScaffold)).height;
      final window =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      check(height).isLessOrEqual(window * 0.85);
      check(find.text('Sampling').evaluate()).isNotEmpty();
    });

    testWidgets('a short sheet is left at its own height', (tester) async {
      // Loaded models with nothing installed is a line and a button.
      await openSheet(
        tester,
        (context) => LoadedModelsSheet.show(context),
        library: FakeModelLibraryRepository(),
      );

      // The cap bounds a sheet, it does not stretch one.
      final height = tester.getSize(find.byType(SheetScaffold)).height;
      check(height).isLessThan(tester.view.physicalSize.height / 2);
    });
  });
}

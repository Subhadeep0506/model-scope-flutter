import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/domain/services/attachment_picker.dart';
import 'package:model_scope_flutter/presentation/widgets/attach_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/loaded_models_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/sampling_sheet.dart';

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
      // Arrange / Act
      await openSheet(tester, (context) => LoadedModelsSheet.show(context));

      // Assert
      check(find.text('Installed models').evaluate()).isNotEmpty();
      check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
      check(find.text('Q8_0 · 399 MB').evaluate()).isNotEmpty();
      check(find.byIcon(Icons.check_rounded).evaluate()).isNotEmpty();
    });

    testWidgets('offers Settings when nothing is installed', (tester) async {
      // Arrange / Act
      await openSheet(
        tester,
        (context) => LoadedModelsSheet.show(context),
        library: FakeModelLibraryRepository(),
      );

      // Assert
      check(find.text('No models installed yet.').evaluate()).isNotEmpty();
      check(find.text('Open settings').evaluate()).isNotEmpty();
    });

    testWidgets('closes from the header square', (tester) async {
      // Arrange
      await openSheet(tester, (context) => LoadedModelsSheet.show(context));

      // Act
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      // Assert
      check(find.text('Installed models').evaluate()).isEmpty();
    });
  });

  group('AttachSheet', () {
    testWidgets('returns the branch that was tapped', (tester) async {
      // Arrange
      AttachmentKind? chosen;
      await openSheet(tester, (context) async {
        chosen = await AttachSheet.show(context);
      });

      // Act
      await tester.tap(find.bySemanticsLabel(RegExp('^Attach Image')));
      await tester.pumpAndSettle();

      // Assert
      check(chosen).equals(AttachmentKind.image);
    });

    testWidgets('returns null when dismissed', (tester) async {
      // Arrange
      AttachmentKind? chosen = AttachmentKind.pdf;
      await openSheet(tester, (context) async {
        chosen = await AttachSheet.show(context);
      });

      // Act
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      // Assert
      check(chosen).isNull();
    });
  });

  group('SamplingSheet', () {
    testWidgets('shows the stored values in mono', (tester) async {
      // Arrange / Act
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

      // Assert
      check(find.text('TEMPERATURE').evaluate()).isNotEmpty();
      check(find.text('1.20').evaluate()).isNotEmpty();
      check(find.text('0.55').evaluate()).isNotEmpty();
      check(find.text('12').evaluate()).isNotEmpty();
      check(find.text('256').evaluate()).isNotEmpty();
    });

    testWidgets('dragging a slider saves once, on release', (tester) async {
      // Arrange
      final settings = FakeSettingsRepository();
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );
      final before = settings.saveCalls;

      // Act — drag the temperature thumb to the right.
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pumpAndSettle();

      // Assert — one write for the whole gesture, not one per frame.
      check(settings.saveCalls - before).equals(1);
      check(settings.stored.temperature)
          .isGreaterThan(SamplerSettings.defaultTemperature);
    });

    testWidgets('reset puts every knob back to its default', (tester) async {
      // Arrange
      final settings = FakeSettingsRepository(
        const SamplerSettings(temperature: 1.9, topK: 7, maxTokens: 64),
      );
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );

      // Act
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();

      // Assert
      check(settings.stored).equals(const SamplerSettings());
      check(find.text('0.70').evaluate()).isNotEmpty();
    });

    testWidgets('the edited system prompt is flushed when the sheet closes', (
      tester,
    ) async {
      // Arrange
      final settings = FakeSettingsRepository();
      await openSheet(
        tester,
        (context) => SamplingSheet.show(context),
        settings: settings,
      );

      // Act — type, then dismiss before the debounce would have fired.
      await tester.enterText(find.byType(TextField), 'Answer in one sentence.');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      // Assert
      check(settings.stored.systemPrompt).equals('Answer in one sentence.');
    });

    testWidgets('lays out without overflow at 200% text scale', (tester) async {
      // Arrange
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // Act
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

      // Assert
      check(tester.takeException()).isNull();
    });
  });
}

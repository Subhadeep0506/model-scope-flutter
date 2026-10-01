import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/presentation/screens/settings_screen.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeModelLibraryRepository library;
  late FakeAppSettingsRepository appSettings;

  /// A second installed model, named apart from [fakeInstalledModel] so the two
  /// trash buttons have distinct semantics labels.
  ModelDescriptor secondModel() => fakeInstalledModel(
    fileName: 'smollm2-360m-instruct-q4_k_m.gguf',
    name: 'SmolLM2 360M Q4',
    quantization: 'Q4_K_M',
    sizeBytes: 601 * 1000 * 1000,
  );

  /// Pumps Settings on a tall surface.
  ///
  /// The screen is seven sections deep; on the default 600-pixel test window
  /// the lower ones would never be laid out and every assertion about them
  /// would pass or fail for the wrong reason.
  Future<void> pumpSettings(
    WidgetTester tester, {
    List<ModelDescriptor>? models,
    ThemeMode themeMode = ThemeMode.system,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    library = FakeModelLibraryRepository.of(
      models ?? <ModelDescriptor>[fakeInstalledModel()],
    );
    appSettings = FakeAppSettingsRepository(AppSettings(themeMode: themeMode));

    await tester.pumpWidget(
      harness(
        const SettingsScreen(),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          library: library,
          appSettings: appSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The `Semantics` wrapping one appearance tile, read as a widget rather than
  /// as a node so the assertion does not depend on how the tree merges.
  Semantics appearanceTile(WidgetTester tester, String label) => tester
      .widgetList<Semantics>(find.byType(Semantics))
      .firstWhere((s) => s.properties.label == '$label appearance');

  testWidgets('every section of the design is on the screen', (tester) async {
    // Arrange / Act
    await pumpSettings(tester);

    // Assert — the seven headings, in the order the mockups put them.
    for (final text in <String>[
      'Settings',
      'API keys',
      'Models · 399 MB',
      'Appearance',
      'Runtime defaults',
      'Storage',
      'About',
    ]) {
      check(find.text(text).evaluate(), because: text).isNotEmpty();
    }

    // And one card per credential, including the two this build only stores.
    for (final kind in ApiKeyKind.values) {
      check(find.text(kind.label).evaluate(), because: kind.label).isNotEmpty();
    }
  });

  testWidgets('the models heading adds the whole library up', (tester) async {
    // Arrange / Act — 399 MB + 601 MB, the only place the total is shown.
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    // Assert
    check(find.text('Models · 1.00 GB').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Q4').evaluate()).isNotEmpty();
  });

  testWidgets('an empty library drops the size and invites a download', (
    tester,
  ) async {
    // Arrange / Act
    await pumpSettings(tester, models: <ModelDescriptor>[]);

    // Assert — `Models · 0 B` would read as a fault rather than a fresh start.
    check(find.text('Models').evaluate()).isNotEmpty();
    check(find.text('No models yet. Add one to start chatting.').evaluate())
        .isNotEmpty();
    check(find.text('Add model').evaluate()).isNotEmpty();
  });

  testWidgets('removing a model asks first, then drops the row', (
    tester,
  ) async {
    // Arrange
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    // Act
    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Q4'));
    await tester.pumpAndSettle();
    check(find.text('Remove SmolLM2 360M Q4?').evaluate()).isNotEmpty();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pump();
    // Removal looks for the weights on disk, and real file I/O does not
    // complete inside `pump`'s fake-async zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    // Assert — the row goes, and so does its share of the heading.
    check(find.text('SmolLM2 360M Q4').evaluate()).isEmpty();
    check(find.text('Models · 399 MB').evaluate()).isNotEmpty();
    check(library.stored.models.single.id).equals(fakeInstalledModel().id);
  });

  testWidgets('cancelling the confirmation keeps the weights', (tester) async {
    // Arrange — re-downloading gigabytes is the cost of getting this wrong.
    await pumpSettings(tester);

    // Act
    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Assert
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(library.saveCalls).equals(0);
  });

  testWidgets('the appearance selector marks the stored mode', (tester) async {
    // Arrange / Act
    await pumpSettings(tester, themeMode: ThemeMode.light);

    // Assert — selection is announced, not just drawn, so the choice is
    // readable with the screen reader on.
    check(appearanceTile(tester, 'Light').properties.selected).equals(true);
    check(appearanceTile(tester, 'Dark').properties.selected).equals(false);
    check(appearanceTile(tester, 'System').properties.selected).equals(false);
  });

  testWidgets('choosing an appearance persists it', (tester) async {
    // Arrange
    await pumpSettings(tester, themeMode: ThemeMode.light);

    // Act
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Assert
    check(appSettings.stored.themeMode).equals(ThemeMode.dark);
    check(appearanceTile(tester, 'Dark').properties.selected).equals(true);
  });

  testWidgets('tapping a row switches the model Chat answers with', (
    tester,
  ) async {
    // Arrange
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    // Act
    await tester.tap(find.text('SmolLM2 360M Q4'));
    await tester.pumpAndSettle();

    // Assert
    check(library.stored.activeId).equals(secondModel().id);
  });
}

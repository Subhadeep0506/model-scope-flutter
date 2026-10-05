import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmService llm;
  late FakeSettingsRepository settings;
  late ProviderContainer container;

  setUp(() {
    llm = FakeLlmService();
    settings = FakeSettingsRepository(
      const SamplerSettings(temperature: 1.1, topK: 12),
    );
    container = ProviderContainer.test(
      overrides: fakeOverrides(
        llm: llm,
        sessions: FakeSessionRepository(),
        settings: settings,
      ),
    );
  });

  test('loads the stored settings', () async {
    final loaded = await container.read(samplerViewModelProvider.future);

    check(loaded.temperature).equals(1.1);
    check(loaded.topK).equals(12);
  });

  test('apply saves and pushes the change onto the loaded model', () async {
    final stored = await container.read(samplerViewModelProvider.future);

    await container
        .read(samplerViewModelProvider.notifier)
        .apply(stored.copyWith(temperature: 0.2));

    check(settings.stored.temperature).equals(0.2);
    check(llm.applied.last.temperature).equals(0.2);
  });

  test('apply ignores a no-op change', () async {
    final stored = await container.read(samplerViewModelProvider.future);
    final before = settings.saveCalls;

    await container.read(samplerViewModelProvider.notifier).apply(stored);

    // No disk write, no needless call into the native sampler.
    check(settings.saveCalls).equals(before);
    check(llm.applied).isEmpty();
  });

  test('resetToDefaults restores every knob at once', () async {
    await container.read(samplerViewModelProvider.future);

    await container.read(samplerViewModelProvider.notifier).resetToDefaults();

    check(settings.stored).equals(const SamplerSettings());
    check(container.read(samplerViewModelProvider).value)
        .isNotNull()
        .equals(const SamplerSettings());
  });
}

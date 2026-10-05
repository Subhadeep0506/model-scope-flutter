import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/data/repositories/settings_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SamplerSettings', () {
    test('defaults match the values drawn in the Sampling mockup', () {
      const settings = SamplerSettings();

      check(settings.temperature).equals(0.70);
      check(settings.topP).equals(0.90);
      check(settings.topK).equals(40);
      check(settings.maxTokens).equals(512);
      check(settings.historyTurns).equals(10);
      check(settings.systemPrompt).isNotEmpty();
    });

    test('survives a JSON round-trip unchanged', () {
      const settings = SamplerSettings(
        temperature: 1.25,
        topP: 0.55,
        topK: 12,
        maxTokens: 2048,
        historyTurns: 4,
        systemPrompt: 'Answer in one sentence.',
      );

      final restored = SamplerSettings.fromJson(settings.toJson());

      check(restored).equals(settings);
    });

    test('uses snake_case keys on the wire', () {
      final json = const SamplerSettings().toJson();

      check(json.keys.toList()).deepEquals(<String>[
        'temperature',
        'top_p',
        'top_k',
        'max_tokens',
        'history_turns',
        'system_prompt',
      ]);
    });

    test('copyWith changes only the named field', () {
      const settings = SamplerSettings();

      final next = settings.copyWith(temperature: 0.1);

      check(next.temperature).equals(0.1);
      check(next.topP).equals(settings.topP);
      check(next).not((it) => it.equals(settings));
    });

    test('every slider default sits inside its range', () {
      check(SamplerSettings.defaultTemperature)
        ..isGreaterOrEqual(SamplerSettings.temperatureRange.$1)
        ..isLessOrEqual(SamplerSettings.temperatureRange.$2);
      check(SamplerSettings.defaultTopP)
        ..isGreaterOrEqual(SamplerSettings.topPRange.$1)
        ..isLessOrEqual(SamplerSettings.topPRange.$2);
      check(SamplerSettings.defaultTopK)
        ..isGreaterOrEqual(SamplerSettings.topKRange.$1)
        ..isLessOrEqual(SamplerSettings.topKRange.$2);
      check(SamplerSettings.defaultMaxTokens)
        ..isGreaterOrEqual(SamplerSettings.maxTokensRange.$1)
        ..isLessOrEqual(SamplerSettings.maxTokensRange.$2);
    });
  });

  group('SettingsRepository', () {
    late Directory directory;
    late SettingsRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('model_scope_settings');
      repository = SettingsRepository(
        JsonFileStore(directory: directory, fileName: 'settings.json'),
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('loads defaults when nothing has been saved', () async {
      final loaded = await repository.load();

      check(loaded).equals(const SamplerSettings());
    });

    test('round-trips saved settings', () async {
      const settings = SamplerSettings(temperature: 1.4, maxTokens: 64);

      await repository.save(settings);
      final loaded = await repository.load();

      check(loaded).equals(settings);
    });

    test(
      'falls back to defaults when the stored document is malformed',
      () async {
        await File('${directory.path}${Platform.pathSeparator}settings.json')
            .writeAsString('{"sampler":{"temperature":"hot"}}');

        final loaded = await repository.load();

        check(loaded).equals(const SamplerSettings());
      },
    );
  });
}

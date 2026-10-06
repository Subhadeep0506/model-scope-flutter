import 'dart:developer' as developer;

import '../../data/models/app_settings.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import 'llm_service.dart';

const String _logName = 'ModelLoader';

/// Loads [model], dropping GPU offload rather than giving up on it.
///
/// Returns a line to show the user, or null when the load went as asked.
///
/// The retry is deliberately not written back to settings: a refused GPU
/// allocation is about this attempt, so the next model gets another chance.
///
/// Shared by Chat and by an agent run, which both want the same weights and
/// the same fallback. Keeping it here rather than in either view model means
/// a phone whose driver refuses the allocation behaves the same in both.
Future<String?> loadWithFallback({
  required LlmService llm,
  required ModelDescriptor model,
  required SamplerSettings settings,
  required AppSettings runtime,
  String? projectorPath,
}) async {
  try {
    await llm.load(
      model: model,
      settings: settings,
      runtime: runtime,
      projectorPath: projectorPath,
    );
    return null;
  } catch (error, stackTrace) {
    if (!runtime.useGpu) rethrow;
    developer.log(
      'GPU load failed, retrying on the CPU',
      name: _logName,
      error: error,
      stackTrace: stackTrace,
    );
    await llm.load(
      model: model,
      settings: settings,
      runtime: runtime.copyWith(useGpu: false),
      projectorPath: projectorPath,
    );
    return 'Loaded on the CPU — GPU offload was unavailable.';
  }
}

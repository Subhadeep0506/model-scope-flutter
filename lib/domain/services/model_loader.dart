import 'dart:developer' as developer;

import '../../data/models/app_settings.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import 'llm_service.dart';

const String _logName = 'ModelLoader';

/// Loads [model], dropping GPU offload rather than giving up on it.
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

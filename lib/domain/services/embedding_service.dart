import 'dart:developer' as developer;
import 'dart:io';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../data/models/model_descriptor.dart';

/// The embedding model could not be loaded or could not encode. Worded to be
/// shown as-is.
class EmbeddingException implements Exception {
  const EmbeddingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns text into vectors.
///
/// An interface with one real implementation, the same arrangement as
/// [LlmService] and for the same reason: the tests must be able to encode
/// without a gigabyte of weights or a native library.
abstract interface class EmbeddingService {
  /// Whether weights are currently loaded.
  bool get isLoaded;

  /// Which model is loaded, or null when none is.
  String? get loadedModelId;

  Future<void> load(ModelDescriptor model);

  /// Encodes [texts], preserving order.
  Future<List<List<double>>> encode(List<String> texts);

  /// Releases the weights. Held only while indexing or retrieving.
  Future<void> dispose();
}

/// [EmbeddingService] backed by `package:nobodywho`'s encoder.
class NobodyWhoEmbeddingService implements EmbeddingService {
  NobodyWhoEmbeddingService();

  static const String _logName = 'NobodyWhoEmbeddingService';

  nobodywho.Encoder? _encoder;
  String? _loadedModelId;

  @override
  bool get isLoaded => _encoder != null;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  Future<void> load(ModelDescriptor model) async {
    if (_loadedModelId == model.id && _encoder != null) return;

    final file = File(model.localPath);
    if (!await file.exists()) {
      throw EmbeddingException(
        'The embedding model ${model.name} is no longer on this device. '
        'Download it again under Settings.',
      );
    }

    _encoder = null;
    _loadedModelId = null;
    try {
      _encoder = await nobodywho.Encoder.fromPath(modelPath: model.localPath);
    } catch (error) {
      throw EmbeddingException(
        'The embedding model ${model.name} could not be loaded: $error',
      );
    }
    _loadedModelId = model.id;
    developer.log('Loaded embedding model ${model.name}', name: _logName);
  }

  @override
  Future<List<List<double>>> encode(List<String> texts) async {
    final encoder = _encoder;
    if (encoder == null) {
      throw const EmbeddingException('No embedding model is loaded.');
    }
    if (texts.isEmpty) return const <List<double>>[];

    try {
      final vectors = await encoder.encodeBatch(texts: texts);
      return <List<double>>[for (final vector in vectors) vector.toList()];
    } catch (error) {
      throw EmbeddingException('The text could not be encoded: $error');
    }
  }

  @override
  Future<void> dispose() async {
    _encoder = null;
    _loadedModelId = null;
  }
}

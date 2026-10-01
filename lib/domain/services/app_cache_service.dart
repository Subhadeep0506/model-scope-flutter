import 'dart:developer' as developer;
import 'dart:io';

/// Measures and clears the files the app itself keeps on disk.
///
/// Downloaded weights are deliberately out of scope. They are the bulk of the
/// bytes, but they took minutes to fetch and a single tap should not throw them
/// away — a model is removed through its own trash button, one at a time.
class AppCacheService {
  const AppCacheService(this._documents);

  final Directory _documents;

  static const String _logName = 'AppCacheService';

  /// Files this service owns: saved transcripts and any half-written temporary
  /// files a killed write left behind.
  static const Set<String> _clearable = <String>{'sessions.json'};

  Future<int> sizeInBytes() async {
    var total = 0;
    await for (final file in _files()) {
      try {
        total += await file.length();
      } on FileSystemException {
        // Raced with a delete; it contributes nothing either way.
      }
    }
    return total;
  }

  Future<void> clear() async {
    await for (final file in _files()) {
      try {
        await file.delete();
      } on FileSystemException catch (error) {
        developer.log(
          'Could not delete ${file.path}',
          name: _logName,
          error: error,
        );
      }
    }
  }

  Stream<File> _files() async* {
    if (!await _documents.exists()) return;
    await for (final entity in _documents.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (_clearable.contains(name) || name.endsWith('.tmp')) yield entity;
    }
  }
}

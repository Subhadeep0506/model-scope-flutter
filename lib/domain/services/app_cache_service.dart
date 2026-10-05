import 'dart:developer' as developer;
import 'dart:io';

class AppCacheService {
  const AppCacheService(this._documents);

  final Directory _documents;

  static const String _logName = 'AppCacheService';

  static const Set<String> _clearable = <String>{'sessions.json'};

  /// Images belong to the sessions that reference them, so they are cleared
  /// with the transcripts rather than left behind pointing at nothing.
  static const String _images = 'images';

  Future<int> sizeInBytes() async {
    var total = 0;
    await for (final file in _files()) {
      try {
        total += await file.length();
      } on FileSystemException {}
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

    final images = Directory('${_documents.path}/$_images');
    if (!await images.exists()) return;
    await for (final entity in images.list()) {
      if (entity is File) yield entity;
    }
  }
}

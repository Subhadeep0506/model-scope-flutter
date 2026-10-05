import 'dart:developer' as developer;
import 'dart:io';

import 'package:uuid/uuid.dart';

/// Holds the images attached to messages. The system picker hands back a path
/// into a temporary directory the platform is free to empty, and `nobodywho`
/// re-reads an image from its path — so the app keeps its own copy, under the
/// directory sessions live in, and that copy is what a message points at.
class ImageStore {
  const ImageStore(this._documents);

  final Directory _documents;

  static const String _logName = 'ImageStore';
  static const String _folder = 'images';
  static const Uuid _uuid = Uuid();

  /// The app's own copy of [sourcePath], or null when it could not be made.
  Future<String?> save(String sourcePath) async {
    try {
      final folder = Directory('${_documents.path}/$_folder');
      if (!await folder.exists()) await folder.create(recursive: true);

      final target = '${folder.path}/${_uuid.v4()}${_extensionOf(sourcePath)}';
      await File(sourcePath).copy(target);
      return target;
    } catch (error, stackTrace) {
      developer.log(
        'Could not copy $sourcePath',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Deletes copies this store made. Paths it does not own are ignored, so a
  /// message written by an older build cannot delete anything unexpected.
  Future<void> delete(Iterable<String> paths) async {
    final folder = '${_documents.path}/$_folder';
    for (final path in paths) {
      if (!path.startsWith(folder)) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (error) {
        developer.log('Could not delete $path', name: _logName, error: error);
      }
    }
  }

  /// `.jpg` for `photo.JPG`, or an empty string when the name has no suffix.
  /// Lower-cased because the extension is what the decoder sniffs on.
  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '';
    return name.substring(dot).toLowerCase();
  }
}

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A directory of JSON documents, one per custom agent.
///
/// [JsonFileStore] holds a single document and is the right shape for settings
/// or a session list; an agent is its own file so that it can be exported,
/// shared or hand-edited on its own, and so that one corrupt agent cannot cost
/// the user the others. Writes use the same temporary-file-then-rename as
/// [JsonFileStore], so an interrupted write cannot leave half a document
/// behind.
class AgentFileStore {
  const AgentFileStore({required this.directory, this.folderName = 'agents'});

  /// The app's documents directory. The store keeps its files in
  /// [folderName] inside it.
  final Directory directory;

  final String folderName;

  Directory get _folder =>
      Directory('${directory.path}${Platform.pathSeparator}$folderName');

  File _fileFor(String id) =>
      File('${_folder.path}${Platform.pathSeparator}$id.json');

  /// Every document in the folder, by file name without the extension.
  ///
  /// A file that will not parse is logged and skipped rather than throwing:
  /// these are written by the app but edited by anyone, and one bad file must
  /// not empty the Agent bench.
  Future<Map<String, Map<String, dynamic>>> readAll() async {
    final folder = _folder;
    if (!await folder.exists()) return <String, Map<String, dynamic>>{};

    final documents = <String, Map<String, dynamic>>{};
    final entries = await folder.list().toList();
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final document = await _readFile(entry);
      if (document != null) {
        documents[_idOf(entry.path)] = document;
      }
    }
    return documents;
  }

  Future<Map<String, dynamic>?> _readFile(File file) async {
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = await compute(_decode, raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (error, stackTrace) {
      developer.log(
        'Skipped ${file.path}',
        name: 'AgentFileStore',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Writes [document] as `<id>.json`, replacing any file already there.
  /// Returns whether it was written.
  Future<bool> write(String id, Map<String, dynamic> document) async {
    try {
      final folder = _folder;
      if (!await folder.exists()) await folder.create(recursive: true);

      final encoded = await compute(_encode, document);
      final temp = File('${_fileFor(id).path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(_fileFor(id).path);
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Could not write agent $id',
        name: 'AgentFileStore',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Removes `<id>.json`. A file that is not there is not an error — deleting
  /// an agent twice should settle, not throw.
  Future<void> delete(String id) async {
    try {
      final file = _fileFor(id);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      developer.log(
        'Could not delete agent $id: ${error.message}',
        name: 'AgentFileStore',
      );
    }
  }

  static String _idOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.substring(0, name.length - '.json'.length);
  }
}

Object? _decode(String raw) => jsonDecode(raw);

/// Indented, because these files are meant to be readable: a user exporting an
/// agent or looking at one on a desktop should see something they can edit.
String _encode(Map<String, dynamic> document) =>
    const JsonEncoder.withIndent('  ').convert(document);

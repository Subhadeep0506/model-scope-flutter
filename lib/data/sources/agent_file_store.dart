import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

class AgentFileStore {
  const AgentFileStore({required this.directory, this.folderName = 'agents'});
  final Directory directory;
  final String folderName;

  Directory get _folder =>
      Directory('${directory.path}${Platform.pathSeparator}$folderName');

  File _fileFor(String id) =>
      File('${_folder.path}${Platform.pathSeparator}$id.json');

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

String _encode(Map<String, dynamic> document) =>
    const JsonEncoder.withIndent('  ').convert(document);

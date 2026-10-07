import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A document could not be turned into text. The message is written to be
/// shown to the user as-is, because this is the first thing that goes wrong
/// when they pick the wrong file.
class DocumentExtractionException implements Exception {
  const DocumentExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns a picked file into plain text.
///
/// Three formats, and nothing else: `.txt` and `.md` are read directly,
/// `.pdf` has its text layer pulled out. There is no OCR, so a PDF of
/// scanned pages holds no text to find — that case is named rather than left
/// to produce an empty index the user would have to diagnose from a bad
/// answer.
class DocumentExtractor {
  const DocumentExtractor();

  /// Extensions the picker offers and this understands. Kept here so the two
  /// cannot drift apart.
  static const List<String> extensions = <String>['txt', 'md', 'pdf'];

  Future<String> extract(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw DocumentExtractionException('That file is no longer there: $path');
    }

    final text = switch (extensionOf(path)) {
      'txt' || 'md' || 'markdown' || 'text' => await _readText(file),
      'pdf' => await _readPdf(file),
      final other => throw DocumentExtractionException(
        other.isEmpty
            ? 'That file has no extension, so there is no telling how to '
                  'read it. Pick a .txt, .md or .pdf file.'
            : 'This build cannot read .$other files. Pick a .txt, .md or '
                  '.pdf file.',
      ),
    };

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const DocumentExtractionException(
        'No text could be read from that file. If it is a PDF of scanned '
        'pages, the words are pictures — this build has no OCR to read them.',
      );
    }
    return trimmed;
  }

  /// The lower-case extension, without the dot. Empty when there is none.
  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// The file's name, which is what the model cites as the source.
  static String titleOf(String path) => path.split(RegExp(r'[/\\]')).last;

  Future<String> _readText(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException catch (error) {
      throw DocumentExtractionException(
        'That file could not be read: ${error.message}',
      );
    } on FormatException {
      throw const DocumentExtractionException(
        'That file is not readable as text — it may be in an encoding this '
        'build does not understand.',
      );
    }
  }

  /// Parsing a PDF is CPU-bound and scales with the page count, so it runs
  /// off the UI thread.
  Future<String> _readPdf(File file) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      throw DocumentExtractionException(
        'That PDF could not be read: ${error.message}',
      );
    }
    return compute(_extractPdfText, bytes);
  }
}

/// Runs in an isolate, so it must be a top-level function and must not touch
/// anything but its argument.
String _extractPdfText(Uint8List bytes) {
  PdfDocument? document;
  try {
    document = PdfDocument(inputBytes: bytes);
    return PdfTextExtractor(document).extractText();
  } catch (error) {
    throw DocumentExtractionException(
      'That PDF could not be opened. It may be encrypted, or damaged.',
    );
  } finally {
    document?.dispose();
  }
}

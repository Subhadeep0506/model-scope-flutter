import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';

import 'document_extractor.dart';

/// Picks a document for the Document QnA agent to read.
class DocumentPicker {
  const DocumentPicker();

  Future<String?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a document',
        type: FileType.custom,
        allowedExtensions: DocumentExtractor.extensions,
      );
      return file?.path;
    } catch (error, stackTrace) {
      developer.log(
        'Could not pick a document',
        name: 'DocumentPicker',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

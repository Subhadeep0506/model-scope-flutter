import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';

import 'document_extractor.dart';

/// Picks a document for the Document QnA agent to read.
///
/// Separate from [AttachmentPicker], which offers images for the chat
/// composer: the two allow different extensions and are reached from
/// different screens, and one picker taking a flag would read worse than two
/// that each say what they are for.
class DocumentPicker {
  const DocumentPicker();

  /// The path of the picked document, or null when the user cancelled or the
  /// platform gave back no readable path.
  Future<String?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a document',
        type: FileType.custom,
        // The same list the extractor understands, so the picker cannot
        // offer a file that is certain to be rejected.
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

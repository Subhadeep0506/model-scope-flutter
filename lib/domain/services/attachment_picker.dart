import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';

/// Picks an image to send with a message. Documents are deliberately not
/// offered here — those belong to the RAG agent, not the composer.
class AttachmentPicker {
  const AttachmentPicker();

  static const List<String> _extensions = <String>['jpg', 'jpeg', 'png'];

  /// The path of the picked image, or null when the user cancelled or the
  /// platform gave back no readable path.
  Future<String?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Attach an image',
        type: FileType.custom,
        allowedExtensions: _extensions,
      );
      return file?.path;
    } catch (error, stackTrace) {
      developer.log(
        'Could not pick an image',
        name: 'AttachmentPicker',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

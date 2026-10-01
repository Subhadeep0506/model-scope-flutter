import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';

/// The two branches of the Attach sheet.
enum AttachmentKind {
  pdf('PDF'),
  image('Image');

  const AttachmentKind(this.label);

  final String label;
}

/// Picks a file and reports its display name.
///
/// Only the name is returned: the bundled model is text-only, so the bytes are
/// deliberately never read. Keeping this behind an interface also keeps
/// `file_picker` out of the widget layer and lets tests supply a fake.
abstract interface class AttachmentPicker {
  /// Returns the chosen file's name, or `null` if the picker was dismissed.
  Future<String?> pick(AttachmentKind kind);
}

class FilePickerAttachmentPicker implements AttachmentPicker {
  const FilePickerAttachmentPicker();

  @override
  Future<String?> pick(AttachmentKind kind) async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Attach ${kind.label}',
        type: kind == AttachmentKind.pdf ? FileType.custom : FileType.image,
        allowedExtensions: kind == AttachmentKind.pdf
            ? const <String>['pdf']
            : null,
      );
      return file?.name;
    } catch (error, stackTrace) {
      developer.log(
        'Could not pick a ${kind.label}',
        name: 'FilePickerAttachmentPicker',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

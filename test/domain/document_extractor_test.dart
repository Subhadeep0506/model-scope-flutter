import 'dart:io';
import 'dart:ui';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/document_extractor.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  // PDF extraction runs on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const DocumentExtractor extractor = DocumentExtractor();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('extractor_test');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<String> write(String name, String content) async {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsString(content);
    return file.path;
  }

  /// A one-page PDF holding [text], built in memory rather than checked in as
  /// a fixture so the test says what it is reading.
  Future<String> writePdf(String name, String text) async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
      text,
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      bounds: const Rect.fromLTWH(0, 0, 400, 200),
    );
    final bytes = await document.save();
    document.dispose();

    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('extensionOf', () {
    test('reads the extension regardless of case or separator', () {
      check(DocumentExtractor.extensionOf('/a/b/notes.MD')).equals('md');
      check(DocumentExtractor.extensionOf(r'C:\docs\report.pdf')).equals('pdf');
    });

    test('a file with no extension has none', () {
      check(DocumentExtractor.extensionOf('/a/b/README')).isEmpty();
      // A dotfile is not an extension: `.gitignore` is the whole name.
      check(DocumentExtractor.extensionOf('/a/.gitignore')).isEmpty();
    });
  });

  test('titleOf is the file name, not the path', () {
    check(DocumentExtractor.titleOf(r'C:\docs\Q3 report.pdf'))
        .equals('Q3 report.pdf');
  });

  test('a text file is read as it stands', () async {
    final path = await write('notes.txt', 'The quarter closed up 8 per cent.');

    check(await extractor.extract(path))
        .equals('The quarter closed up 8 per cent.');
  });

  test('markdown is read too, markup and all', () async {
    final path = await write('notes.md', '# Heading\n\nSome **bold** text.');

    check(await extractor.extract(path)).contains('**bold**');
  });

  test('a PDF gives up its text layer', () async {
    final path = await writePdf('report.pdf', 'Revenue rose by 8 per cent.');

    check(await extractor.extract(path)).contains('Revenue rose by 8 per cent');
  });

  test('a PDF with no text layer is named as such, not left empty', () async {
    // A PDF of scanned pages reads as a page with nothing on it. Without
    // this, it would index zero passages and the agent would answer from
    // nothing while sounding certain.
    final document = PdfDocument()..pages.add();
    final bytes = await document.save();
    document.dispose();
    final file = File('${directory.path}${Platform.pathSeparator}scan.pdf');
    await file.writeAsBytes(bytes);

    await check(extractor.extract(file.path))
        .throws<DocumentExtractionException>(
          (it) => it.has((e) => e.message, 'message').contains('scanned'),
        );
  });

  test('an empty text file is a failure, not an empty document', () async {
    final path = await write('empty.txt', '   \n  ');

    await check(extractor.extract(path)).throws<DocumentExtractionException>();
  });

  test('an unsupported format says which formats work', () async {
    final path = await write('sheet.csv', 'a,b,c');

    await check(extractor.extract(path)).throws<DocumentExtractionException>(
      (it) => it.has((e) => e.message, 'message').contains('.txt'),
    );
  });

  test('a file that is not there says so rather than throwing an IO', () async {
    await check(extractor.extract('${directory.path}/gone.txt'))
        .throws<DocumentExtractionException>(
          (it) => it.has((e) => e.message, 'message').contains('no longer'),
        );
  });

  test('damaged PDF bytes are reported, not propagated raw', () async {
    final file = File('${directory.path}${Platform.pathSeparator}bad.pdf');
    await file.writeAsString('this is not a PDF at all');

    await check(extractor.extract(file.path))
        .throws<DocumentExtractionException>();
  });

  test('the picker and the reader agree on what is allowed', () {
    // The picker offers exactly what this understands; a mismatch would let
    // a user choose a file certain to be rejected.
    check(DocumentExtractor.extensions)
        .deepEquals(<String>['txt', 'md', 'pdf']);
  });
}

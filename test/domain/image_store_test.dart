import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/image_store.dart';

void main() {
  late Directory documents;
  late ImageStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('image_store_test');
    store = ImageStore(documents);
  });

  tearDown(() => documents.deleteSync(recursive: true));

  /// Writes a file outside the store, standing in for what the picker hands
  /// back: a path the app does not own.
  File source(String name, [String contents = 'bytes']) {
    final file = File('${documents.path}/picked-$name')
      ..writeAsStringSync(contents);
    return file;
  }

  test('save copies the file into the app\'s own folder', () async {
    final picked = source('photo.jpg');

    final stored = await store.save(picked.path);

    check(stored).isNotNull();
    final copy = File(stored ?? '');
    check(copy.existsSync()).isTrue();
    check(copy.readAsStringSync()).equals('bytes');
    check(copy.path).contains('${documents.path}/images');
    // The original is untouched: it belongs to the picker, not to us.
    check(picked.existsSync()).isTrue();
  });

  test('save keeps the extension, lower-cased', () async {
    final stored = await store.save(source('photo.JPG').path);

    check(stored ?? '').endsWith('.jpg');
  });

  test('two saves of one file do not collide', () async {
    final picked = source('photo.jpg');

    final first = await store.save(picked.path);
    final second = await store.save(picked.path);

    check(second).not((it) => it.equals(first));
    check(File(first ?? '').existsSync()).isTrue();
    check(File(second ?? '').existsSync()).isTrue();
  });

  test('save reports a source it cannot read instead of throwing', () async {
    final stored = await store.save('${documents.path}/not-here.jpg');

    check(stored).isNull();
  });

  test('delete removes copies this store made', () async {
    final stored = await store.save(source('photo.jpg').path) ?? '';

    await store.delete(<String>[stored]);

    check(File(stored).existsSync()).isFalse();
  });

  test('delete leaves files outside the store alone', () async {
    // A message written by an older build could hold any path at all, and
    // must not be able to delete something the app does not own.
    final outsider = source('elsewhere.jpg');

    await store.delete(<String>[outsider.path]);

    check(outsider.existsSync()).isTrue();
  });

  test('delete shrugs off a path that is already gone', () async {
    final stored = await store.save(source('photo.jpg').path) ?? '';
    await store.delete(<String>[stored]);

    await store.delete(<String>[stored]);

    check(File(stored).existsSync()).isFalse();
  });
}

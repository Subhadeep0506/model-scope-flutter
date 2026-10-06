import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/sources/agent_file_store.dart';

void main() {
  // The store encodes and decodes on `compute`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AgentFileStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent_file_store_test');
    store = AgentFileStore(directory: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// The file an agent with [id] should end up in.
  File fileFor(String id) => File(
    '${root.path}${Platform.pathSeparator}agents'
    '${Platform.pathSeparator}$id.json',
  );

  Map<String, dynamic> agent(String id) => <String, dynamic>{
    'id': id,
    'name': 'Agent $id',
  };

  test('reads back what it wrote', () async {
    check(await store.write('mine', agent('mine'))).isTrue();

    final documents = await store.readAll();

    check(documents.keys.toList()).deepEquals(<String>['mine']);
    check(documents['mine']?['name']).equals('Agent mine');
  });

  test('gives each agent its own file, named by its id', () async {
    await store.write('first', agent('first'));
    await store.write('second', agent('second'));

    // One file per agent is what lets a user export or hand-edit one, and
    // what stops a corrupt one costing them the others.
    check(await fileFor('first').exists()).isTrue();
    check(await fileFor('second').exists()).isTrue();
    check((await store.readAll()).keys.toList()..sort())
        .deepEquals(<String>['first', 'second']);
  });

  test('writing the same id again replaces it', () async {
    await store.write('mine', agent('mine'));
    await store.write('mine', <String, dynamic>{'id': 'mine', 'name': 'Newer'});

    final documents = await store.readAll();

    check(documents).length.equals(1);
    check(documents['mine']?['name']).equals('Newer');
  });

  test('writes something a person could read and edit', () async {
    await store.write('mine', agent('mine'));

    final raw = await fileFor('mine').readAsString();

    // Indented on purpose: an exported agent should be legible on a desktop.
    check(raw).contains('\n  "id": "mine"');
    check(jsonDecode(raw)).isA<Map<String, dynamic>>();
  });

  test('an empty folder reads as no agents, not an error', () async {
    check(await store.readAll()).isEmpty();
  });

  test('leaves files that are not JSON alone', () async {
    await store.write('real', agent('real'));
    await File(
      '${root.path}${Platform.pathSeparator}agents'
      '${Platform.pathSeparator}notes.txt',
    ).writeAsString('not an agent');

    check((await store.readAll()).keys.toList()).deepEquals(<String>['real']);
  });

  test('skips a corrupt agent rather than losing the rest', () async {
    await store.write('good', agent('good'));
    await fileFor('broken').create(recursive: true);
    await fileFor('broken').writeAsString('{ this is not json');

    final documents = await store.readAll();

    // Unlike a bundled template, which throws, these are the user's files.
    // One bad one must not empty the Agent bench.
    check(documents.keys.toList()).deepEquals(<String>['good']);
  });

  test('skips an empty file', () async {
    await fileFor('blank').create(recursive: true);
    await fileFor('blank').writeAsString('   ');

    check(await store.readAll()).isEmpty();
  });

  test('deletes an agent', () async {
    await store.write('mine', agent('mine'));

    await store.delete('mine');

    check(await fileFor('mine').exists()).isFalse();
    check(await store.readAll()).isEmpty();
  });

  test('deleting one that is not there settles quietly', () async {
    // Deleting an agent twice, or deleting a built-in, must not throw.
    await check(store.delete('never-existed')).completes();
  });

  test('an interrupted write leaves no stray temporary file', () async {
    await store.write('mine', agent('mine'));

    final names = await Directory('${root.path}${Platform.pathSeparator}agents')
        .list()
        .map((entry) => entry.path.split(RegExp(r'[\\/]')).last)
        .toList();

    check(names).deepEquals(<String>['mine.json']);
  });
}

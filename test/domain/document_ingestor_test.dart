import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/sources/vector_store.dart';
import 'package:model_scope_flutter/domain/services/document_extractor.dart';
import 'package:model_scope_flutter/domain/services/document_ingestor.dart';
import 'package:model_scope_flutter/domain/services/embedding_service.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late FakeDocumentIndex index;
  late FakeEmbeddingService embedder;
  late DocumentIngestor ingestor;

  final ModelDescriptor embeddingModel = fakeInstalledModel(
    repoId: 'CompendiumLabs/bge-small-en-v1.5-gguf',
    fileName: 'bge-small-en-v1.5-q8_0.gguf',
    name: 'BGE Small EN v1.5',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ingestor_test');
    index = FakeDocumentIndex();
    embedder = FakeEmbeddingService();
    ingestor = DocumentIngestor(const DocumentExtractor(), embedder, index);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<String> write(String name, String content) async {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsString(content);
    return file.path;
  }

  Future<List<IngestProgress>> run(String path) async =>
      ingestor.ingest(path: path, embeddingModel: embeddingModel).toList();

  test('reads, chunks, encodes and stores a document', () async {
    final path = await write(
      'report.txt',
      List<String>.filled(400, 'word').join(' '),
    );

    final progress = await run(path);

    check(index.chunks.length).isGreaterThan(1);
    check(index.stored.single.title).equals('report.txt');
    check(index.stored.single.embedModelId).equals(embeddingModel.id);
    check(index.stored.single.chunkCount).equals(index.chunks.length);
    check(progress.last.done).isTrue();
    check(progress.last.message).contains('Indexed report.txt');
  });

  test('every chunk carries a vector of the width the index expects', () async {
    final path = await write('a.txt', 'A short document about revenue.');

    await run(path);

    for (final chunk in index.chunks) {
      check(chunk.embedding.length).equals(kEmbeddingDimensions);
    }
  });

  test('chunks are numbered in the order they appear', () async {
    final path = await write(
      'ordered.txt',
      List<String>.generate(400, (i) => 'w$i').join(' '),
    );

    await run(path);

    check(index.chunks.map((c) => c.ordinal).toList())
        .deepEquals(<int>[for (var i = 0; i < index.chunks.length; i++) i]);
  });

  test('the encoder is loaded for the job and released after it', () async {
    final path = await write('a.txt', 'Something short.');

    await run(path);

    // Two models resident at once on a phone is how an allocation fails, and
    // the chat model is loaded straight after this.
    check(embedder.loadCalls).equals(1);
    check(embedder.disposeCalls).equals(1);
    check(embedder.isLoaded).isFalse();
  });

  test('the encoder is released even when encoding fails', () async {
    final path = await write('a.txt', 'Something short.');
    embedder.encodeFailure = const EmbeddingException('out of memory');

    await check(run(path)).throws<EmbeddingException>();

    check(embedder.disposeCalls).equals(1);
  });

  test('the same file is not encoded twice', () async {
    final path = await write('a.txt', 'Something short.');
    await run(path);

    final second = await run(path);

    // Re-encoding a document the user picked again costs tens of seconds to
    // arrive at exactly the same vectors.
    check(embedder.loadCalls).equals(1);
    check(second.single.done).isTrue();
    check(second.single.message).contains('Already indexed');
  });

  test('a different embedding model forces a re-encode', () async {
    final path = await write('a.txt', 'Something short.');
    await run(path);

    await ingestor
        .ingest(
          path: path,
          embeddingModel: fakeInstalledModel(
            repoId: 'second-state/All-MiniLM-L6-v2-Embedding-GGUF',
            fileName: 'all-MiniLM-L6-v2-Q8_0.gguf',
            name: 'All-MiniLM-L6 v2',
          ),
        )
        .toList();

    // Vectors from two models are not comparable, so the old ones cannot
    // just be kept.
    check(embedder.loadCalls).equals(2);
  });

  test('indexing a second document replaces the first', () async {
    await run(await write('first.txt', 'All about apples.'));
    await run(await write('second.txt', 'All about oranges.'));

    // The index holds one document; leaving the first behind would let the
    // agent retrieve from a document the user is no longer asking about.
    check(index.stored).length.equals(1);
    check(index.stored.single.title).equals('second.txt');
    for (final chunk in index.chunks) {
      check(chunk.text).contains('oranges');
    }
  });

  test('a document with no readable text indexes nothing', () async {
    final path = await write('empty.txt', '   ');

    await check(run(path)).throws<DocumentExtractionException>();

    check(index.chunks).isEmpty();
  });

  test('docIdFor treats both slash styles as the same file', () {
    check(DocumentIngestor.docIdFor(r'C:\docs\a.txt'))
        .equals(DocumentIngestor.docIdFor('C:/docs/a.txt'));
  });
}

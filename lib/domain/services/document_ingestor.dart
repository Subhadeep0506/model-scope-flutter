import 'dart:developer' as developer;

import '../../data/models/model_descriptor.dart';
import '../../data/repositories/document_index_repository.dart';
import '../../data/sources/vector_store.dart';
import 'document_extractor.dart';
import 'embedding_service.dart';
import 'text_chunker.dart';

/// What indexing is doing, for the run log.
class IngestProgress {
  const IngestProgress(this.message, {this.done = false});

  final String message;
  final bool done;
}

/// Reads a document, splits it, encodes it and stores it.
class DocumentIngestor {
  const DocumentIngestor(this._extractor, this._embedder, this._index);

  final DocumentExtractor _extractor;
  final EmbeddingService _embedder;
  final DocumentIndexRepository _index;
  static const int _batchSize = 16;
  static const String _logName = 'DocumentIngestor';
  
  /// Indexes [path], reporting what it is doing as it goes.
  Stream<IngestProgress> ingest({
    required String path,
    required ModelDescriptor embeddingModel,
    int chunkChars = kChunkSize,
    int overlapChars = kChunkOverlap,
  }) async* {
    final docId = docIdFor(path);
    final existing = _index.documentOf(docId);
    if (existing != null &&
        existing.embedModelId == embeddingModel.id &&
        existing.chunkChars == chunkChars) {
      yield IngestProgress(
        'Already indexed: ${existing.title}, '
        '${existing.chunkCount} passages.',
        done: true,
      );
      return;
    }

    yield const IngestProgress('Reading the document…');
    final text = await _extractor.extract(path);

    final chunks = chunkText(text, size: chunkChars, overlap: overlapChars);
    if (chunks.isEmpty) {
      throw const DocumentExtractionException(
        'That document held no text worth indexing.',
      );
    }
    yield IngestProgress(
      '${text.length} characters, split into ${chunks.length} passages.',
    );

    yield IngestProgress('Loading ${embeddingModel.name}…');
    await _embedder.load(embeddingModel);

    try {
      final rows = <DocumentChunk>[];
      for (var start = 0; start < chunks.length; start += _batchSize) {
        final end = (start + _batchSize).clamp(0, chunks.length);
        final batch = chunks.sublist(start, end);
        final vectors = await _embedder.encode(batch);

        for (final (offset, vector) in vectors.indexed) {
          rows.add(
            DocumentChunk(
              docId: docId,
              ordinal: start + offset,
              text: batch[offset],
              embedding: vector,
            ),
          );
        }
        yield IngestProgress('Encoded $end of ${chunks.length} passages.');
      }

      _index.replaceWith(
        IngestedDocument(
          docId: docId,
          title: DocumentExtractor.titleOf(path),
          sourcePath: path,
          chunkCount: rows.length,
          embedModelId: embeddingModel.id,
          chunkChars: chunkChars,
          ingestedAt: DateTime.now(),
        ),
        rows,
      );
      developer.log('Indexed $path into ${rows.length} chunks', name: _logName);
      yield IngestProgress(
        'Indexed ${DocumentExtractor.titleOf(path)}: '
        '${rows.length} passages.',
        done: true,
      );
    } finally {
      // Released whether or not it worked: the chat model has to fit in what
      // this was using.
      await _embedder.dispose();
    }
  }

  static String docIdFor(String path) => path.replaceAll('\\', '/');
}

import 'dart:developer' as developer;

import '../../objectbox.g.dart';
import '../sources/vector_store.dart';

class RetrievedChunk {
  const RetrievedChunk({
    required this.text,
    required this.ordinal,
    required this.title,
    required this.score,
  });

  final String text;
  final int ordinal;
  final String title;
  final double score;
}

class DocumentIndexRepository {
  const DocumentIndexRepository(this._store);

  final Store _store;

  static const String _logName = 'DocumentIndexRepository';

  Box<DocumentChunk> get _chunks => _store.box<DocumentChunk>();
  Box<IngestedDocument> get _documents => _store.box<IngestedDocument>();

  List<IngestedDocument> documents() {
    final all = _documents.getAll();
    all.sort((a, b) => b.ingestedAt.compareTo(a.ingestedAt));
    return all;
  }

  IngestedDocument? documentOf(String docId) => _documents
      .query(IngestedDocument_.docId.equals(docId))
      .build()
      .findFirst();

  int chunkCount() => _chunks.count();

  void replaceWith(IngestedDocument document, List<DocumentChunk> chunks) {
    _store.runInTransaction(TxMode.write, () {
      _chunks.removeAll();
      _documents.removeAll();
      _documents.put(document);
      _chunks.putMany(chunks);
    });
    developer.log(
      'Indexed ${document.title}: ${chunks.length} chunks',
      name: _logName,
    );
  }

  List<RetrievedChunk> search(List<double> vector, {int topK = 4}) {
    if (vector.length != kEmbeddingDimensions) {
      developer.log(
        'Query vector has ${vector.length} dimensions, '
        'the index has $kEmbeddingDimensions',
        name: _logName,
      );
      return const <RetrievedChunk>[];
    }

    final titles = <String, String>{
      for (final document in _documents.getAll())
        document.docId: document.title,
    };

    final query = _chunks
        .query(
          DocumentChunk_.embedding.nearestNeighborsF32(
            vector,
            topK.clamp(1, 50),
          ),
        )
        .build();
    try {
      return <RetrievedChunk>[
        for (final result in query.findWithScores())
          RetrievedChunk(
            text: result.object.text,
            ordinal: result.object.ordinal,
            title: titles[result.object.docId] ?? 'the document',
            score: result.score,
          ),
      ];
    } finally {
      query.close();
    }
  }

  void clear() {
    _store.runInTransaction(TxMode.write, () {
      _chunks.removeAll();
      _documents.removeAll();
    });
    developer.log('Cleared the document index', name: _logName);
  }
}

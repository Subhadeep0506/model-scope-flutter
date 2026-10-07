import 'dart:developer' as developer;

import '../../objectbox.g.dart';
import '../sources/vector_store.dart';

/// One retrieved passage and how close it was to the query.
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

  /// Cosine distance from the query: smaller is closer. Reported rather than
  /// hidden so the trace can show whether retrieval found anything relevant
  /// or merely found the nearest of several bad options.
  final double score;
}

/// The local vector database: chunks in, nearest passages out.
///
/// One document at a time by default. A library of documents is a feature
/// this build does not need — the agent takes one file per run — and keeping
/// a single document means the index is always small enough to search in a
/// few milliseconds on a phone.
class DocumentIndexRepository {
  const DocumentIndexRepository(this._store);

  final Store _store;

  static const String _logName = 'DocumentIndexRepository';

  Box<DocumentChunk> get _chunks => _store.box<DocumentChunk>();
  Box<IngestedDocument> get _documents => _store.box<IngestedDocument>();

  /// What has been indexed, newest first.
  List<IngestedDocument> documents() {
    final all = _documents.getAll();
    all.sort((a, b) => b.ingestedAt.compareTo(a.ingestedAt));
    return all;
  }

  /// The record for [docId], or null when it has never been indexed.
  IngestedDocument? documentOf(String docId) => _documents
      .query(IngestedDocument_.docId.equals(docId))
      .build()
      .findFirst();

  int chunkCount() => _chunks.count();

  /// Replaces whatever was indexed with [document] and its [chunks].
  ///
  /// A replacement rather than an addition: the index holds one document, so
  /// indexing a second must not leave the first behind to be retrieved from.
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

  /// The [topK] passages closest to [vector], closest first.
  List<RetrievedChunk> search(List<double> vector, {int topK = 4}) {
    if (vector.length != kEmbeddingDimensions) {
      // A vector of the wrong width is silently ignored by the index rather
      // than rejected, which would read as "nothing relevant" — worth saying
      // out loud instead.
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
      // `findWithScores` rather than `find`: only the scoring variants return
      // the neighbours in distance order, which is the whole point.
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

  /// Empties the index. Behind the Clear action in Settings.
  void clear() {
    _store.runInTransaction(TxMode.write, () {
      _chunks.removeAll();
      _documents.removeAll();
    });
    developer.log('Cleared the document index', name: _logName);
  }
}

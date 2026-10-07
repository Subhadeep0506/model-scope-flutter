import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/sources/vector_store.dart';

/// What is in the local vector database right now.
class DocumentIndexState {
  const DocumentIndexState({this.chunks = 0, this.document});

  static const DocumentIndexState empty = DocumentIndexState();

  /// How many passages are stored.
  final int chunks;

  /// The document they came from, or null when nothing is indexed.
  final IngestedDocument? document;
}

/// Owns the Settings view of the document index.
///
/// Reads rather than watches: the index is written by an agent run, not by
/// this screen, and a run invalidates this when it finishes. Polling a native
/// database on every rebuild would cost more than it is worth.
class DocumentIndexViewModel extends Notifier<DocumentIndexState> {
  @override
  DocumentIndexState build() => _read();

  /// Empties the index, behind the Clear button.
  void clear() {
    ref.read(documentIndexRepositoryProvider).clear();
    state = DocumentIndexState.empty;
  }

  /// Re-reads the store, after a run has indexed something.
  void refresh() => state = _read();

  DocumentIndexState _read() {
    final repository = ref.read(documentIndexRepositoryProvider);
    final documents = repository.documents();
    return DocumentIndexState(
      chunks: repository.chunkCount(),
      document: documents.isEmpty ? null : documents.first,
    );
  }
}

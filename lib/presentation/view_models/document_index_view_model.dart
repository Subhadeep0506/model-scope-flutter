import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/sources/vector_store.dart';

/// What is in the local vector database right now.
class DocumentIndexState {
  const DocumentIndexState({this.chunks = 0, this.document});
  static const DocumentIndexState empty = DocumentIndexState();
  final int chunks;
  final IngestedDocument? document;
}

/// Owns the Settings view of the document index.
class DocumentIndexViewModel extends Notifier<DocumentIndexState> {
  @override
  DocumentIndexState build() => _read();
  void clear() {
    ref.read(documentIndexRepositoryProvider).clear();
    state = DocumentIndexState.empty;
  }
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

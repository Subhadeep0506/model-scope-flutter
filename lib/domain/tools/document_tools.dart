library;

import '../../data/models/model_descriptor.dart';
import '../../data/repositories/document_index_repository.dart';
import '../services/embedding_service.dart';
import 'tool_definition.dart';

/// How many passages retrieval returns by default.
const int kDefaultTopK = 4;

/// How long a passage may be before the tool trims it, in characters. Four
/// whole chunks plus the question has to fit a phone-sized context.
const int kPassageLimit = 900;

/// What the current run wants from retrieval.
///
/// Held in one mutable object the run writes before it starts, because a tool
/// is built once in the registry and knows nothing about the run calling it —
/// the same indirection the web tools use to read an API key per call rather
/// than capture one.
class RetrievalSettings {
  RetrievalSettings({this.topK = kDefaultTopK, this.embeddingModel});

  int topK;

  /// Which model encodes the query. Must be the one that encoded the
  /// document: vectors from two different models are not comparable.
  ModelDescriptor? embeddingModel;

  void apply({int? topK, ModelDescriptor? embeddingModel}) {
    this.topK = (topK ?? this.topK).clamp(1, 20);
    this.embeddingModel = embeddingModel ?? this.embeddingModel;
  }
}

ToolDefinition searchDocumentTool({
  required DocumentIndexRepository index,
  required EmbeddingService embedder,
  required RetrievalSettings settings,
  int passageLimit = kPassageLimit,
}) {
  Future<String> run({required String query}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return 'The search needs a question to look for.';
    }

    final model = settings.embeddingModel;
    if (model == null) {
      return 'No embedding model is installed, so the document cannot be '
          'searched. One can be downloaded under Settings.';
    }

    try {
      await embedder.load(model);
      final vectors = await embedder.encode(<String>[trimmed]);
      if (vectors.isEmpty) {
        return 'The question could not be encoded, so nothing was searched.';
      }

      final hits = index.search(vectors.first, topK: settings.topK);
      return formatPassages(hits, query: trimmed, passageLimit: passageLimit);
    } on EmbeddingException catch (error) {
      // Never thrown onward: whatever comes back goes straight to the model,
      // and a sentence it can relay beats a crashed run.
      return 'The document search failed. $error';
    } finally {
      await embedder.dispose();
    }
  }

  return ToolDefinition(
    name: 'search_document',
    description:
        'Search the document the user supplied and return the passages '
        'closest in meaning to a question. Use this before answering '
        'anything about the document, and answer only from what it returns — '
        'the document is not in your training data.',
    function: run,
    parameterDescriptions: const <String, String>{
      'query':
          'What to look for, as the question in plain words. A phrase or a '
          'question, not a file name and not a keyword list.',
    },
  );
}

/// The retrieved passages as the text a model reads.
String formatPassages(
  List<RetrievedChunk> hits, {
  required String query,
  int passageLimit = kPassageLimit,
}) {
  if (hits.isEmpty) {
    return 'Nothing in the document matched "$query". Either it does not '
        'cover this, or no document has been indexed yet.';
  }

  final lines = <String>[
    'Passages from ${hits.first.title} matching "$query":',
  ];
  for (final (index, hit) in hits.indexed) {
    lines.add('\n${index + 1}. (passage ${hit.ordinal + 1})');
    lines.add(_trim(hit.text, passageLimit));
  }
  lines.add(
    '\nAnswer only from these passages. If they do not settle the question, '
    'say so rather than filling the gap.',
  );
  return lines.join('\n');
}

String _trim(String text, int limit) {
  if (text.length <= limit) return text;
  final head = text.substring(0, limit);
  final lastBreak = head.lastIndexOf(' ');
  final cut = lastBreak > limit ~/ 2 ? head.substring(0, lastBreak) : head;
  return '${cut.trimRight()}…';
}

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/repositories/document_index_repository.dart';
import 'package:model_scope_flutter/data/sources/vector_store.dart';
import 'package:model_scope_flutter/domain/services/embedding_service.dart';
import 'package:model_scope_flutter/domain/tools/document_tools.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';

import '../support/fakes.dart';

void main() {
  late FakeDocumentIndex index;
  late FakeEmbeddingService embedder;
  late RetrievalSettings settings;

  setUp(() {
    index = FakeDocumentIndex();
    embedder = FakeEmbeddingService();
    settings = RetrievalSettings(
      embeddingModel: fakeInstalledModel(name: 'BGE Small'),
    );
  });

  /// Puts [passages] in the index, encoded the way the fake encoder does.
  void seed(List<String> passages, {String title = 'report.pdf'}) {
    index.replaceWith(
      IngestedDocument(
        docId: 'doc',
        title: title,
        sourcePath: '/tmp/$title',
        chunkCount: passages.length,
        embedModelId: 'm',
        ingestedAt: DateTime(2026, 10, 7),
      ),
      <DocumentChunk>[
        for (final (ordinal, text) in passages.indexed)
          DocumentChunk(
            docId: 'doc',
            ordinal: ordinal,
            text: text,
            embedding: fakeVector(text),
          ),
      ],
    );
  }

  ToolDefinition toolFor() =>
      searchDocumentTool(index: index, embedder: embedder, settings: settings);

  Future<String> ask(String query) async => await Function.apply(
    toolFor().function,
    <Object?>[],
    <Symbol, Object?>{#query: query},
  ) as String;

  test('retrieves the passage about the same subject', () async {
    seed(<String>[
      'Revenue rose eight per cent in the third quarter.',
      'The office cafeteria now opens at seven in the morning.',
      'Headcount fell by four people across engineering.',
    ]);

    final result = await ask('what happened to revenue');

    // The revenue passage shares words with the question, so it ranks first.
    check(result).contains('Revenue rose eight per cent');
    check(result).contains('report.pdf');
  });

  test('returns as many passages as the run asked for', () async {
    seed(<String>['one alpha', 'two beta', 'three gamma', 'four delta']);
    settings.apply(topK: 2);

    final result = await ask('alpha beta gamma delta');

    // Two numbered passages, not four.
    check(result).contains('\n1. ');
    check(result).contains('\n2. ');
    check(result.contains('\n3. ')).isFalse();
  });

  test('tells the model to stay inside what it was given', () async {
    seed(<String>['Something about the quarter.']);

    // The instruction is the whole reason retrieval helps a small model.
    check(await ask('the quarter')).contains('Answer only from these');
  });

  test('an empty index says so rather than returning nothing', () async {
    final result = await ask('anything');

    check(result).contains('Nothing in the document matched');
  });

  test('an empty question is refused without encoding anything', () async {
    seed(<String>['Something.']);

    check(await ask('   ')).contains('needs a question');
    check(embedder.encoded).isEmpty();
  });

  test('with no embedding model it names the fix', () async {
    seed(<String>['Something.']);
    settings.embeddingModel = null;

    final result = await ask('anything');

    check(result).contains('No embedding model');
    check(result).contains('Settings');
  });

  test('an encoder failure is a sentence, not a thrown error', () async {
    // A tool must never throw: whatever comes back goes to the model.
    seed(<String>['Something.']);
    embedder.loadFailure = const EmbeddingException('the weights are gone');

    check(await ask('anything')).contains('the weights are gone');
  });

  test('the encoder is released even when retrieval fails', () async {
    seed(<String>['Something.']);
    embedder.encodeFailure = const EmbeddingException('out of memory');

    await ask('anything');

    // Otherwise the chat model has to fit in what this was still using.
    check(embedder.disposeCalls).equals(1);
    check(embedder.isLoaded).isFalse();
  });

  test('the encoder is released after a search that worked', () async {
    seed(<String>['Something.']);

    await ask('something');

    check(embedder.disposeCalls).equals(1);
  });

  group('formatPassages', () {
    test('numbers passages from one, by their place in the document', () {
      final text = formatPassages(<RetrievedChunk>[
        const RetrievedChunk(
          text: 'Third passage.',
          ordinal: 2,
          title: 'notes.md',
          score: 0.1,
        ),
      ], query: 'q');

      // Numbered 1 in the list, but reported as passage 3 of the document.
      check(text).contains('1. (passage 3)');
    });

    test('a long passage is cut short rather than flooding the context', () {
      final text = formatPassages(
        <RetrievedChunk>[
          RetrievedChunk(
            text: List<String>.filled(300, 'word').join(' '),
            ordinal: 0,
            title: 'long.txt',
            score: 0,
          ),
        ],
        query: 'q',
        passageLimit: 100,
      );

      check(text).contains('…');
      check(text.length).isLessThan(400);
    });
  });
}

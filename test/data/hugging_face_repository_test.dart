import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/repositories/hugging_face_repository.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';

void main() {
  // The client decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A repository whose Hub answers each request with the next entry of
  /// [pages], a cursor following every page but the last.
  ///
  /// [requests] is handed back so a test can assert how many calls went out —
  /// page chasing has to stay inside the Hub's rate limit.
  (HfHuggingFaceRepository, List<int>) repositoryOver(
    List<List<String>> pages,
  ) {
    final requests = <int>[];
    final client = HfApiClient(
      MockClient((request) async {
        final index = requests.length;
        requests.add(index);
        final isLast = index >= pages.length - 1;
        return http.Response(
          jsonEncode(<Map<String, Object?>>[
            for (final id in pages[index])
              <String, Object?>{'id': id, 'downloads': 10, 'likes': 2},
          ]),
          200,
          headers: isLast
              ? const <String, String>{}
              : <String, String>{
                  'link':
                      '<https://hf.co/api/models?cursor=c$index>; '
                      'rel="next"',
                },
          request: request,
        );
      }),
    );
    return (HfHuggingFaceRepository(client, () async => null), requests);
  }

  Future<List<String>> idsFrom(HfHuggingFaceRepository repository) async {
    final page = await repository.search(
      sort: CatalogSort.downloads,
      query: '',
    );
    return page.items.map((repo) => repo.id).toList();
  }

  group('search', () {
    test('drops repos whose name states more than 4B parameters', () async {
      // Arrange
      final (repository, _) = repositoryOver(<List<String>>[
        <String>[
          'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
          'bartowski/Llama-3.2-3B-Instruct-GGUF',
          'bartowski/Qwen2.5-7B-Instruct-GGUF',
          'bartowski/Llama-3.3-70B-Instruct-GGUF',
        ],
      ]);

      // Act
      final ids = await idsFrom(repository);

      // Assert — the device runs inference itself; 7B and up cannot answer.
      check(ids).deepEquals(<String>[
        'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
        'bartowski/Llama-3.2-3B-Instruct-GGUF',
      ]);
    });

    test('keeps a repo whose name states no parameter count', () async {
      // Arrange
      final (repository, _) = repositoryOver(<List<String>>[
        <String>['microsoft/Phi-3.5-mini-instruct-gguf'],
      ]);

      // Act
      final ids = await idsFrom(repository);

      // Assert — plenty of small models never say, and `mini` is not a number.
      check(ids).deepEquals(<String>['microsoft/Phi-3.5-mini-instruct-gguf']);
    });

    test('drops a mixture-of-experts repo named for its expert size', () async {
      // Arrange
      final (repository, _) = repositoryOver(<List<String>>[
        <String>['TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF'],
      ]);

      // Act
      final ids = await idsFrom(repository);

      // Assert — 8x7B is a 47B model, not a 7B one.
      check(ids).isEmpty();
    });

    test('chases pages until it has enough to fill the list', () async {
      // Arrange — two rows survive per upstream page.
      final (repository, requests) = repositoryOver(<List<String>>[
        for (var page = 0; page < 6; page++)
          <String>[
            'owner/Small-1B-$page-GGUF',
            'owner/Small-2B-$page-GGUF',
            'owner/Big-70B-$page-GGUF',
          ],
      ]);

      // Act
      final ids = await idsFrom(repository);

      // Assert — five requests is the cap, so ten rows come back and the
      // sixth page is left for the next `loadMore`.
      check(requests).length.equals(5);
      check(ids).length.equals(10);
    });

    test('stops chasing at the end of the catalog', () async {
      // Arrange — one short page, no cursor after it.
      final (repository, requests) = repositoryOver(<List<String>>[
        <String>['owner/Tiny-360M-GGUF'],
      ]);

      // Act
      final page = await repository.search(
        sort: CatalogSort.downloads,
        query: '',
      );

      // Assert — a null cursor ends the list rather than being retried.
      check(requests).length.equals(1);
      check(page.nextCursor).isNull();
      check(page.items).length.equals(1);
    });
  });
}

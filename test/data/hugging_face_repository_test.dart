import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/repositories/hugging_face_repository.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';

void main() {
  // The client decodes the file tree on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const String repoId = 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF';

  /// Every request the repository actually sent, in order.
  late List<Uri> sent;

  /// Bearer tokens seen by the Hub, `null` where the request was anonymous.
  late List<String?> bearers;

  String detailsBody() => jsonEncode(<String, Object?>{
    'id': repoId,
    'downloads': 182000,
    'likes': 412,
    'siblings': <Map<String, Object?>>[
      <String, Object?>{'rfilename': 'qwen2.5-coder-1.5b-q4_k_m.gguf'},
    ],
  });

  String treeBody() => jsonEncode(<Map<String, Object?>>[
    <String, Object?>{
      'type': 'file',
      'path': 'qwen2.5-coder-1.5b-q4_k_m.gguf',
      'lfs': <String, Object?>{'size': 1100000000},
    },
  ]);

  /// A repository over a Hub that answers with [status]. [token] is read per
  /// request rather than held as a copy.
  HuggingFaceRepository repositoryOver({
    int status = 200,
    Future<String?> Function()? token,
  }) {
    final client = HfApiClient(
      MockClient((request) async {
        sent.add(request.url);
        bearers.add(request.headers['Authorization']);
        if (status != 200) return http.Response('{}', status, request: request);

        final isTree = request.url.path.endsWith('/tree/main');
        return http.Response(
          isTree ? treeBody() : detailsBody(),
          200,
          request: request,
        );
      }),
    );
    return HuggingFaceRepository(client, token ?? () async => null);
  }

  setUp(() {
    sent = <Uri>[];
    bearers = <String?>[];
  });

  group('detailsOf', () {
    test('asks the Hub once and serves the rest from memory', () async {
      final repository = repositoryOver();

      // The catalog card rebuilds whenever anything above it changes.
      final first = await repository.detailsOf(repoId);
      final second = await repository.detailsOf(repoId);

      // The Hub rate-limits unauthenticated clients hard, so a rebuild
      // must cost nothing.
      check(sent).length.equals(1);
      check(second.downloads).equals(first.downloads);
      check(first.likes).equals(412);
    });

    test('two callers at once share one in-flight request', () async {
      // The catalog builds its cards in the same frame.
      final repository = repositoryOver();

      await Future.wait<void>(<Future<void>>[
        repository.detailsOf(repoId),
        repository.detailsOf(repoId),
        repository.detailsOf(repoId),
      ]);

      check(sent).length.equals(1);
    });

    test('reports the file count the stats row shows', () async {
      final repository = repositoryOver();

      final summary = await repository.detailsOf(repoId);

      check(summary.fileCountLabel).equals('1 file');
    });

    test('a rate-limited answer is not remembered as the result', () async {
      // Hugging Face returns 429 to anonymous clients under load.
      final repository = repositoryOver(status: 429);

      await check(repository.detailsOf(repoId)).throws<HfApiException>();

      // Cached, the Retry button could never succeed.
      await check(repository.detailsOf(repoId)).throws<HfApiException>();
      check(sent).length.equals(2);
    });
  });

  group('filesOf', () {
    test('asks the Hub once per repository', () async {
      // The model sheet is the only thing that reads a file tree.
      final repository = repositoryOver();

      final files = await repository.filesOf(repoId);
      await repository.filesOf(repoId);

      check(sent).length.equals(1);
      check(sent.single.path).endsWith('/tree/main');
      check(files).length.equals(1);
      check(files.single.sizeBytes).equals(1100000000);
    });

    test('its cache is separate from the stats cache', () async {
      // One is `/api/models/x`, the other `/api/models/x/tree/main`.
      final repository = repositoryOver();

      await repository.detailsOf(repoId);
      await repository.filesOf(repoId);

      // Sharing a key would serve one answer for both questions.
      check(sent).length.equals(2);
    });

    test('a failed tree can be retried', () async {
      // A gated repository rejects an anonymous request.
      final repository = repositoryOver(status: 401);

      await check(repository.filesOf(repoId)).throws<HfApiException>();
      await check(repository.filesOf(repoId)).throws<HfApiException>();

      // The user adds a token in Settings, then taps Retry.
      check(sent).length.equals(2);
    });
  });

  test(
    'the stored token is read at request time, not at construction',
    () async {
      // A key typed into Settings must take effect without a restart.
      String? stored;
      final repository = repositoryOver(token: () async => stored);

      await repository.detailsOf(repoId);
      stored = 'hf_abc';
      await repository.filesOf(repoId);

      check(bearers).deepEquals(<String?>[null, 'Bearer hf_abc']);
    },
  );
}

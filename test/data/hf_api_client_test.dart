import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';

void main() {
  // The client decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A client that answers every request with [body] and [headers].
  HfApiClient clientReturning(
    Object body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
    void Function(http.Request request)? onRequest,
  }) => HfApiClient(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: headers,
        // Model names carry accents often enough that a wrong charset would
        // corrupt real responses.
        request: request,
      );
    }),
  );

  List<Map<String, Object?>> repos(List<String> ids) => <Map<String, Object?>>[
    for (final id in ids)
      <String, Object?>{'id': id, 'downloads': 10, 'likes': 2},
  ];

  group('listModels', () {
    test(
      'asks for text-generation GGUF repos in the requested order',
      () async {
        // Arrange
        Uri? asked;
        final client = clientReturning(
          repos(<String>['a/b']),
          onRequest: (request) => asked = request.url,
        );

        // Act
        await client.listModels(sort: CatalogSort.likes, query: '  qwen  ');

        // Assert — without the pipeline tag the Hub also returns embedding and
        // object-detection repos, which cannot answer a prompt.
        final params = asked?.queryParameters ?? const <String, String>{};
        check(params['filter']).equals('gguf');
        check(params['pipeline_tag']).equals('text-generation');
        check(params['sort']).equals('likes');
        check(params['search']).equals('qwen');
        check(params).not((it) => it.containsKey('cursor'));
      },
    );

    test('extracts the cursor from the Link header', () async {
      // Arrange
      final client = clientReturning(
        repos(<String>['a/b']),
        headers: <String, String>{
          'link':
              '<https://huggingface.co/api/models?cursor=eyJfaWQ'
              '&limit=20>; rel="next"',
        },
      );

      // Act
      final page = await client.listModels();

      // Assert
      check(page.items).length.equals(1);
      check(page.nextCursor).equals('eyJfaWQ');
    });

    test('reports the last page as having no cursor', () async {
      // Arrange — Hugging Face omits the header entirely at the end.
      final client = clientReturning(repos(<String>['a/b']));

      // Act
      final page = await client.listModels();

      // Assert
      check(page.nextCursor).isNull();
    });

    test('passes a cursor back on the next page', () async {
      // Arrange
      Uri? asked;
      final client = clientReturning(
        repos(<String>['a/b']),
        onRequest: (request) => asked = request.url,
      );

      // Act
      await client.listModels(cursor: 'eyJfaWQ');

      // Assert
      check(asked?.queryParameters['cursor']).equals('eyJfaWQ');
    });
  });

  group('listFiles', () {
    test('prefers the LFS size over the pointer size', () async {
      // Arrange — `size` is the 134-byte pointer; `lfs.size` is the payload.
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'path': 'model-q4_k_m.gguf',
          'size': 134,
          'lfs': <String, Object?>{'size': 1100000000},
        },
      ]);

      // Act
      final files = await client.listFiles('a/b');

      // Assert
      check(files.single.sizeBytes).equals(1100000000);
      check(files.single.sizeLabel).equals('1.10 GB');
    });

    test('falls back to size when the file is not in LFS', () async {
      // Arrange
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'path': 'tiny-q2_k.gguf',
          'size': 2000000,
        },
      ]);

      // Act
      final files = await client.listFiles('a/b');

      // Assert
      check(files.single.sizeBytes).equals(2000000);
    });

    test('drops directories, vision projectors and split shards', () async {
      // Arrange
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{'type': 'directory', 'path': 'nested'},
        <String, Object?>{'type': 'file', 'path': 'README.md', 'size': 100},
        <String, Object?>{'type': 'file', 'path': 'mmproj-f16.gguf', 'size': 1},
        <String, Object?>{
          'type': 'file',
          'path': 'big-q8_0-00001-of-00009.gguf',
          'size': 2,
        },
        <String, Object?>{
          'type': 'file',
          'path': 'good-q4_k_m.gguf',
          'size': 3,
        },
      ]);

      // Act
      final files = await client.listFiles('a/b');

      // Assert — each of the three rejects would fail at load time, so
      // offering one is offering a model that cannot work.
      check(files.map((f) => f.fileName))
          .deepEquals(<String>['good-q4_k_m.gguf']);
    });

    test('orders the quants smallest first', () async {
      // Arrange
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{'type': 'file', 'path': 'a-q8_0.gguf', 'size': 300},
        <String, Object?>{'type': 'file', 'path': 'a-q2_k.gguf', 'size': 100},
        <String, Object?>{'type': 'file', 'path': 'a-q4_k_m.gguf', 'size': 200},
      ]);

      // Act
      final files = await client.listFiles('a/b');

      // Assert — the device-friendly options come first.
      check(files.map((f) => f.quantization))
          .deepEquals(<String>['Q2_K', 'Q4_K_M', 'Q8_0']);
    });
  });

  group('failures', () {
    test('a rejected token is reported as such', () async {
      // Arrange
      final client = clientReturning(<String, Object?>{}, status: 401);

      // Act / Assert
      await check(client.listModels()).throws<HfApiException>(
        (it) => it.has((e) => e.message, 'message').contains('rejected'),
      );
    });

    test('a rate limit is flagged so the UI can suggest a token', () async {
      // Arrange
      final client = clientReturning(<String, Object?>{}, status: 429);

      // Act / Assert
      await check(client.listModels()).throws<HfApiException>(
        (it) => it.has((e) => e.isRateLimit, 'isRateLimit').isTrue(),
      );
    });

    test('being offline is not reported as a server error', () async {
      // Arrange
      final client = HfApiClient(
        MockClient((_) => throw const SocketException('Failed host lookup')),
      );

      // Act / Assert
      await check(client.listModels()).throws<HfApiException>(
        (it) => it.has((e) => e.message, 'message').contains('No connection'),
      );
    });
  });

  group('auth headers', () {
    test('a token becomes a bearer header', () {
      check(HfApiClient.authHeaders('  hf_abc  '))
          .deepEquals(<String, String>{'Authorization': 'Bearer hf_abc'});
    });

    test('no token sends no header at all', () {
      check(HfApiClient.authHeaders(null)).isEmpty();
      check(HfApiClient.authHeaders('   ')).isEmpty();
    });
  });

  group('quantisation parsing', () {
    // Hugging Face has no field for the quant; it only ever appears in the
    // file name, and every publisher spells it slightly differently.
    const cases = <String, String>{
      'smollm2-360m-instruct-q8_0.gguf': 'Q8_0',
      'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf': 'Q4_K_M',
      'Meta-Llama-3.1-8B-Instruct-IQ3_XS.gguf': 'IQ3_XS',
      'gemma-2-2b-it.F16.gguf': 'F16',
      'phi-3.5-mini-instruct-bf16.gguf': 'BF16',
      'gpt-oss-20b-mxfp4.gguf': 'MXFP4',
      'model.gguf': 'GGUF',
    };

    for (final MapEntry(key: fileName, value: expected) in cases.entries) {
      test('reads $expected out of $fileName', () {
        check(
          GgufFile(
            repoId: 'a/b',
            fileName: fileName,
            sizeBytes: 1,
          ).quantization,
        ).equals(expected);
      });
    }
  });
}

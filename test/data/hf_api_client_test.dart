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

  /// A client that answers every request with [body].
  HfApiClient clientReturning(
    Object body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) => HfApiClient(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(jsonEncode(body), status, request: request);
    }),
  );

  group('repoDetails', () {
    test('asks for exactly the repository it was given', () async {
      Uri? asked;
      final client = clientReturning(<String, Object?>{
        'id': 'a/b',
        'downloads': 10,
        'likes': 2,
      }, onRequest: (request) => asked = request.url);

      await client.repoDetails('bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF');

      // One named repository per call. There is no search any more,
      // which is what keeps this device under the Hub's rate limit.
      check(asked?.path)
          .equals('/api/models/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF');
      check(asked?.queryParameters ?? <String, String>{}).isEmpty();
    });

    test('reads the stats the catalog card shows', () async {
      final client = clientReturning(<String, Object?>{
        'id': 'a/b',
        'downloads': 182000,
        'likes': 412,
        'siblings': <Map<String, Object?>>[
          <String, Object?>{'rfilename': 'a-q4_k_m.gguf'},
          <String, Object?>{'rfilename': 'a-q8_0.gguf'},
        ],
      });

      final summary = await client.repoDetails('a/b');

      check(summary.downloads).equals(182000);
      check(summary.likes).equals(412);
      check(summary.fileCountLabel).equals('2 files');
    });

    test('rejects a response that is not a repository object', () async {
      // The Hub answers an unknown path with a list or a string.
      final client = clientReturning(<Object?>[]);

      await check(client.repoDetails('a/b')).throws<HfApiException>();
    });
  });

  group('listFiles', () {
    test('prefers the LFS size over the pointer size', () async {
      // `size` is the 134-byte pointer; `lfs.size` is the payload.
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'path': 'model-q4_k_m.gguf',
          'size': 134,
          'lfs': <String, Object?>{'size': 1100000000},
        },
      ]);

      final files = await client.listFiles('a/b');

      check(files.single.sizeBytes).equals(1100000000);
      check(files.single.sizeLabel).equals('1.10 GB');
    });

    test('falls back to size when the file is not in LFS', () async {
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'path': 'tiny-q2_k.gguf',
          'size': 2000000,
        },
      ]);

      final files = await client.listFiles('a/b');

      check(files.single.sizeBytes).equals(2000000);
    });

    test('drops directories, non-GGUF files and split shards', () async {
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{'type': 'directory', 'path': 'nested'},
        <String, Object?>{'type': 'file', 'path': 'README.md', 'size': 100},
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

      final files = await client.listFiles('a/b');

      // One shard of a split model always fails inside the loader,
      // and there is no multi-file download flow to complete it.
      check(files.map((f) => f.fileName))
          .deepEquals(<String>['good-q4_k_m.gguf']);
    });

    test('keeps projectors and adapters, classified by kind', () async {
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{'type': 'file', 'path': 'a-q4_k_m.gguf', 'size': 300},
        <String, Object?>{'type': 'file', 'path': 'mmproj-f16.gguf', 'size': 1},
        <String, Object?>{
          'type': 'file',
          'path': 'a-lora-writing.gguf',
          'size': 2,
        },
      ]);

      final files = await client.listFiles('a/b');

      // The model sheet lists these for reference, so dropping them
      // would leave a vision repo looking like it ships no projector at all.
      check(files.map((f) => f.kind)).deepEquals(<GgufFileKind>[
        GgufFileKind.model,
        GgufFileKind.mmproj,
        GgufFileKind.adapter,
      ]);
    });

    test('orders the quants smallest first', () async {
      final client = clientReturning(<Map<String, Object?>>[
        <String, Object?>{'type': 'file', 'path': 'a-q8_0.gguf', 'size': 300},
        <String, Object?>{'type': 'file', 'path': 'a-q2_k.gguf', 'size': 100},
        <String, Object?>{'type': 'file', 'path': 'a-q4_k_m.gguf', 'size': 200},
      ]);

      final files = await client.listFiles('a/b');

      // The device-friendly options come first.
      check(files.map((f) => f.quantization))
          .deepEquals(<String>['Q2_K', 'Q4_K_M', 'Q8_0']);
    });
  });

  group('failures', () {
    test('a rejected token is reported as such', () async {
      final client = clientReturning(<String, Object?>{}, status: 401);

      await check(client.repoDetails('a/b')).throws<HfApiException>(
        (it) => it.has((e) => e.message, 'message').contains('rejected'),
      );
    });

    test('a rate limit is flagged so the UI can suggest a token', () async {
      final client = clientReturning(<String, Object?>{}, status: 429);

      await check(client.repoDetails('a/b')).throws<HfApiException>(
        (it) => it.has((e) => e.isRateLimit, 'isRateLimit').isTrue(),
      );
    });

    test('being offline is not reported as a server error', () async {
      final client = HfApiClient(
        MockClient((_) => throw const SocketException('Failed host lookup')),
      );

      await check(client.repoDetails('a/b')).throws<HfApiException>(
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

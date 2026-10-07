import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/repositories/hugging_face_repository.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';
import 'package:model_scope_flutter/domain/services/api_key_verifier.dart';

void main() {
  /// A verifier whose three services all answer out of [bodies], keyed by the
  /// path asked for, and which records every address it was sent to.
  ({ApiKeyVerifier verifier, List<String> paths}) verifierFor(
    Map<String, Object?> bodies, {
    int status = 200,
  }) {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
        jsonEncode(bodies[request.url.path] ?? <String, Object?>{}),
        status,
        request: request,
      );
    });

    return (
      verifier: ApiKeyVerifier(
        HuggingFaceRepository(HfApiClient(client), () async => null),
        TavilyApiClient(client),
        FirecrawlApiClient(client),
      ),
      paths: paths,
    );
  }

  const Map<String, Object?> goodKeys = <String, Object?>{
    '/api/whoami-v2': <String, Object?>{'name': 'octocat'},
    '/usage': <String, Object?>{
      'key': <String, Object?>{'usage': 412, 'limit': 4000},
      'account': <String, Object?>{'current_plan': 'Bootstrap'},
    },
    '/v2/team/credit-usage': <String, Object?>{
      'success': true,
      'data': <String, Object?>{'remainingCredits': 3588},
    },
  };

  test('a Hugging Face token reports the account it belongs to', () async {
    final (:verifier, :paths) = verifierFor(goodKeys);

    final summary = await verifier.verify(ApiKeyKind.huggingFace, 'hf_x');

    check(summary).equals('Verified as octocat');
    check(paths).deepEquals(<String>['/api/whoami-v2']);
  });

  test('a Tavily key reports its plan and spend', () async {
    final (:verifier, :paths) = verifierFor(goodKeys);

    final summary = await verifier.verify(ApiKeyKind.tavily, 'tvly-x');

    check(summary)
        .equals('Verified · Bootstrap plan · 412 of 4000 credits used');
    // The point of the whole exercise: no search was run to check the key.
    check(paths).deepEquals(<String>['/usage']);
  });

  test('a Firecrawl key reports what is left on it', () async {
    final (:verifier, :paths) = verifierFor(goodKeys);

    final summary = await verifier.verify(ApiKeyKind.firecrawl, 'fc-x');

    check(summary).equals('Verified · 3588 credits left');
    // Likewise: no page was scraped to check the key.
    check(paths).deepEquals(<String>['/v2/team/credit-usage']);
  });

  test('one credit left is not "1 credits"', () async {
    final (:verifier, paths: _) = verifierFor(<String, Object?>{
      '/v2/team/credit-usage': <String, Object?>{
        'success': true,
        'data': <String, Object?>{'remainingCredits': 1},
      },
    });

    check(await verifier.verify(ApiKeyKind.firecrawl, 'fc-x'))
        .equals('Verified · 1 credit left');
  });

  test('an uncapped Tavily plan is not reported as a fraction', () async {
    final (:verifier, paths: _) = verifierFor(<String, Object?>{
      '/usage': <String, Object?>{
        'key': <String, Object?>{'usage': 7, 'limit': null},
        'account': <String, Object?>{'current_plan': 'Enterprise'},
      },
    });

    check(await verifier.verify(ApiKeyKind.tavily, 'tvly-x'))
        .equals('Verified · Enterprise plan · 7 credits used');
  });

  test('a rejected key throws the service\'s own sentence', () async {
    final (:verifier, paths: _) = verifierFor(goodKeys, status: 401);

    await check(verifier.verify(ApiKeyKind.tavily, 'bad'))
        .throws<TavilyApiException>(
          (it) => it.has((e) => e.message, 'message').contains('Settings'),
        );
  });
}

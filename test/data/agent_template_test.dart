import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';

void main() {
  /// A template with every field set, as a hand-written one would be.
  Map<String, Object?> fullTemplate() => <String, Object?>{
    'schema_version': 1,
    'id': 'price_comparison',
    'name': 'Price Comparison',
    'purpose': 'Compare prices across retailers',
    'description': 'Searches, scrapes and ranks.',
    'icon': 'tag',
    'system_prompt': 'You are careful.',
    'inputs': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'product',
        'label': 'Product name',
        'type': 'text',
        'default': 'WH-1000XM5',
        'required': true,
      },
      <String, Object?>{
        'name': 'region',
        'label': 'Region',
        'type': 'choice',
        'options': <String>['IN', 'US'],
        'default': 'IN',
      },
    ],
    'pipeline': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'search',
        'kind': 'tool',
        'tool': 'web_search',
        'reads': <String>['input.product'],
        'prompt': 'Search for {{input.product}}.',
        'model': null,
      },
      <String, Object?>{
        'id': 'rank',
        'kind': 'reason',
        'reads': <String>['step.search'],
        'prompt': 'Rank them.',
      },
    ],
    'answer': <String, Object?>{
      'prompt': 'Write it up.',
      'reads': <String>['step.rank'],
    },
  };

  group('parsing', () {
    test('reads every field a hand-written template sets', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(template.id).equals('price_comparison');
      check(template.name).equals('Price Comparison');
      check(template.icon).equals('tag');
      check(template.systemPrompt).equals('You are careful.');
      check(template.inputs).length.equals(2);
      check(template.pipeline).length.equals(2);
      check(template.answer.prompt).equals('Write it up.');
    });

    test('reads the two step kinds', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(template.pipeline.first.kind).equals(StepKind.tool);
      check(template.pipeline.first.tool).equals('web_search');
      check(template.pipeline.last.kind).equals(StepKind.reason);
      check(template.pipeline.last.tool).isNull();
    });

    test('reads the input types, including the choices', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(template.inputs.first.type).equals(AgentInputType.text);
      check(template.inputs.last.type).equals(AgentInputType.choice);
      check(template.inputs.last.options).deepEquals(<String>['IN', 'US']);
      check(template.inputs.last.required).isTrue();
    });

    test('fills in what an agent built in the app leaves out', () {
      final template = AgentTemplate.fromJson(<String, Object?>{
        'id': 'bare',
        'name': 'Bare',
        'purpose': 'p',
        'system_prompt': 's',
        'pipeline': <Map<String, Object?>>[],
        'answer': <String, Object?>{'prompt': 'Answer.'},
      });

      check(template.schemaVersion).equals(1);
      check(template.description).equals('');
      check(template.icon).equals('robot');
      check(template.inputs).isEmpty();
      check(template.answer.reads).isEmpty();
      check(template.createdAt).isNull();
    });

    test('an unknown step kind throws rather than defaulting', () {
      final broken = fullTemplate();
      (broken['pipeline'] as List<Map<String, Object?>>).first['kind'] =
          'parallel';

      // A kind this build cannot run must not quietly become a reason step:
      // the agent would appear to work and do the wrong thing.
      check(() => AgentTemplate.fromJson(broken)).throws<Object>();
    });

    test('an unknown input type throws', () {
      final broken = fullTemplate();
      (broken['inputs'] as List<Map<String, Object?>>).first['type'] = 'audio';

      check(() => AgentTemplate.fromJson(broken)).throws<Object>();
    });

    test('a missing pipeline throws', () {
      final broken = fullTemplate()..remove('pipeline');

      check(() => AgentTemplate.fromJson(broken)).throws<Object>();
    });

    test('a missing answer throws', () {
      final broken = fullTemplate()..remove('answer');

      check(() => AgentTemplate.fromJson(broken)).throws<Object>();
    });
  });

  group('writing back', () {
    test('a template survives a round trip through JSON', () {
      final original = AgentTemplate.fromJson(fullTemplate());

      // What a custom agent does every time it is saved and reopened.
      final reparsed = AgentTemplate.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      check(reparsed.id).equals(original.id);
      check(reparsed.pipeline.first.tool).equals('web_search');
      check(reparsed.pipeline.last.reads).deepEquals(<String>['step.search']);
      check(reparsed.inputs.last.options).deepEquals(<String>['IN', 'US']);
      check(reparsed.answer.reads).deepEquals(<String>['step.rank']);
    });

    test('a created date survives, since a built-in has none', () {
      final template = AgentTemplate(
        id: 'mine',
        name: 'Mine',
        purpose: 'p',
        systemPrompt: 's',
        pipeline: const <PipelineStep>[],
        answer: const AnswerStep(prompt: 'Answer.'),
        createdAt: DateTime(2026, 10, 6, 9, 30),
      );

      final reparsed = AgentTemplate.fromJson(
        jsonDecode(jsonEncode(template.toJson())) as Map<String, dynamic>,
      );

      check(reparsed.createdAt).equals(DateTime(2026, 10, 6, 9, 30));
    });
  });

  group('what the card shows', () {
    test('lists the tools once each, in pipeline order', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(template.toolNames).deepEquals(<String>['web_search']);
    });

    test('counts the answer as a step', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(template.stepCount).equals(3);
    });

    test('collects the defaults Run with defaults sends', () {
      final template = AgentTemplate.fromJson(fullTemplate());

      check(
        template.defaultValues,
      ).deepEquals(<String, String>{'product': 'WH-1000XM5', 'region': 'IN'});
    });

    test('an input with no default is left out of them', () {
      final template = AgentTemplate.fromJson(<String, Object?>{
        'id': 'a',
        'name': 'A',
        'purpose': 'p',
        'system_prompt': 's',
        'inputs': <Map<String, Object?>>[
          <String, Object?>{'name': 'q', 'label': 'Q'},
        ],
        'pipeline': <Map<String, Object?>>[],
        'answer': <String, Object?>{'prompt': 'Answer.'},
      });

      check(template.defaultValues).isEmpty();
      check(template.inputNamed('q')).isNotNull();
      check(template.inputNamed('gone')).isNull();
    });
  });
}

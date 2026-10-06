import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/agent_scope.dart';

void main() {
  AgentScope scopeOf({
    Map<String, String> inputs = const <String, String>{},
    Map<String, String> steps = const <String, String>{},
  }) {
    final scope = AgentScope(inputs: inputs);
    steps.forEach(scope.record);
    return scope;
  }

  group('resolve', () {
    test('reads an input and a finished step', () {
      final scope = scopeOf(
        inputs: <String, String>{'query': 'dart records'},
        steps: <String, String>{'search': 'two results'},
      );

      check(scope.resolve('input.query')).equals('dart records');
      check(scope.resolve('step.search')).equals('two results');
    });

    test('answers null for something that does not exist', () {
      final scope = scopeOf(inputs: <String, String>{'query': 'x'});

      // Null rather than empty, so a caller can tell a template naming
      // something that is not there from a step that produced nothing.
      check(scope.resolve('input.missing')).isNull();
      check(scope.resolve('step.missing')).isNull();
      check(scope.resolve('nonsense.query')).isNull();
      check(scope.resolve('query')).isNull();
    });

    test('a step that ran but said nothing is empty, not missing', () {
      final scope = scopeOf(steps: <String, String>{'search': ''});

      check(scope.resolve('step.search')).equals('');
    });
  });

  group('labelFor', () {
    test('turns a reference into something a person would read', () {
      check(AgentScope.labelFor('input.product_name')).equals('Product Name');
      check(AgentScope.labelFor('step.search')).equals('Result of Search');
    });
  });

  group('renderTemplate', () {
    test('substitutes every placeholder', () {
      final scope = scopeOf(
        inputs: <String, String>{'product': 'WH-1000XM5', 'region': 'IN'},
      );

      check(
        renderTemplate('Find {{input.product}} in {{input.region}}.', scope),
      ).equals('Find WH-1000XM5 in IN.');
    });

    test('tolerates spaces inside the braces', () {
      final scope = scopeOf(inputs: <String, String>{'q': 'x'});

      check(renderTemplate('{{ input.q }}', scope)).equals('x');
    });

    test('an unresolved placeholder becomes nothing, not braces', () {
      final scope = scopeOf();

      // Left as `{{...}}` the model reads the braces as content and sometimes
      // copies them into its answer.
      check(renderTemplate('A {{input.gone}} B', scope)).equals('A  B');
    });

    test('leaves text with no placeholders alone', () {
      check(renderTemplate('Just a sentence.', scopeOf()))
          .equals('Just a sentence.');
    });
  });

  group('referencesIn', () {
    test('lists what a prompt names, in order', () {
      check(referencesIn('{{step.a}} then {{input.b}} then {{step.a}}'))
          .deepEquals(<String>['step.a', 'input.b', 'step.a']);
    });

    test('finds none in plain text', () {
      check(referencesIn('nothing here')).isEmpty();
    });
  });

  group('buildStepPrompt', () {
    test('puts the context first and the instruction last', () {
      final scope = scopeOf(steps: <String, String>{'search': 'two results'});

      final prompt = buildStepPrompt(
        instruction: 'List the main points.',
        reads: <String>['step.search'],
        scope: scope,
      );

      // A small model follows the last thing it read. Four thousand characters
      // of scraped page between the instruction and the end of the prompt is
      // how an agent ends up summarising the page instead of doing the job.
      check(prompt)
          .equals('Result of Search:\ntwo results\n\nList the main points.');
    });

    test('renders placeholders in the instruction too', () {
      final scope = scopeOf(inputs: <String, String>{'topic': 'records'});

      check(
        buildStepPrompt(
          instruction: 'Search for {{input.topic}}.',
          reads: const <String>[],
          scope: scope,
        ),
      ).equals('Search for records.');
    });

    test('skips a reference that resolved to nothing', () {
      final scope = scopeOf(steps: <String, String>{'a': 'kept', 'b': '   '});

      final prompt = buildStepPrompt(
        instruction: 'Go.',
        reads: <String>['step.a', 'step.b', 'step.missing'],
        scope: scope,
      );

      check(prompt).equals('Result of A:\nkept\n\nGo.');
    });

    test('is just the instruction when there is nothing to read', () {
      check(
        buildStepPrompt(
          instruction: 'Go.',
          reads: const <String>[],
          scope: scopeOf(),
        ),
      ).equals('Go.');
    });
  });
}

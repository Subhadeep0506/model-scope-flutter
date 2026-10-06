import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/domain/services/agent_validator.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/tool_registry.dart';

void main() {
  ToolDefinition toolNamed(String name) => ToolDefinition(
    name: name,
    description: 'Does nothing, for a test.',
    function: ({required String input}) async => 'ok',
  );

  /// A registry with one ready tool and one gated behind a key that is not
  /// set, which is the ordinary state of a fresh install.
  ToolRegistry registry({bool keySet = true}) => ToolRegistry(
    tools: <ToolDefinition>[toolNamed('web_search'), toolNamed('calculator')],
    readiness: <String, Future<bool> Function()>{
      'web_search': () async => keySet,
    },
    blockers: const <String, String>{
      'web_search': 'Needs Tavily key — set it in Settings',
    },
  );

  AgentTemplate templateOf({
    List<AgentInput> inputs = const <AgentInput>[],
    required List<PipelineStep> pipeline,
    AnswerStep answer = const AnswerStep(prompt: 'Write it up.'),
  }) => AgentTemplate(
    id: 'a',
    name: 'A',
    purpose: 'p',
    systemPrompt: 's',
    inputs: inputs,
    pipeline: pipeline,
    answer: answer,
  );

  const PipelineStep searchStep = PipelineStep(
    id: 'search',
    kind: StepKind.tool,
    tool: 'web_search',
    prompt: 'Search.',
  );

  group('structure', () {
    test('a sound template has nothing wrong with it', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(pipeline: const <PipelineStep>[searchStep]),
      );

      check(problems).isEmpty();
    });

    test('a tool this build does not have is named', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(id: 's', kind: StepKind.tool, tool: 'pdf_parse'),
          ],
        ),
      );

      check(problems.single).equals('"pdf_parse" is not a tool in this build');
    });

    test('a tool step naming no tool is caught', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(id: 's', kind: StepKind.tool),
          ],
        ),
      );

      check(problems.single).contains('names no tool');
    });

    test('a reason step with nothing to think about is caught', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(id: 's', kind: StepKind.reason, prompt: '   '),
          ],
        ),
      );

      check(problems.single).contains('nothing to reason about');
    });

    test('two steps sharing an id are caught', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(pipeline: const <PipelineStep>[searchStep, searchStep]),
      );

      check(problems.single).contains('share the id "search"');
    });

    test('an agent with no steps is caught', () {
      final problems = AgentValidator(registry())
          .structuralProblems(templateOf(pipeline: const <PipelineStep>[]));

      check(problems).contains('This agent has no steps');
    });
  });

  group('references', () {
    test('a step may read an input and an earlier step', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          inputs: const <AgentInput>[AgentInput(name: 'q', label: 'Q')],
          pipeline: const <PipelineStep>[
            searchStep,
            PipelineStep(
              id: 'points',
              kind: StepKind.reason,
              prompt: 'Think about {{input.q}}.',
              reads: <String>['step.search'],
            ),
          ],
        ),
      );

      check(problems).isEmpty();
    });

    test('reading a step that has not run yet is caught', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(
              id: 'first',
              kind: StepKind.reason,
              prompt: 'Think.',
              reads: <String>['step.second'],
            ),
            PipelineStep(id: 'second', kind: StepKind.reason, prompt: 'Think.'),
          ],
        ),
      );

      // Forward references are what would make a pipeline a graph. This check
      // is what keeps it a pipeline.
      check(problems.single).contains('"step.second"');
    });

    test('a step cannot read itself', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(
              id: 'loop',
              kind: StepKind.reason,
              prompt: 'Think.',
              reads: <String>['step.loop'],
            ),
          ],
        ),
      );

      check(problems.single).contains('"step.loop"');
    });

    test('an input that was never declared is caught', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(
              id: 's',
              kind: StepKind.reason,
              prompt: 'About {{input.nothere}}.',
            ),
          ],
        ),
      );

      check(problems.single).contains('"input.nothere"');
    });

    test('the answer step is checked too', () {
      final problems = AgentValidator(registry()).structuralProblems(
        templateOf(
          pipeline: const <PipelineStep>[searchStep],
          answer: const AnswerStep(
            prompt: 'Write it.',
            reads: <String>['step.gone'],
          ),
        ),
      );

      check(problems.single).contains('The answer step');
    });
  });

  group('readiness', () {
    test('a sound agent with its key set can run', () async {
      final availability = await AgentValidator(registry()).check(
        templateOf(pipeline: const <PipelineStep>[searchStep]),
        hasModel: true,
      );

      check(availability.canRun).isTrue();
      check(availability.firstBlocker).isNull();
    });

    test('a missing key is reported in the words the design uses', () async {
      final availability = await AgentValidator(registry(keySet: false)).check(
        templateOf(pipeline: const <PipelineStep>[searchStep]),
        hasModel: true,
      );

      check(availability.canRun).isFalse();
      check(availability.firstBlocker)
          .equals('Needs Tavily key — set it in Settings');
    });

    test('a tool needing no key is always ready', () async {
      final availability = await AgentValidator(registry(keySet: false)).check(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(id: 'c', kind: StepKind.tool, tool: 'calculator'),
          ],
        ),
        hasModel: true,
      );

      check(availability.canRun).isTrue();
    });

    test('no model installed blocks the run first', () async {
      final availability = await AgentValidator(registry()).check(
        templateOf(pipeline: const <PipelineStep>[searchStep]),
        hasModel: false,
      );

      check(availability.firstBlocker)
          .isNotNull()
          .contains('No model installed');
    });

    test('a required input left empty blocks the run', () async {
      final availability = await AgentValidator(registry()).check(
        templateOf(
          inputs: const <AgentInput>[AgentInput(name: 'q', label: 'Query')],
          pipeline: const <PipelineStep>[searchStep],
        ),
        hasModel: true,
      );

      check(availability.firstBlocker).equals('Query needs a value');
    });

    test('an optional input left empty does not', () async {
      final availability = await AgentValidator(registry()).check(
        templateOf(
          inputs: const <AgentInput>[
            AgentInput(name: 'q', label: 'Query', required: false),
          ],
          pipeline: const <PipelineStep>[searchStep],
        ),
        hasModel: true,
      );

      check(availability.canRun).isTrue();
    });

    test('a broken template is not also nagged about keys', () async {
      final availability = await AgentValidator(registry(keySet: false)).check(
        templateOf(
          pipeline: const <PipelineStep>[
            PipelineStep(id: 's', kind: StepKind.tool, tool: 'pdf_parse'),
          ],
        ),
        hasModel: true,
      );

      // A key warning on top of a tool that does not exist is noise.
      check(availability.blockers).length.equals(1);
      check(availability.blockers.single).contains('pdf_parse');
    });
  });
}

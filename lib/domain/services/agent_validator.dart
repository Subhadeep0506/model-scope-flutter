import '../../data/models/agent_template.dart';
import '../tools/tool_registry.dart';
import 'agent_scope.dart';

/// Whether an agent can run, and what stops it if not.
class AgentAvailability {
  const AgentAvailability(this.blockers);

  const AgentAvailability.ready() : blockers = const <String>[];

  /// One line per problem, each written to be shown as-is.
  final List<String> blockers;

  bool get canRun => blockers.isEmpty;

  /// The first problem, which is the one the card has room for.
  String? get firstBlocker => blockers.isEmpty ? null : blockers.first;
}

class AgentValidator {
  const AgentValidator(this._tools);
  final ToolRegistry _tools;

  List<String> structuralProblems(AgentTemplate template) {
    final problems = <String>[
      ..._pipelineShape(template),
      ..._referenceProblems(template),
    ];
    for (final step in template.pipeline) {
      problems.addAll(_stepProblems(step));
    }
    return problems;
  }

  Future<AgentAvailability> check(
    AgentTemplate template, {
    required bool hasModel,
    Map<String, String> values = const <String, String>{},
  }) async {
    final blockers = <String>[
      if (!hasModel) 'No model installed — download one in Settings',
      ...structuralProblems(template),
      ..._missingInputs(template, values),
    ];

    if (blockers.isEmpty) {
      for (final name in template.toolNames) {
        final blocker = await _tools.blockerFor(name);
        if (blocker != null && !blockers.contains(blocker)) {
          blockers.add(blocker);
        }
      }
    }
    return AgentAvailability(blockers);
  }

  List<String> _pipelineShape(AgentTemplate template) {
    final problems = <String>[];
    if (template.pipeline.isEmpty) {
      problems.add('This agent has no steps');
    }
    if (template.answer.prompt.trim().isEmpty) {
      problems.add('The answer step has no instruction');
    }

    final seen = <String>{};
    for (final step in template.pipeline) {
      if (step.id.trim().isEmpty) {
        problems.add('A step has no id');
      } else if (!seen.add(step.id)) {
        problems.add('Two steps share the id "${step.id}"');
      }
    }
    return problems;
  }

  List<String> _stepProblems(PipelineStep step) {
    final tool = step.tool;
    return switch (step.kind) {
      StepKind.tool when tool == null || tool.isEmpty => <String>[
        'Step "${step.id}" is a tool step but names no tool',
      ],
      StepKind.tool when !_tools.has(tool ?? '') => <String>[
        '"$tool" is not a tool in this build',
      ],
      StepKind.reason when (step.prompt ?? '').trim().isEmpty => <String>[
        'Step "${step.id}" has nothing to reason about',
      ],
      _ => const <String>[],
    };
  }

  List<String> _referenceProblems(AgentTemplate template) {
    final problems = <String>[];
    final available = <String>{
      for (final input in template.inputs) 'input.${input.name}',
    };

    for (final step in template.pipeline) {
      problems.addAll(
        _unknownReferences(
          _referencesOf(step.reads, step.prompt),
          available,
          'Step "${step.id}"',
        ),
      );
      available.add('step.${step.id}');
    }

    problems.addAll(
      _unknownReferences(
        _referencesOf(template.answer.reads, template.answer.prompt),
        available,
        'The answer step',
      ),
    );
    return problems;
  }

  static List<String> _referencesOf(List<String> reads, String? prompt) =>
      <String>[...reads, ...referencesIn(prompt ?? '')];

  static List<String> _unknownReferences(
    List<String> references,
    Set<String> available,
    String who,
  ) => <String>[
    for (final reference in references)
      if (!available.contains(reference))
        '$who reads "$reference", which nothing before it produces',
  ];

  List<String> _missingInputs(
    AgentTemplate template,
    Map<String, String> values,
  ) => <String>[
    for (final input in template.inputs)
      if (input.required && (values[input.name] ?? '').trim().isEmpty)
        '${input.label} needs a value',
  ];
}

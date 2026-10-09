import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/presentation/view_models/agent_builder_state.dart';
import 'package:model_scope_flutter/presentation/view_models/agent_builder_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAgentRepository agents;

  ProviderContainer containerWith({List<Agent>? seed}) {
    agents = FakeAgentRepository(
      seed ?? <Agent>[Agent(template: fakeAgentTemplate(), isBuiltIn: true)],
    );
    return ProviderContainer.test(
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(),
        agents: agents,
      ),
    );
  }

  AgentBuilderViewModel notifierOf(ProviderContainer c) =>
      c.read(agentBuilderViewModelProvider.notifier);

  AgentDraft draftOf(ProviderContainer c) =>
      c.read(agentBuilderViewModelProvider).value ?? AgentDraft();

  /// Fills in everything an agent needs to validate, so a test about one
  /// thing is not rejected for the other four. The step is there because the
  /// validator refuses an agent with an empty pipeline.
  void fillBasics(ProviderContainer container) {
    final vm = notifierOf(container);
    vm.setName('News digest');
    vm.setPurpose('Summarises the news');
    vm.setSystemPrompt('You are careful.');
    vm.setAnswerPrompt('Write the digest.');

    vm.addStep();
    final key = draftOf(container).steps.last.key;
    vm.setStepKind(key, StepKind.reason);
    vm.setStepPrompt(key, 'Think about the news.');
  }

  group('slugify', () {
    test('turns a name into something safe for a file and a prompt', () {
      check(slugify('News digest')).equals('news_digest');
      check(slugify('  Price / Comparison!  ')).equals('price_comparison');
      check(slugify('Agent 2')).equals('agent_2');
      check(slugify('—')).isEmpty();
    });
  });

  group('creating', () {
    test('starts empty', () async {
      final container = containerWith();
      await notifierOf(container).open(agentId: null, duplicate: false);

      final draft = draftOf(container);
      check(draft.isExisting).isFalse();
      check(draft.name).isEmpty();
      check(draft.steps).isEmpty();
      check(notifierOf(container).mode).equals(BuilderMode.create);
    });

    test('the id is minted from the name on the first save', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);

      final outcome = await vm.save();

      check(outcome)
          .isA<SaveSucceeded>()
          .has((o) => o.id, 'id')
          .equals('news_digest');
      check(agents.saved.single.id).equals('news_digest');
    });

    test('a clashing id gets a suffix rather than overwriting', () async {
      final container = containerWith(
        seed: <Agent>[
          Agent(
            template: fakeAgentTemplate(id: 'news_digest'),
            isBuiltIn: true,
          ),
        ],
      );
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);

      await vm.save();

      check(agents.saved.single.id).equals('news_digest_2');
    });

    test('renaming after a save does not move the file', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      await vm.save();

      vm.setName('Something else entirely');
      await vm.save();

      // Two writes, one id: an agent's file and its run history are keyed by
      // the id, and renaming must not orphan either.
      check(agents.saved).length.equals(2);
      check(agents.saved.last.id).equals('news_digest');
      check(agents.saved.last.name).equals('Something else entirely');
    });
  });

  group('editing', () {
    test('loads an existing agent and keeps its id', () async {
      final container = containerWith(
        seed: <Agent>[
          Agent(template: fakeAgentTemplate(id: 'mine'), isBuiltIn: false),
        ],
      );
      final vm = notifierOf(container);

      await vm.open(agentId: 'mine', duplicate: false);

      check(vm.mode).equals(BuilderMode.edit);
      check(draftOf(container).id).equals('mine');
      check(draftOf(container).name).equals('Test Agent');
    });

    test('an agent that is gone reports rather than opening blank', () async {
      final container = containerWith();
      await notifierOf(container).open(agentId: 'nope', duplicate: false);

      check(container.read(agentBuilderViewModelProvider)).isA<AsyncError>();
    });

    test('a built-in is saved under its own id, shadowing it', () async {
      final container = containerWith(
        seed: <Agent>[
          Agent(template: fakeAgentTemplate(id: 'web_answer'), isBuiltIn: true),
        ],
      );
      final vm = notifierOf(container);

      await vm.open(agentId: 'web_answer', duplicate: false);
      vm.setName('My web answer');
      await vm.save();

      // Not a copy under a minted id: the same id, so the card, the name and
      // the run history stay where they are and the user's version is what
      // runs.
      check(vm.mode).equals(BuilderMode.edit);
      check(agents.saved.single.id).equals('web_answer');
      check(agents.saved.single.name).equals('My web answer');
    });

    test(
      'editing a built-in offers a reset, editing your own does not',
      () async {
        final container = containerWith(
          seed: <Agent>[
            Agent(template: fakeAgentTemplate(id: 'shipped'), isBuiltIn: true),
            Agent(template: fakeAgentTemplate(id: 'mine'), isBuiltIn: false),
          ],
        );
        final vm = notifierOf(container);

        await vm.open(agentId: 'shipped', duplicate: false);
        check(vm.isBuiltInOverride).isTrue();

        await vm.open(agentId: 'mine', duplicate: false);
        check(vm.isBuiltInOverride).isFalse();

        // A copy of a built-in is a new agent, not an override of one.
        await vm.open(agentId: 'shipped', duplicate: true);
        check(vm.isBuiltInOverride).isFalse();
      },
    );

    test(
      'resetting removes the file, so the bundled one loads again',
      () async {
        final container = containerWith(
          seed: <Agent>[
            Agent(
              template: fakeAgentTemplate(id: 'web_answer'),
              isBuiltIn: true,
              isEdited: true,
            ),
          ],
        );
        final vm = notifierOf(container);
        await vm.open(agentId: 'web_answer', duplicate: false);

        await vm.reset();

        // Nothing can touch the bundle, so dropping the override is the whole
        // of putting the shipped agent back.
        check(agents.deleted).deepEquals(<String>['web_answer']);
      },
    );
  });

  group('duplicating', () {
    test('mints a new id, so the original stays where it is', () async {
      final container = containerWith(
        seed: <Agent>[
          Agent(
            template: fakeAgentTemplate(id: 'price_comparison'),
            isBuiltIn: true,
          ),
        ],
      );
      final vm = notifierOf(container);

      await vm.open(agentId: 'price_comparison', duplicate: true);

      check(vm.mode).equals(BuilderMode.duplicate);
      check(draftOf(container).name).equals('Test Agent copy');

      await vm.save();

      check(agents.saved.single.id).equals('test_agent_copy');
      // Saved once, it is simply the agent being edited.
      check(vm.mode).equals(BuilderMode.edit);
    });
  });

  group('inputs', () {
    test('the name follows the label until the name is set by hand', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addInput();
      final key = draftOf(container).inputs.single.key;

      vm.setInputLabel(key, 'Search query');
      check(draftOf(container).inputs.single.name).equals('search_query');

      vm.setInputName(key, 'topic');
      vm.setInputLabel(key, 'Something else');
      // Edited by hand, so it stops following.
      check(draftOf(container).inputs.single.name).equals('topic');
    });

    test('renaming an input rewrites what reads it', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addInput();
      final key = draftOf(container).inputs.single.key;
      vm.setInputLabel(key, 'Query');
      vm.addStep();
      final step = draftOf(container).steps.single.key;
      vm.toggleStepRead(step, 'input.query');
      vm.setStepPrompt(step, 'Search for {{input.query}}.');

      vm.setInputName(key, 'topic');

      // Otherwise the step would be reading something that no longer exists,
      // which the validator reports but the user never asked for.
      check(draftOf(container).steps.single.reads)
          .deepEquals(<String>['input.topic']);
      check(draftOf(container).steps.single.prompt).contains('{{input.topic}}');
    });

    test('choosing Choice offers an option to fill in', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addInput();
      final key = draftOf(container).inputs.single.key;

      vm.setInputType(key, AgentInputType.choice);

      // A choice with no options is a blocker, so the editor starts with one.
      check(draftOf(container).inputs.single.options).length.equals(1);
    });

    test('a choice with no options is refused on save', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.addInput();
      final key = draftOf(container).inputs.single.key;
      vm.setInputLabel(key, 'Units');
      vm.setInputType(key, AgentInputType.choice);

      final outcome = await vm.save();

      check(outcome).isA<SaveRejected>();
      check(agents.saved).isEmpty();
    });
  });

  group('steps', () {
    test('a new step gets an id nothing else is using', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);

      vm.addStep();
      vm.addStep();

      check(draftOf(container).steps.map((s) => s.id).toList())
          .deepEquals(<String>['step_1', 'step_2']);
    });

    test('duplicating a step does not duplicate its id', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addStep();

      vm.duplicateStep(draftOf(container).steps.single.key);

      final ids = draftOf(container).steps.map((s) => s.id).toSet();
      check(ids).length.equals(2);
    });

    test('a step may only read what runs before it', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addInput();
      vm.setInputLabel(draftOf(container).inputs.single.key, 'Query');
      vm.addStep();
      vm.addStep();

      final first = draftOf(container).referencesBefore(0);
      final second = draftOf(container).referencesBefore(1);

      check(first.map((r) => r.reference).toList())
          .deepEquals(<String>['input.query']);
      check(second.map((r) => r.reference).toList())
          .deepEquals(<String>['input.query', 'step.step_1']);
    });

    test('moving a step drops a read that is now in its future', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addStep();
      vm.addStep();
      final second = draftOf(container).steps.last.key;
      vm.toggleStepRead(second, 'step.step_1');

      vm.moveStep(second, -1);

      // It now runs first, so it cannot read what used to come before it.
      check(draftOf(container).steps.first.reads).isEmpty();
    });

    test('deleting a step unhooks whatever read it', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addStep();
      vm.addStep();
      final first = draftOf(container).steps.first.key;
      vm.toggleStepRead(draftOf(container).steps.last.key, 'step.step_1');

      vm.removeStep(first);

      check(draftOf(container).steps.single.reads).isEmpty();
    });

    test('a tool step with no tool is refused on save', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.addStep();

      final outcome = await vm.save();

      check(outcome)
          .isA<SaveRejected>()
          .has((o) => o.problems.join(' '), 'problems')
          .contains('names no tool');
    });

    test('switching to Reason drops the tool it was holding', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.addStep();
      final key = draftOf(container).steps.last.key;
      vm.setStepTool(key, 'web_search');
      vm.setStepKind(key, StepKind.reason);
      vm.setStepPrompt(key, 'Think about it.');

      await vm.save();

      // A tool left over from the toggle would make the runner hand the model
      // a tool on a step meant to have none.
      check(agents.saved.single.pipeline.last.tool).isNull();
    });
  });

  group('the structured response', () {
    test('turning it on offers a field to fill in', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);

      vm.setStructured(true);

      check(draftOf(container).answer.fields).length.equals(1);
    });

    test('a schema with no named fields is refused', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.setStructured(true);

      final outcome = await vm.save();

      check(outcome)
          .isA<SaveRejected>()
          .has((o) => o.problems.join(' '), 'problems')
          .contains('no fields');
    });

    test('a schema the rows can draw becomes rows', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.setStructured(true);

      vm.setRawSchema(<String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'winner': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['winner'],
      });

      check(draftOf(container).answer.rawSchema).isNull();
      check(draftOf(container).answer.fields.single.name).equals('winner');
    });

    test('a schema the rows cannot draw is kept as written', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.setStructured(true);

      const Map<String, dynamic> exotic = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'units': <String, dynamic>{
            'type': 'string',
            'enum': <String>['metric', 'imperial'],
          },
        },
      };
      vm.setRawSchema(exotic);
      await vm.save();

      // Simplifying it into something the rows understand would change what
      // the model is allowed to emit, which is the opposite of the point.
      check(draftOf(container).answer.rawSchema).isNotNull();
      check(agents.saved.single.answer.schema).isNotNull().deepEquals(exotic);
    });

    test('an exotic schema survives a save and a reload', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.setStructured(true);
      vm.setRawSchema(<String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'n': <String, dynamic>{'type': 'number', 'minimum': 0},
        },
      });
      await vm.save();

      await vm.open(agentId: 'news_digest', duplicate: false);

      check(draftOf(container).answer.rawSchema).isNotNull();
      check(draftOf(container).answer.isStructured).isTrue();
    });

    test('switching back to the fields abandons the raw schema', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.setStructured(true);
      vm.setRawSchema(<String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'a': <String, dynamic>{
            'type': 'string',
            'enum': <String>['x'],
          },
        },
      });

      vm.useFields();

      check(draftOf(container).answer.rawSchema).isNull();
      check(draftOf(container).answer.fields).isNotEmpty();
    });

    test('turning it off takes the schema off the template', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);
      vm.setStructured(true);
      vm.setView('price_table');
      draftOf(container).answer.fields.single.name = 'winner';

      vm.setStructured(false);
      await vm.save();

      check(agents.saved.single.answer.schema).isNull();
      // And the view with it, so a prose agent does not claim a component.
      check(agents.saved.single.answer.view).isNull();
    });
  });

  group('saving and deleting', () {
    test('an agent with nothing filled in lists every problem', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);

      final outcome = await vm.save();

      final problems = (outcome as SaveRejected).problems;
      check(problems.join(' ')).contains('needs a name');
      check(problems.join(' ')).contains('purpose');
      check(problems.join(' ')).contains('system prompt');
      check(agents.saved).isEmpty();
    });

    test('a write that fails is reported, not swallowed', () async {
      final container = containerWith();
      agents.writeFails = true;
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);

      check(await vm.save()).isA<SaveFailed>();
    });

    test('delete removes the file it was editing', () async {
      final container = containerWith(
        seed: <Agent>[
          Agent(template: fakeAgentTemplate(id: 'mine'), isBuiltIn: false),
        ],
      );
      final vm = notifierOf(container);
      await vm.open(agentId: 'mine', duplicate: false);

      await vm.delete();

      check(agents.deleted).deepEquals(<String>['mine']);
    });

    test('delete on an unsaved draft has nothing to remove', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);

      await vm.delete();

      check(agents.deleted).isEmpty();
    });
  });

  group('round trip', () {
    test('a full agent survives draft and back unchanged', () async {
      // The strongest single check that the builder can express what the app
      // already ships: anything it cannot hold would be lost here.
      final template = AgentTemplate(
        id: 'round_trip',
        name: 'Round Trip',
        purpose: 'Goes there and back',
        description: 'A paragraph the builder draws no control for.',
        icon: 'tag',
        systemPrompt: 'You are careful.',
        inputs: const <AgentInput>[
          AgentInput(
            name: 'region',
            label: 'Region',
            type: AgentInputType.choice,
            options: <String>['IN', 'US'],
            defaultValue: 'IN',
          ),
          AgentInput(
            name: 'document',
            label: 'Document',
            type: AgentInputType.file,
            required: false,
          ),
        ],
        pipeline: const <PipelineStep>[
          PipelineStep(
            id: 'search',
            kind: StepKind.tool,
            tool: 'web_search',
            prompt: 'Search for {{input.region}}.',
          ),
          PipelineStep(
            id: 'think',
            kind: StepKind.reason,
            prompt: 'Consider it.',
            reads: <String>['step.search'],
          ),
        ],
        answer: AnswerStep(
          prompt: 'Write it up.',
          reads: const <String>['step.think', 'step.search'],
          view: 'price_table',
          schema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'offers': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'retailer': <String, dynamic>{'type': 'string'},
                    'price': <String, dynamic>{'type': 'number'},
                  },
                  'required': <String>['retailer', 'price'],
                },
              },
            },
            'required': <String>['offers'],
          },
        ),
        temperature: 0.45,
        limits: const AgentLimits(webResults: 6, chunkChars: 1200),
        createdAt: DateTime(2026, 10, 1),
      );

      final back = AgentDraft.from(
        template,
        id: template.id,
      ).toTemplate(id: template.id);

      check(back.name).equals(template.name);
      check(back.description).equals(template.description);
      check(back.icon).equals(template.icon);
      check(back.temperature).equals(0.45);
      check(back.inputs.first.options).deepEquals(<String>['IN', 'US']);
      check(back.inputs.last.type).equals(AgentInputType.file);
      check(back.inputs.last.required).isFalse();
      check(back.pipeline.first.tool).equals('web_search');
      check(back.pipeline.last.reads).deepEquals(<String>['step.search']);
      check(back.answer.reads)
          .deepEquals(<String>['step.think', 'step.search']);
      check(back.answer.view).equals('price_table');
      check(back.answer.schema)
          .isNotNull()
          .deepEquals(template.answer.schema ?? <String, dynamic>{});
      check(back.limitsOrDefault.webResults).equals(6);
      check(back.limitsOrDefault.chunkChars).equals(1200);
    });
  });

  group('limits', () {
    test('a new agent starts at the defaults', () async {
      final container = containerWith();
      await notifierOf(container).open(agentId: null, duplicate: false);

      check(draftOf(container).limits.webResults)
          .equals(AgentLimits.defaultWebResults);
    });

    test('what the sliders set is what gets saved', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      fillBasics(container);

      vm.setWebResults(7);
      vm.setWebSnippetChars(240);
      vm.setWebPageChars(1500);
      vm.setChunkChars(900);
      vm.setChunkOverlapChars(60);
      vm.setPassages(8);
      await vm.save();

      final limits = agents.saved.single.limitsOrDefault;
      check(limits.webResults).equals(7);
      check(limits.webSnippetChars).equals(240);
      check(limits.webPageChars).equals(1500);
      check(limits.chunkChars).equals(900);
      check(limits.chunkOverlapChars).equals(60);
      check(limits.passages).equals(8);
    });

    test('only the half that applies is offered', () async {
      final container = containerWith();
      final vm = notifierOf(container);
      await vm.open(agentId: null, duplicate: false);
      vm.addStep();
      final key = draftOf(container).steps.single.key;

      vm.setStepTool(key, 'web_search');
      check(draftOf(container).usesWebTools).isTrue();
      check(draftOf(container).usesDocumentTools).isFalse();

      vm.setStepTool(key, 'search_document');
      check(draftOf(container).usesWebTools).isFalse();
      check(draftOf(container).usesDocumentTools).isTrue();

      // A tool left behind on a step switched to Reason is never called, so
      // its limits are not worth showing either.
      vm.setStepKind(key, StepKind.reason);
      check(draftOf(container).usesDocumentTools).isFalse();
    });
  });
}

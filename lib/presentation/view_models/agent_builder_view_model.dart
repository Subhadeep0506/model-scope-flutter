import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/agent_template.dart';
import '../../domain/services/schema_fields.dart';
import 'agent_builder_state.dart';

/// What the builder was opened to do.
enum BuilderMode {
  /// A blank agent.
  create,

  /// An existing custom agent, saved back over itself.
  edit,

  /// A copy of a built-in, saved as a new one.
  duplicate,
}

/// What came of pressing Save.
sealed class SaveOutcome {
  const SaveOutcome();
}

/// Written. [id] is where it went, which the screen needs to pop back to.
class SaveSucceeded extends SaveOutcome {
  const SaveSucceeded(this.id);

  final String id;
}

/// Not written, because the agent would not validate. The list is the
/// validator's own wording, shown as-is.
class SaveRejected extends SaveOutcome {
  const SaveRejected(this.problems);

  final List<String> problems;
}

/// Not written, because the file would not go down.
class SaveFailed extends SaveOutcome {
  const SaveFailed(this.reason);

  final String reason;
}

/// Owns the agent being built.
///
/// Every mutation lives here rather than in the screen, which only calls these
/// and draws what comes back. The draft is mutable and the notifier re-emits
/// the same instance through [_touch] — a form of thirty controls rebuilt into
/// a fresh immutable tree on every keystroke would be a lot of allocation for
/// no benefit, and nothing outside this screen reads the draft.
class AgentBuilderViewModel extends AsyncNotifier<AgentDraft> {
  static const String _logName = 'AgentBuilderViewModel';

  BuilderMode _mode = BuilderMode.create;

  BuilderMode get mode => _mode;

  bool _isBuiltIn = false;

  /// Whether saving writes over a built-in rather than over a file of the
  /// user's own.
  ///
  /// What the destructive button means hangs on this: for an override it is
  /// `Reset to built-in`, which puts the shipped version back, and for
  /// anything else it is `Delete agent`, which removes it for good.
  bool get isBuiltInOverride => _mode == BuilderMode.edit && _isBuiltIn;

  @override
  Future<AgentDraft> build() async => AgentDraft();

  /// Always notify.
  ///
  /// The draft is mutable and edited in place, so the value Riverpod is asked
  /// to compare is the same object it held before and `==` says nothing
  /// changed. Without this the screen would redraw on nothing but a load —
  /// typing a name, adding a step, ticking a read would all be invisible.
  @override
  bool updateShouldNotify(
    AsyncValue<AgentDraft> previous,
    AsyncValue<AgentDraft> next,
  ) => true;

  /// Loads whatever the route asked for. Called once, after the first frame.
  Future<void> open({required String? agentId, required bool duplicate}) async {
    if (agentId == null) {
      _mode = BuilderMode.create;
      _isBuiltIn = false;
      state = AsyncData<AgentDraft>(AgentDraft());
      return;
    }

    state = const AsyncLoading<AgentDraft>();
    try {
      final agent = await ref.read(agentRepositoryProvider).byId(agentId);
      if (agent == null) {
        state = AsyncError<AgentDraft>(
          StateError('That agent no longer exists.'),
          StackTrace.current,
        );
        return;
      }

      _mode = duplicate ? BuilderMode.duplicate : BuilderMode.edit;
      _isBuiltIn = agent.isBuiltIn;
      final draft = AgentDraft.from(
        agent.template,
        // A duplicate carries no id, so saving mints a new one and leaves the
        // original where it is. An edit keeps the id — including a built-in's,
        // where saving writes a file that shadows the bundled one.
        id: duplicate ? null : agent.id,
      );
      if (duplicate) draft.name = '${agent.template.name} copy';
      state = AsyncData<AgentDraft>(draft);
    } catch (error, stackTrace) {
      state = AsyncError<AgentDraft>(error, stackTrace);
    }
  }

  AgentDraft get _draft => state.value ?? AgentDraft();

  /// Re-emits the draft so the screen rebuilds. See [updateShouldNotify] for
  /// why re-emitting the same object is enough.
  void _touch() => state = AsyncData<AgentDraft>(_draft);

  // ---- basics -------------------------------------------------------------

  void setName(String value) {
    _draft.name = value;
    _touch();
  }

  void setPurpose(String value) {
    _draft.purpose = value;
    _touch();
  }

  void setIcon(String value) {
    _draft.icon = value;
    _touch();
  }

  void setSystemPrompt(String value) {
    _draft.systemPrompt = value;
    _touch();
  }

  // ---- limits -------------------------------------------------------------

  void setWebResults(int value) {
    _draft.limits.webResults = value;
    _touch();
  }

  void setWebSnippetChars(int value) {
    _draft.limits.webSnippetChars = value;
    _touch();
  }

  void setWebPageChars(int value) {
    _draft.limits.webPageChars = value;
    _touch();
  }

  void setChunkChars(int value) {
    _draft.limits.chunkChars = value;
    _touch();
  }

  void setChunkOverlapChars(int value) {
    _draft.limits.chunkOverlapChars = value;
    _touch();
  }

  void setPassages(int value) {
    _draft.limits.passages = value;
    _touch();
  }

  // ---- inputs -------------------------------------------------------------

  void addInput() {
    _draft.inputs.add(DraftInput());
    _touch();
  }

  void removeInput(String key) {
    _draft.inputs.removeWhere((input) => input.key == key);
    _touch();
  }

  /// Renaming an input renames it everywhere it is read, so a step does not
  /// silently start reading something that no longer exists.
  void setInputLabel(String key, String label) {
    final input = _inputFor(key);
    if (input == null) return;

    final wasAuto = input.name == slugify(input.label);
    input.label = label;
    if (wasAuto) _renameInput(input, slugify(label));
    _touch();
  }

  void setInputName(String key, String name) {
    final input = _inputFor(key);
    if (input == null) return;
    _renameInput(input, slugify(name));
    _touch();
  }

  void _renameInput(DraftInput input, String name) {
    final from = 'input.${input.name}';
    final to = 'input.$name';
    input.name = name;
    if (from == to) return;

    for (final step in _draft.steps) {
      _replaceReference(step.reads, from, to);
      step.prompt = step.prompt.replaceAll('{{$from}}', '{{$to}}');
    }
    _replaceReference(_draft.answer.reads, from, to);
    _draft.answer.prompt = _draft.answer.prompt.replaceAll(
      '{{$from}}',
      '{{$to}}',
    );
  }

  void setInputType(String key, AgentInputType type) {
    final input = _inputFor(key);
    if (input == null) return;
    input.type = type;
    // A choice with no options is a blocker the validator reports, so one
    // empty row is offered rather than an empty list.
    if (type == AgentInputType.choice && input.options.isEmpty) {
      input.options.add('');
    }
    _touch();
  }

  void setInputDefault(String key, String value) {
    _inputFor(key)?.defaultValue = value;
    _touch();
  }

  void setInputRequired(String key, bool value) {
    _inputFor(key)?.required = value;
    _touch();
  }

  void addInputOption(String key) {
    _inputFor(key)?.options.add('');
    _touch();
  }

  void setInputOption(String key, int index, String value) {
    final options = _inputFor(key)?.options;
    if (options == null || index < 0 || index >= options.length) return;
    options[index] = value;
    _touch();
  }

  void removeInputOption(String key, int index) {
    final options = _inputFor(key)?.options;
    if (options == null || index < 0 || index >= options.length) return;
    options.removeAt(index);
    _touch();
  }

  DraftInput? _inputFor(String key) {
    for (final input in _draft.inputs) {
      if (input.key == key) return input;
    }
    return null;
  }

  // ---- steps --------------------------------------------------------------

  void addStep() {
    _draft.steps.add(DraftStep(id: _nextStepId()));
    _touch();
  }

  /// `step_1`, `step_2`, … skipping any already taken.
  String _nextStepId() {
    final taken = <String>{for (final step in _draft.steps) step.id.trim()};
    for (var n = _draft.steps.length + 1; ; n++) {
      final candidate = 'step_$n';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  void removeStep(String key) {
    final step = _stepFor(key);
    if (step == null) return;
    _draft.steps.remove(step);
    // Anything reading it is now reading something that will never run.
    _dropReference('step.${step.id.trim()}');
    _touch();
  }

  void duplicateStep(String key) {
    final index = _draft.steps.indexWhere((step) => step.key == key);
    if (index < 0) return;
    final copy = _draft.steps[index].copy();
    copy.id = _nextStepId();
    _draft.steps.insert(index + 1, copy);
    _touch();
  }

  /// Moves a step one place. [delta] is -1 for up, 1 for down.
  ///
  /// Anything the moved step reads that now comes after it is dropped, and so
  /// is anything that read it and now comes before — reordering must not leave
  /// a step reading the future.
  void moveStep(String key, int delta) {
    final index = _draft.steps.indexWhere((step) => step.key == key);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _draft.steps.length) return;

    final step = _draft.steps.removeAt(index);
    _draft.steps.insert(target, step);
    _pruneReads();
    _touch();
  }

  void setStepKind(String key, StepKind kind) {
    _stepFor(key)?.kind = kind;
    _touch();
  }

  void setStepTool(String key, String tool) {
    _stepFor(key)?.tool = tool;
    _touch();
  }

  void setStepPrompt(String key, String prompt) {
    _stepFor(key)?.prompt = prompt;
    _touch();
  }

  void setStepId(String key, String id) {
    final step = _stepFor(key);
    if (step == null) return;

    final from = 'step.${step.id.trim()}';
    final to = 'step.${slugify(id)}';
    step.id = slugify(id);
    if (from == to) return;

    for (final other in _draft.steps) {
      _replaceReference(other.reads, from, to);
      other.prompt = other.prompt.replaceAll('{{$from}}', '{{$to}}');
    }
    _replaceReference(_draft.answer.reads, from, to);
    _draft.answer.prompt = _draft.answer.prompt.replaceAll(
      '{{$from}}',
      '{{$to}}',
    );
    _touch();
  }

  void toggleStepRead(String key, String reference) {
    final reads = _stepFor(key)?.reads;
    if (reads == null) return;
    reads.contains(reference) ? reads.remove(reference) : reads.add(reference);
    _touch();
  }

  DraftStep? _stepFor(String key) {
    for (final step in _draft.steps) {
      if (step.key == key) return step;
    }
    return null;
  }

  /// Drops every read a step is no longer allowed to make.
  void _pruneReads() {
    for (final (index, step) in _draft.steps.indexed) {
      final allowed = <String>{
        for (final reference in _draft.referencesBefore(index))
          reference.reference,
      };
      step.reads.removeWhere((read) => !allowed.contains(read));
    }
  }

  void _dropReference(String reference) {
    for (final step in _draft.steps) {
      step.reads.remove(reference);
    }
    _draft.answer.reads.remove(reference);
  }

  static void _replaceReference(List<String> reads, String from, String to) {
    for (var i = 0; i < reads.length; i++) {
      if (reads[i] == from) reads[i] = to;
    }
  }

  // ---- the answer ---------------------------------------------------------

  void setAnswerPrompt(String value) {
    _draft.answer.prompt = value;
    _touch();
  }

  void toggleAnswerRead(String reference) {
    final reads = _draft.answer.reads;
    reads.contains(reference) ? reads.remove(reference) : reads.add(reference);
    _touch();
  }

  void setStructured(bool value) {
    _draft.answer.isStructured = value;
    // One empty row to type into, rather than an empty tab with an Add button.
    if (value &&
        _draft.answer.fields.isEmpty &&
        _draft.answer.rawSchema == null) {
      _draft.answer.fields.add(SchemaField());
    }
    _touch();
  }

  void setView(String? value) {
    _draft.answer.view = value;
    _touch();
  }

  /// Replaces the schema with one typed into the JSON tab.
  ///
  /// When the rows can draw it they become the source of truth and the raw
  /// copy is dropped; when they cannot, the raw copy is kept and the rows are
  /// left alone — see [DraftAnswer.rawSchema].
  void setRawSchema(Map<String, dynamic> schema) {
    final fields = fieldsFromSchema(schema);
    final answer = _draft.answer;
    if (fields == null) {
      answer.rawSchema = schema;
    } else {
      answer.rawSchema = null;
      answer.fields
        ..clear()
        ..addAll(fields);
    }
    _touch();
  }

  /// Abandons a raw schema so the rows take over again.
  void useFields() {
    _draft.answer.rawSchema = null;
    if (_draft.answer.fields.isEmpty) _draft.answer.fields.add(SchemaField());
    _touch();
  }

  /// The fields are mutated in place by the rows; this only redraws.
  void touchFields() => _touch();

  // ---- saving -------------------------------------------------------------

  /// Validates and writes. Returns what happened for the screen to show.
  Future<SaveOutcome> save() async {
    final draft = _draft;
    final id = draft.id ?? await _mintId(draft.name);
    final template = draft.toTemplate(
      id: id,
      createdAt: draft.createdAt ?? DateTime.now(),
    );

    final problems = <String>[
      ..._ownProblems(draft, template),
      ...ref.read(agentValidatorProvider).structuralProblems(template),
    ];
    if (problems.isNotEmpty) return SaveRejected(problems);

    final written = await ref.read(agentRepositoryProvider).save(template);
    if (!written) {
      return const SaveFailed('That agent could not be written to storage.');
    }

    draft.id = id;
    _mode = BuilderMode.edit;
    ref.invalidate(agentsProvider);
    developer.log('Saved agent $id', name: _logName);
    return SaveSucceeded(id);
  }

  /// Saves a template straight from the JSON editor, keeping the same checks.
  Future<SaveOutcome> saveTemplate(AgentTemplate template) async {
    final problems = ref
        .read(agentValidatorProvider)
        .structuralProblems(template);
    if (problems.isNotEmpty) return SaveRejected(problems);

    final written = await ref.read(agentRepositoryProvider).save(template);
    if (!written) {
      return const SaveFailed('That agent could not be written to storage.');
    }

    state = AsyncData<AgentDraft>(AgentDraft.from(template, id: template.id));
    _mode = BuilderMode.edit;
    ref.invalidate(agentsProvider);
    return SaveSucceeded(template.id);
  }

  /// What the validator does not check, because a template cannot be built
  /// without them in the first place.
  static List<String> _ownProblems(AgentDraft draft, AgentTemplate template) =>
      <String>[
        if (template.name.isEmpty) 'This agent needs a name',
        if (template.purpose.isEmpty) 'This agent needs a one-line purpose',
        if (template.systemPrompt.isEmpty) 'This agent needs a system prompt',
        for (final input in draft.inputs)
          if (input.name.trim().isEmpty) 'An input has no name',
        for (final input in draft.inputs)
          if (input.type == AgentInputType.choice &&
              input.toInput().options.isEmpty)
            '"${input.label}" is a choice with no options',
        if (draft.answer.isStructured && draft.answer.toSchema() == null)
          'The structured response has no fields',
      ];

  /// A filesystem-safe id, unique against everything already loaded.
  Future<String> _mintId(String name) async {
    final base = slugify(name).isEmpty ? 'agent' : slugify(name);
    final taken = <String>{
      for (final agent in await ref.read(agentRepositoryProvider).load())
        agent.id,
    };

    if (!taken.contains(base)) return base;
    for (var n = 2; ; n++) {
      final candidate = '${base}_$n';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> delete() => _removeFile('Deleted agent');

  /// Throws away the user's version of a built-in.
  ///
  /// The same file removal as [delete] — the bundled template was never gone,
  /// only shadowed, so dropping the override is all it takes to have the
  /// shipped agent load again.
  Future<void> reset() => _removeFile('Reset agent');

  Future<void> _removeFile(String what) async {
    final id = _draft.id;
    if (id == null) return;
    await ref.read(agentRepositoryProvider).delete(id);
    ref.invalidate(agentsProvider);
    developer.log('$what $id', name: _logName);
  }
}

/// `News digest` → `news_digest`.
///
/// Used for ids, which become file names, and for input and step names, which
/// are written into prompts as `{{input.x}}` — so anything outside letters,
/// digits and underscores has to go.
String slugify(String value) {
  final lower = value.trim().toLowerCase();
  final cleaned = lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return cleaned;
}

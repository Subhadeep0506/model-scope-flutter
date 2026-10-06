library;

/// The values a step can read, built up as the run proceeds.
class AgentScope {
  AgentScope({Map<String, String>? inputs})
    : _inputs = <String, String>{...?inputs};

  final Map<String, String> _inputs;
  final Map<String, String> _steps = <String, String>{};

  /// What the user typed, by input name.
  Map<String, String> get inputs => Map<String, String>.unmodifiable(_inputs);

  /// What each finished step produced, by step id.
  Map<String, String> get steps => Map<String, String>.unmodifiable(_steps);

  /// Records [output] as the result of step [id].
  void record(String id, String output) => _steps[id] = output;

  String? resolve(String reference) {
    final (namespace, key) = _split(reference);
    return switch (namespace) {
      'input' => _inputs[key],
      'step' => _steps[key],
      _ => null,
    };
  }

  /// What a reference is called on screen: `Query`, not `input.query`.
  static String labelFor(String reference) {
    final (namespace, key) = _split(reference);
    final words = key
        .split(RegExp('[_.-]'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
    return switch (namespace) {
      'step' => 'Result of $words',
      _ => words,
    };
  }

  static (String, String) _split(String reference) {
    final dot = reference.indexOf('.');
    if (dot < 0) return ('', reference);
    return (reference.substring(0, dot), reference.substring(dot + 1));
  }
}

String renderTemplate(String template, AgentScope scope) =>
    template.replaceAllMapped(
      RegExp(r'\{\{\s*([A-Za-z0-9_.]+)\s*\}\}'),
      (match) => scope.resolve(match.group(1) ?? '') ?? '',
    );

/// Every `{{reference}}` named in [template], in the order they appear.
List<String> referencesIn(String template) => <String>[
  for (final match in RegExp(
    r'\{\{\s*([A-Za-z0-9_.]+)\s*\}\}',
  ).allMatches(template))
    match.group(1) ?? '',
];

String buildStepPrompt({
  required String instruction,
  required List<String> reads,
  required AgentScope scope,
}) {
  final blocks = <String>[];
  for (final reference in reads) {
    final value = scope.resolve(reference)?.trim() ?? '';
    if (value.isEmpty) continue;
    blocks.add('${AgentScope.labelFor(reference)}:\n$value');
  }

  final rendered = renderTemplate(instruction, scope).trim();
  if (blocks.isEmpty) return rendered;
  return '${blocks.join('\n\n')}\n\n$rendered';
}

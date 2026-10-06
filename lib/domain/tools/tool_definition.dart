/// A capability a language model may call, described without reference to any
/// particular runtime.
///
/// `package:nobodywho` builds its own `Tool` from a Dart function, reading the
/// parameter names and types straight off `function.runtimeType` to generate a
/// JSON schema. That is convenient but native: constructing one needs the
/// Rust library loaded, which `flutter test` cannot do. Keeping the definition
/// in a plain class means a test can call [function] directly and check what
/// the model would have been told, and means a different backend later is one
/// adapter file rather than a rewrite.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.function,
    this.parameterDescriptions = const <String, String>{},
  });

  /// Lowercase with underscores, as the chat templates of most tool-calling
  /// models expect.
  final String name;

  /// What the tool does, and when to reach for it. This is the whole of what
  /// the model knows, so it is written for the model rather than for a reader
  /// of the code.
  final String description;

  /// The work itself.
  ///
  /// Three rules, all imposed by the schema generator rather than by choice:
  ///
  /// * every parameter must be **named and `required`** — optional named
  ///   parameters are not exercised by the library and the generator reads the
  ///   signature as written;
  /// * types must be `String`, `int`, `double`, `bool`, or a `List`/`Set` of
  ///   those;
  /// * it must return `String` or `Future<String>`, because the return value
  ///   goes back into the model's context as text.
  ///
  /// It must not throw. A tool that throws returns the exception's text to the
  /// model as its result, which reads as an answer rather than a failure; so
  /// every tool here catches and returns a sentence saying what went wrong.
  final Function function;

  /// A line per parameter, by name, telling the model what to put in it. The
  /// generator supplies names and types on its own; this supplies the meaning.
  final Map<String, String> parameterDescriptions;
}

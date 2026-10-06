import 'package:nobodywho/nobodywho.dart' as nobodywho;

import 'tool_definition.dart';

/// The one place a [ToolDefinition] meets `package:nobodywho`.
///
/// Building a `nobodywho.Tool` loads the native library and generates a JSON
/// schema by reflecting on the function's runtime type, neither of which works
/// under `flutter test`. Keeping that in a file of its own means everything
/// around it — the services, the tool definitions, the text the model reads —
/// stays testable, and the untested part is three lines with no logic in it.
///
/// The chat owns the attachment: `Chat.fromPath(tools: ...)` at load, or
/// `chat.setTools(...)` afterwards, which is how a session can be given tools
/// without reloading the weights.
extension ToolDefinitionAdapter on ToolDefinition {
  nobodywho.Tool toNobodyWho() => nobodywho.Tool(
    function: function,
    name: name,
    description: description,
    parameterDescriptions: parameterDescriptions,
  );
}

/// Every definition in [definitions], in the shape a chat accepts.
List<nobodywho.Tool> toNobodyWhoTools(Iterable<ToolDefinition> definitions) =>
    definitions
        .map((definition) => definition.toNobodyWho())
        .toList(growable: false);

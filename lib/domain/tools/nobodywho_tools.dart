import 'package:nobodywho/nobodywho.dart' as nobodywho;

import 'tool_definition.dart';

extension ToolDefinitionAdapter on ToolDefinition {
  nobodywho.Tool toNobodyWho() => nobodywho.Tool(
    function: function,
    name: name,
    description: description,
    parameterDescriptions: parameterDescriptions,
  );
}

List<nobodywho.Tool> toNobodyWhoTools(Iterable<ToolDefinition> definitions) =>
    definitions
        .map((definition) => definition.toNobodyWho())
        .toList(growable: false);

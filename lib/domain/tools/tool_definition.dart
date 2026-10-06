class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.function,
    this.parameterDescriptions = const <String, String>{},
  });
  final String name;
  final String description;
  final Function function;
  final Map<String, String> parameterDescriptions;
}

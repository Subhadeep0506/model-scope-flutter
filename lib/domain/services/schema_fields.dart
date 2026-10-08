/// What a field in the builder's `{} Fields` tab can be.
///
/// Five types, which is what `agents-new-agent-6.png` draws. Deliberately far
/// short of JSON Schema: these are the shapes a row can be drawn for, and
/// anything richer is edited as JSON instead.
enum SchemaFieldType {
  text('Text', 'string'),
  number('Number', 'number'),
  boolean('Yes / no', 'boolean'),
  object('Object', 'object'),
  array('Array', 'array');

  const SchemaFieldType(this.label, this.jsonType);

  /// The caption on the type dropdown.
  final String label;

  /// What it is called in the schema itself.
  final String jsonType;

  /// Whether a field of this type holds other fields.
  bool get holdsChildren => this == SchemaFieldType.object;

  static SchemaFieldType? fromJsonType(String? type) {
    for (final value in values) {
      if (value.jsonType == type) return value;
    }
    return null;
  }
}

/// One row in the fields builder.
///
/// Mutable, unlike nearly everything else in this app: it is form state being
/// typed into, and rebuilding a tree of immutable nodes on every keystroke
/// would mean threading an index path through every callback.
class SchemaField {
  SchemaField({
    this.name = '',
    this.type = SchemaFieldType.text,
    this.required = true,
    List<SchemaField>? children,
    this.itemType = SchemaFieldType.text,
    List<SchemaField>? itemChildren,
  }) : children = children ?? <SchemaField>[],
       itemChildren = itemChildren ?? <SchemaField>[];

  String name;
  SchemaFieldType type;

  /// Whether the model must emit this field.
  ///
  /// Worth being deliberate about: llguidance forces every required field to
  /// be produced, so requiring something the material may not support makes
  /// the model invent it rather than leave it out.
  bool required;

  /// The properties of an [SchemaFieldType.object].
  final List<SchemaField> children;

  /// What an [SchemaFieldType.array] holds — the `ITEMS OF` dropdown.
  SchemaFieldType itemType;

  /// The properties of each item, when [itemType] is an object.
  final List<SchemaField> itemChildren;

  SchemaField copy() => SchemaField(
    name: name,
    type: type,
    required: required,
    children: <SchemaField>[for (final child in children) child.copy()],
    itemType: itemType,
    itemChildren: <SchemaField>[for (final child in itemChildren) child.copy()],
  );
}

/// The fields as a JSON Schema the sampler can be built from.
///
/// Returns null when there is nothing to describe, which is what tells the
/// answer step to generate prose rather than constrain anything.
Map<String, dynamic>? schemaFromFields(List<SchemaField> fields) {
  final named = <SchemaField>[
    for (final field in fields)
      if (field.name.trim().isNotEmpty) field,
  ];
  if (named.isEmpty) return null;
  return _objectFrom(named);
}

Map<String, dynamic> _objectFrom(List<SchemaField> fields) {
  final properties = <String, dynamic>{};
  final required = <String>[];

  for (final field in fields) {
    final name = field.name.trim();
    // Last one wins on a duplicate name, which is what a JSON object would do
    // anyway — and the builder cannot stop someone typing the same name twice.
    if (name.isEmpty) continue;
    properties[name] = _valueFrom(field);
    if (field.required) required.add(name);
  }

  return <String, dynamic>{
    'type': 'object',
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };
}

Map<String, dynamic> _valueFrom(SchemaField field) => switch (field.type) {
  SchemaFieldType.object => _objectFrom(field.children),
  SchemaFieldType.array => <String, dynamic>{
    'type': 'array',
    'items': field.itemType == SchemaFieldType.object
        ? _objectFrom(field.itemChildren)
        : <String, dynamic>{'type': field.itemType.jsonType},
  },
  _ => <String, dynamic>{'type': field.type.jsonType},
};

/// [schema] as rows the builder can draw, or **null when it cannot draw it**.
///
/// Null is not a failure: it means the schema uses something outside the five
/// types above — an `enum`, a `$ref`, a `minimum`, a union — and the editor
/// should keep showing the JSON rather than quietly throwing those away. A
/// schema the rows cannot express is still a perfectly good schema to hand to
/// the sampler, which is the whole reason the JSON tab is editable.
List<SchemaField>? fieldsFromSchema(Map<String, dynamic>? schema) {
  if (schema == null) return null;
  if (schema['type'] != 'object') return null;

  final properties = schema['properties'];
  if (properties is! Map<String, dynamic>) return null;
  // Anything beyond the three keys the builder writes means the schema says
  // more than the rows can show.
  if (_hasExtraKeys(schema, const <String>{'type', 'properties', 'required'})) {
    return null;
  }

  final required = <String>{
    for (final name
        in schema['required'] is List
            ? schema['required'] as List<dynamic>
            : const <dynamic>[])
      if (name is String) name,
  };

  final fields = <SchemaField>[];
  for (final entry in properties.entries) {
    final field = _fieldFrom(
      entry.key,
      entry.value,
      required.contains(entry.key),
    );
    if (field == null) return null;
    fields.add(field);
  }
  return fields;
}

SchemaField? _fieldFrom(String name, Object? value, bool required) {
  if (value is! Map<String, dynamic>) return null;

  final declared = value['type'];
  final type = SchemaFieldType.fromJsonType(
    declared is String ? declared : null,
  );
  if (type == null) return null;

  switch (type) {
    case SchemaFieldType.object:
      final children = fieldsFromSchema(value);
      if (children == null) return null;
      return SchemaField(
        name: name,
        type: type,
        required: required,
        children: children,
      );

    case SchemaFieldType.array:
      if (_hasExtraKeys(value, const <String>{'type', 'items'})) return null;
      final items = value['items'];
      if (items is! Map<String, dynamic>) return null;

      final itemType = SchemaFieldType.fromJsonType(
        items['type'] is String ? items['type'] as String : null,
      );
      if (itemType == null || itemType == SchemaFieldType.array) return null;

      if (itemType == SchemaFieldType.object) {
        final children = fieldsFromSchema(items);
        if (children == null) return null;
        return SchemaField(
          name: name,
          type: type,
          required: required,
          itemType: itemType,
          itemChildren: children,
        );
      }
      if (_hasExtraKeys(items, const <String>{'type'})) return null;
      return SchemaField(
        name: name,
        type: type,
        required: required,
        itemType: itemType,
      );

    case SchemaFieldType.text:
    case SchemaFieldType.number:
    case SchemaFieldType.boolean:
      // `{"type": "string", "enum": [...]}` is a constraint a row cannot show,
      // and dropping it would change what the model is allowed to emit.
      if (_hasExtraKeys(value, const <String>{'type'})) return null;
      return SchemaField(name: name, type: type, required: required);
  }
}

bool _hasExtraKeys(Map<String, dynamic> value, Set<String> known) =>
    value.keys.any((key) => !known.contains(key));

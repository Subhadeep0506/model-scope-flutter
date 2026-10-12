enum SchemaFieldType {
  text('Text', 'string'),
  number('Number', 'number'),
  boolean('Yes / no', 'boolean'),
  object('Object', 'object'),
  array('Array', 'array');

  const SchemaFieldType(this.label, this.jsonType);
  final String label;
  final String jsonType;
  bool get holdsChildren => this == SchemaFieldType.object;

  static SchemaFieldType? fromJsonType(String? type) {
    for (final value in values) {
      if (value.jsonType == type) return value;
    }
    return null;
  }
}

/// One row in the fields builder.
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
  bool required;
  final List<SchemaField> children;
  SchemaFieldType itemType;
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
List<SchemaField>? fieldsFromSchema(Map<String, dynamic>? schema) {
  if (schema == null) return null;
  if (schema['type'] != 'object') return null;

  final properties = schema['properties'];
  if (properties is! Map<String, dynamic>) return null;

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
      if (_hasExtraKeys(value, const <String>{'type'})) return null;
      return SchemaField(name: name, type: type, required: required);
  }
}

bool _hasExtraKeys(Map<String, dynamic> value, Set<String> known) =>
    value.keys.any((key) => !known.contains(key));

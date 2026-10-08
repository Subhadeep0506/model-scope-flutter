import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/schema_fields.dart';

void main() {
  group('schemaFromFields', () {
    test('nothing to describe makes no schema', () {
      // Null is what tells the answer step to write prose instead.
      check(schemaFromFields(<SchemaField>[])).isNull();
      check(schemaFromFields(<SchemaField>[SchemaField()])).isNull();
    });

    test('a flat field becomes a property and a requirement', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(name: 'winner'),
        SchemaField(name: 'score', type: SchemaFieldType.number),
        SchemaField(
          name: 'tied',
          type: SchemaFieldType.boolean,
          required: false,
        ),
      ]);

      check(schema ?? <String, dynamic>{}).deepEquals(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'winner': <String, Object?>{'type': 'string'},
          'score': <String, Object?>{'type': 'number'},
          'tied': <String, Object?>{'type': 'boolean'},
        },
        'required': <String>['winner', 'score'],
      });
    });

    test('nothing required means no required key at all', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(name: 'note', required: false),
      ]);

      check(schema?.containsKey('required') ?? true).isFalse();
    });

    test('an unnamed row is skipped rather than written blank', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(name: 'kept'),
        SchemaField(name: '   '),
      ]);

      check((schema?['properties'] as Map<String, dynamic>).keys)
          .deepEquals(<String>['kept']);
    });

    test('names are trimmed, so a stray space is not part of the key', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(name: '  winner '),
      ]);

      check((schema?['properties'] as Map<String, dynamic>).keys)
          .deepEquals(<String>['winner']);
    });

    test('an object nests its own properties', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(
          name: 'best',
          type: SchemaFieldType.object,
          children: <SchemaField>[
            SchemaField(name: 'retailer'),
            SchemaField(name: 'price', type: SchemaFieldType.number),
          ],
        ),
      ]);

      check(_properties(schema)).deepEquals(<String, Object?>{
        'best': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'retailer': <String, Object?>{'type': 'string'},
            'price': <String, Object?>{'type': 'number'},
          },
          'required': <String>['retailer', 'price'],
        },
      });
    });

    test('an array of scalars names only its item type', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(
          name: 'tags',
          type: SchemaFieldType.array,
          itemType: SchemaFieldType.text,
        ),
      ]);

      check(_properties(schema)).deepEquals(<String, Object?>{
        'tags': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      });
    });

    test('an array of objects carries its row shape', () {
      final schema = schemaFromFields(<SchemaField>[
        SchemaField(
          name: 'offers',
          type: SchemaFieldType.array,
          itemType: SchemaFieldType.object,
          itemChildren: <SchemaField>[
            SchemaField(name: 'retailer'),
            SchemaField(name: 'price', type: SchemaFieldType.number),
          ],
        ),
      ]);

      final offers =
          (schema?['properties'] as Map<String, dynamic>)['offers']
              as Map<String, dynamic>;
      check(offers['items'] as Map<String, dynamic>)
          .deepEquals(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'retailer': <String, Object?>{'type': 'string'},
              'price': <String, Object?>{'type': 'number'},
            },
            'required': <String>['retailer', 'price'],
          });
    });
  });

  group('fieldsFromSchema', () {
    /// Through JSON and back, which is what the two editor tabs do.
    List<SchemaField>? roundTrip(List<SchemaField> fields) =>
        fieldsFromSchema(schemaFromFields(fields));

    test('a flat schema round-trips', () {
      final back =
          roundTrip(<SchemaField>[
            SchemaField(name: 'winner'),
            SchemaField(name: 'score', type: SchemaFieldType.number),
            SchemaField(
              name: 'tied',
              type: SchemaFieldType.boolean,
              required: false,
            ),
          ]) ??
          <SchemaField>[];

      check(back).length.equals(3);
      check(back[0].name).equals('winner');
      check(back[0].type).equals(SchemaFieldType.text);
      check(back[0].required).isTrue();
      check(back[1].type).equals(SchemaFieldType.number);
      check(back[2].type).equals(SchemaFieldType.boolean);
      check(back[2].required).isFalse();
    });

    test('a nested object round-trips', () {
      final back = roundTrip(<SchemaField>[
        SchemaField(
          name: 'best',
          type: SchemaFieldType.object,
          children: <SchemaField>[SchemaField(name: 'retailer')],
        ),
      ]);

      check(back?.single.type).equals(SchemaFieldType.object);
      check(back?.single.children ?? <SchemaField>[]).length.equals(1);
      check(back?.single.children.single.name).equals('retailer');
    });

    test('an array of objects round-trips', () {
      final back = roundTrip(<SchemaField>[
        SchemaField(
          name: 'offers',
          type: SchemaFieldType.array,
          itemType: SchemaFieldType.object,
          itemChildren: <SchemaField>[
            SchemaField(name: 'price', type: SchemaFieldType.number),
          ],
        ),
      ]);

      check(back?.single.type).equals(SchemaFieldType.array);
      check(back?.single.itemType).equals(SchemaFieldType.object);
      check(back?.single.itemChildren.single.name).equals('price');
    });

    test('an array of scalars round-trips', () {
      final back = roundTrip(<SchemaField>[
        SchemaField(
          name: 'tags',
          type: SchemaFieldType.array,
          itemType: SchemaFieldType.text,
        ),
      ]);

      check(back?.single.itemType).equals(SchemaFieldType.text);
      check(back?.single.itemChildren ?? <SchemaField>[]).isEmpty();
    });

    test('the real Price Comparison schema round-trips', () {
      // The shipped file, shortened. If the builder cannot read this it
      // cannot be used to edit the agent it ships with.
      final back = fieldsFromSchema(<String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'currency': <String, dynamic>{'type': 'string'},
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
          'cheapest_retailer': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['currency', 'offers', 'cheapest_retailer'],
      });

      check(back ?? <SchemaField>[]).length.equals(3);
      check(back?[1].itemChildren ?? <SchemaField>[]).length.equals(2);
    });
  });

  group('a schema the rows cannot draw', () {
    test('an enum is not representable', () {
      // Dropping it would change what the model is allowed to emit, so the
      // editor must keep showing the JSON instead.
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'units': <String, dynamic>{
              'type': 'string',
              'enum': <String>['metric', 'imperial'],
            },
          },
        }),
      ).isNull();
    });

    test('a constraint on a number is not representable', () {
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'score': <String, dynamic>{'type': 'number', 'minimum': 0},
          },
        }),
      ).isNull();
    });

    test('a keyword beside the properties is not representable', () {
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'a': <String, dynamic>{'type': 'string'},
          },
          'additionalProperties': false,
        }),
      ).isNull();
    });

    test('a union type is not representable', () {
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'a': <String, dynamic>{
              'oneOf': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'string'},
              ],
            },
          },
        }),
      ).isNull();
    });

    test('an array of arrays is not representable', () {
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'grid': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'number'},
              },
            },
          },
        }),
      ).isNull();
    });

    test('something that is not an object schema is not representable', () {
      check(fieldsFromSchema(null)).isNull();
      check(fieldsFromSchema(<String, dynamic>{'type': 'array'})).isNull();
      check(fieldsFromSchema(<String, dynamic>{'type': 'object'})).isNull();
    });

    test('a nested object with an enum inside fails the whole schema', () {
      // Not just the one row: the editor has to be honest that it cannot
      // show the schema, not quietly show most of it.
      check(
        fieldsFromSchema(<String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'inner': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'units': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>['a'],
                },
              },
            },
          },
        }),
      ).isNull();
    });
  });

  test('copy is deep, so editing a duplicated row leaves the first alone', () {
    final original = SchemaField(
      name: 'offers',
      type: SchemaFieldType.array,
      itemType: SchemaFieldType.object,
      itemChildren: <SchemaField>[SchemaField(name: 'retailer')],
    );

    final copy = original.copy();
    copy.itemChildren.single.name = 'vendor';

    check(original.itemChildren.single.name).equals('retailer');
  });
}

/// The `properties` object out of a built schema, for comparing against.
Map<String, dynamic> _properties(Map<String, dynamic>? schema) =>
    schema?['properties'] as Map<String, dynamic>? ?? <String, dynamic>{};

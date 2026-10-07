import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/sources/open_meteo_api_client.dart';
import 'package:model_scope_flutter/domain/services/open_meteo_weather_service.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/weather_tools.dart';

void main() {
  /// A service over a client that geocodes any name to itself and answers
  /// every forecast with [temperature], except for the names in [unknown],
  /// which it places nowhere.
  OpenMeteoWeatherService serviceWith({
    double temperature = 14.0,
    Set<String> unknown = const <String>{},
    List<String>? calls,
    int maxLocations = 5,
  }) => OpenMeteoWeatherService(
    OpenMeteoApiClient(
      MockClient((request) async {
        final name = request.url.queryParameters['name'];
        if (name != null) {
          calls?.add(name);
          if (unknown.contains(name)) {
            return http.Response('{}', 200, request: request);
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'results': <Map<String, Object?>>[
                <String, Object?>{
                  'name': name,
                  'latitude': 1.0,
                  'longitude': 2.0,
                  'country': 'Testland',
                },
              ],
            }),
            200,
            request: request,
          );
        }

        return http.Response(
          jsonEncode(<String, Object?>{
            'current': <String, Object?>{
              'temperature_2m': temperature,
              'apparent_temperature': temperature - 1,
              'relative_humidity_2m': 70,
              'wind_speed_10m': 10.0,
              'weather_code': 61,
              'is_day': 1,
            },
            'current_units': <String, Object?>{
              'temperature_2m': '°C',
              'wind_speed_10m': 'km/h',
            },
            'daily': <String, Object?>{
              'time': <String>['2026-10-07', '2026-10-08'],
              'temperature_2m_max': <double>[19.0, 17.0],
              'temperature_2m_min': <double>[11.0, 10.0],
              'precipitation_sum': <double>[0.0, 4.2],
              'precipitation_probability_max': <int>[0, 80],
              'weather_code': <int>[3, 63],
            },
          }),
          200,
          request: request,
        );
      }),
    ),
    maxLocations: maxLocations,
  );

  /// Runs the tool the way the model does, by name.
  Future<String> runTool(
    ToolDefinition tool, {
    required String locations,
    String units = 'metric',
  }) async => await Function.apply(
    tool.function,
    <Object?>[],
    <Symbol, Object?>{#locations: locations, #units: units},
  ) as String;

  group('parseLocations', () {
    test('splits on commas and trims', () {
      final service = serviceWith();

      check(service.parseLocations('London, Tokyo ,New York'))
          .deepEquals(<String>['London', 'Tokyo', 'New York']);
    });

    test('drops blanks and repeats regardless of case', () {
      final service = serviceWith();

      // A small model listing one city twice should not cost two requests to
      // be told the same thing.
      check(service.parseLocations('Paris, , paris, PARIS, Rome'))
          .deepEquals(<String>['Paris', 'Rome']);
    });

    test('stops at the ceiling rather than fetching all day', () {
      final service = serviceWith(maxLocations: 3);

      check(service.parseLocations('a, b, c, d, e')).length.equals(3);
    });
  });

  group('get_weather', () {
    test('one call covers every place named', () async {
      final calls = <String>[];
      final tool = weatherTool(serviceWith(calls: calls));

      final result = await runTool(tool, locations: 'London, Tokyo, New York');

      // The whole reason this tool takes a list: three places, one call.
      check(calls).deepEquals(<String>['London', 'Tokyo', 'New York']);
      check(result).contains('London, Testland');
      check(result).contains('Tokyo, Testland');
      check(result).contains('New York, Testland');
    });

    test('reports conditions, the range and the rain outlook', () async {
      final tool = weatherTool(serviceWith(temperature: 14.2));

      final result = await runTool(tool, locations: 'London');

      check(result).contains('Now: 14.2°C, light rain');
      check(result).contains('feels like 13.2°C');
      check(result).contains('Humidity 70%, wind 10km/h');
      check(result).contains('Today: 11 to 19, overcast, no precipitation');
      check(result).contains('Tomorrow: 10 to 17, rain, 80% chance');
    });

    test(
      'a place that could not be found is named, not quietly dropped',
      () async {
        final tool = weatherTool(serviceWith(unknown: <String>{'Atlantis'}));

        final result = await runTool(tool, locations: 'London, Atlantis');

        check(result).contains('London, Testland');
        // Said out loud, so the model cannot report on one city and imply it
        // covered both.
        check(result).contains('could not be found');
        check(result).contains('Atlantis');
      },
    );

    test('every place failing is a sentence, not a thrown error', () async {
      final tool = weatherTool(serviceWith(unknown: <String>{'Atlantis'}));

      final result = await runTool(tool, locations: 'Atlantis');

      check(result).contains('The weather lookup failed.');
      check(result).contains('Atlantis');
    });

    test('an empty list is a sentence, not a thrown error', () async {
      final tool = weatherTool(serviceWith());

      // A tool must never throw: whatever comes back goes to the model.
      check(await runTool(tool, locations: '   '))
          .contains('needs at least one place name');
    });

    test('no network is a sentence the model can relay', () async {
      final tool = weatherTool(
        OpenMeteoWeatherService(
          OpenMeteoApiClient(
            MockClient(
              (_) async => throw http.ClientException('Connection closed'),
            ),
          ),
        ),
      );

      final result = await runTool(tool, locations: 'London');

      check(result).contains('The weather lookup failed.');
    });

    test('imperial is asked for when the units say so', () async {
      final units = <String?>[];
      final service = OpenMeteoWeatherService(
        OpenMeteoApiClient(
          MockClient((request) async {
            if (request.url.queryParameters['name'] == null) {
              units.add(request.url.queryParameters['temperature_unit']);
            }
            return http.Response(
              jsonEncode(<String, Object?>{
                'results': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'Austin',
                    'latitude': 1,
                    'longitude': 2,
                  },
                ],
                'current': <String, Object?>{'temperature_2m': 80.0},
              }),
              200,
              request: request,
            );
          }),
        ),
      );

      await runTool(
        weatherTool(service),
        locations: 'Austin',
        units: 'imperial',
      );

      check(units).deepEquals(<String?>['fahrenheit']);
    });
  });
}

import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:model_scope_flutter/data/models/weather_report.dart';
import 'package:model_scope_flutter/data/sources/open_meteo_api_client.dart';

void main() {
  /// A client answering every request with [body] at [status], handing the
  /// request it was given to [onRequest] first.
  OpenMeteoApiClient clientReturning(
    Object body, {
    int status = 200,
    void Function(http.BaseRequest request)? onRequest,
  }) => OpenMeteoApiClient(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(jsonEncode(body), status, request: request);
    }),
  );

  const GeocodedPlace london = GeocodedPlace(
    name: 'London',
    latitude: 51.5,
    longitude: -0.13,
    country: 'United Kingdom',
    admin1: 'England',
  );

  Map<String, Object?> forecastBody() => <String, Object?>{
    'current': <String, Object?>{
      'temperature_2m': 14.2,
      'apparent_temperature': 12.8,
      'relative_humidity_2m': 71,
      'wind_speed_10m': 11.0,
      'weather_code': 3,
      'is_day': 1,
    },
    'current_units': <String, Object?>{
      'temperature_2m': '°C',
      'wind_speed_10m': 'km/h',
    },
    'daily': <String, Object?>{
      'time': <String>['2026-10-07', '2026-10-08', '2026-10-09'],
      'temperature_2m_max': <double>[19.0, 17.5, 16.0],
      'temperature_2m_min': <double>[11.0, 10.5, 9.0],
      'precipitation_sum': <double>[0.0, 4.2, 1.0],
      'precipitation_probability_max': <int>[5, 80, 30],
      'weather_code': <int>[3, 63, 61],
    },
  };

  group('geocode', () {
    test('asks for one match and reads where it is', () async {
      http.BaseRequest? sent;
      final client = clientReturning(<String, Object?>{
        'results': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'London',
            'latitude': 51.50853,
            'longitude': -0.12574,
            'country': 'United Kingdom',
            'admin1': 'England',
          },
        ],
      }, onRequest: (r) => sent = r);

      final place = await client.geocode('London');

      check(sent?.url.host).equals('geocoding-api.open-meteo.com');
      check(sent?.url.queryParameters['name']).equals('London');
      check(sent?.url.queryParameters['count']).equals('1');
      check(place?.name).equals('London');
      check(place?.latitude).equals(51.50853);
      check(place?.label).equals('London, England, United Kingdom');
    });

    test('a name that places nowhere is null, not an error', () async {
      // Open-Meteo omits `results` entirely rather than sending an empty list.
      final client = clientReturning(<String, Object?>{
        'generationtime_ms': 0.4,
      });

      check(await client.geocode('Atlantis')).isNull();
    });

    test('an empty name is not worth a request', () async {
      final client = OpenMeteoApiClient(
        MockClient((_) async => throw StateError('must not call out')),
      );

      check(await client.geocode('   ')).isNull();
    });

    test('labels a place with only the parts it knows', () async {
      final client = clientReturning(<String, Object?>{
        'results': <Map<String, Object?>>[
          <String, Object?>{'name': 'Nowhere', 'latitude': 1, 'longitude': 2},
        ],
      });

      check((await client.geocode('Nowhere'))?.label).equals('Nowhere');
    });
  });

  group('forecast', () {
    test('asks for the current block, the days and the local clock', () async {
      http.BaseRequest? sent;
      final client = clientReturning(
        forecastBody(),
        onRequest: (r) => sent = r,
      );

      await client.forecast(london);

      final query = sent?.url.queryParameters ?? <String, String>{};
      check(sent?.url.host).equals('api.open-meteo.com');
      check(query['latitude']).equals('51.5');
      check(query['current'] ?? '').contains('apparent_temperature');
      check(query['daily'] ?? '').contains('precipitation_probability_max');
      // Local to the place, so "today" means today there.
      check(query['timezone']).equals('auto');
      // Metric is Open-Meteo's own default, so nothing is sent for it.
      check(query.containsKey('temperature_unit')).isFalse();
    });

    test('imperial switches all three units together', () async {
      http.BaseRequest? sent;
      final client = clientReturning(
        forecastBody(),
        onRequest: (r) => sent = r,
      );

      await client.forecast(london, metric: false);

      final query = sent?.url.queryParameters ?? <String, String>{};
      check(query['temperature_unit']).equals('fahrenheit');
      check(query['wind_speed_unit']).equals('mph');
      check(query['precipitation_unit']).equals('inch');
    });

    test('reads the conditions now and the days ahead', () async {
      final client = clientReturning(forecastBody());

      final weather = await client.forecast(london);

      check(weather.temperature).equals(14.2);
      check(weather.feelsLike).equals(12.8);
      check(weather.humidity).equals(71);
      check(weather.isDay).isTrue();
      check(weather.condition).equals('overcast');
      // The units come from the response rather than from what was asked
      // for, so the report quotes what the figures actually are.
      check(weather.temperatureUnit).equals('°C');
      check(weather.windUnit).equals('km/h');

      check(weather.days).length.equals(3);
      check(weather.days.first.maxTemp).equals(19.0);
      check(weather.days[1].precipitationChance).equals(80);
      check(weather.days[1].precipitationMm).equals(4.2);
    });

    test('takes no more days than were asked for', () async {
      final client = clientReturning(forecastBody());

      check(await client.forecast(london, dayCount: 2))
          .has((w) => w.days.length, 'days')
          .equals(2);
    });

    test('a response with no daily block still reports the present', () async {
      final client = clientReturning(<String, Object?>{
        'current': <String, Object?>{'temperature_2m': 9.0},
      });

      final weather = await client.forecast(london);

      check(weather.temperature).equals(9.0);
      check(weather.days).isEmpty();
      // No code at all is unknown, not clear sky — which code 0 would mean.
      check(weather.condition).equals('unknown conditions');
    });

    test('repeats the reason Open-Meteo gave for refusing', () async {
      final client = clientReturning(<String, Object?>{
        'error': true,
        'reason': 'Cannot initialize WeatherVariable from invalid String',
      }, status: 400);

      await check(client.forecast(london)).throws<OpenMeteoApiException>(
        (it) => it.has((e) => e.message, 'message').contains('WeatherVariable'),
      );
    });

    test('rate limiting is reported as temporary', () async {
      final client = clientReturning(<String, Object?>{}, status: 429);

      await check(client.forecast(london)).throws<OpenMeteoApiException>(
        (it) => it.has((e) => e.message, 'message').contains('Try again'),
      );
    });

    test('a body that is not JSON is not a forecast', () async {
      final client = OpenMeteoApiClient(
        MockClient((request) async => http.Response('<html>', 200)),
      );

      await check(client.forecast(london)).throws<OpenMeteoApiException>();
    });
  });
}

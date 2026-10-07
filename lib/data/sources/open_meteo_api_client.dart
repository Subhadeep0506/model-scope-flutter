import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/json_read.dart';
import '../models/weather_report.dart';

/// A call to Open-Meteo failed in a way worth telling the user — or the model —
/// about. Like the Tavily and Firecrawl exceptions, the message is written to
/// stand alone, because a tool hands it straight back to the model.
class OpenMeteoApiException implements Exception {
  const OpenMeteoApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin client over Open-Meteo: a place name to coordinates, and coordinates
/// to a forecast.
///
/// No API key and no credits, which is why this is the weather service the app
/// uses — nothing to store in Settings and nothing to spend.
class OpenMeteoApiClient {
  const OpenMeteoApiClient(this._client);

  final http.Client _client;

  static const String _geocodingHost = 'geocoding-api.open-meteo.com';
  static const String _forecastHost = 'api.open-meteo.com';

  /// What the current block asks for, in the order the report reads them.
  static const List<String> _current = <String>[
    'temperature_2m',
    'apparent_temperature',
    'relative_humidity_2m',
    'wind_speed_10m',
    'weather_code',
    'is_day',
  ];

  static const List<String> _daily = <String>[
    'temperature_2m_max',
    'temperature_2m_min',
    'precipitation_sum',
    'precipitation_probability_max',
    'weather_code',
  ];

  /// The best match for [name], or null when the geocoder places it nowhere.
  ///
  /// Null rather than an exception: one unknown name out of five is a line in
  /// the report, not a failed call.
  Future<GeocodedPlace?> geocode(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final response = await _get(
      Uri.https(_geocodingHost, '/v1/search', <String, String>{
        'name': trimmed,
        'count': '1',
        'format': 'json',
      }),
    );

    final results = readObjectList(_decodeObject(response.body)['results']);
    if (results.isEmpty) return null;
    return GeocodedPlace.fromJson(results.first);
  }

  /// Current conditions and the next [dayCount] days at [place].
  Future<LocationWeather> forecast(
    GeocodedPlace place, {
    bool metric = true,
    int dayCount = 3,
  }) async {
    final response = await _get(
      Uri.https(_forecastHost, '/v1/forecast', <String, String>{
        'latitude': '${place.latitude}',
        'longitude': '${place.longitude}',
        'current': _current.join(','),
        'daily': _daily.join(','),
        'forecast_days': '$dayCount',
        // Whatever the location's own clock says, so "today" means today
        // there rather than wherever the phone is.
        'timezone': 'auto',
        if (!metric) ...<String, String>{
          'temperature_unit': 'fahrenheit',
          'wind_speed_unit': 'mph',
          'precipitation_unit': 'inch',
        },
      }),
    );

    return LocationWeather.fromJson(
      _decodeObject(response.body),
      place: place,
      dayCount: dayCount,
    );
  }

  Future<http.Response> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri);
    } on SocketException {
      throw const OpenMeteoApiException(
        'No connection to the weather service.',
      );
    } on http.ClientException catch (error) {
      throw OpenMeteoApiException(
        'Could not reach the weather service: ${error.message}',
      );
    }

    return switch (response.statusCode) {
      200 => response,
      400 => throw OpenMeteoApiException(
        'The weather service rejected the request: ${_reasonOf(response.body)}',
      ),
      429 => throw const OpenMeteoApiException(
        'The weather service is rate-limiting this device. Try again in a '
        'moment.',
      ),
      _ => throw OpenMeteoApiException(
        'The weather service returned ${response.statusCode}.',
      ),
    };
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const OpenMeteoApiException(
        'The weather service returned something that was not JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const OpenMeteoApiException(
        'The weather service returned an unexpected response.',
      );
    }
    return decoded;
  }

  static String _reasonOf(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final reason = readStringOrNull(decoded['reason']);
        if (reason != null) return reason;
      }
    } on FormatException {
      // Not JSON. The generic sentence below is the honest answer.
    }
    return 'no reason given';
  }
}

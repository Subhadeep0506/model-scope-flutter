import 'dart:developer' as developer;

import '../../data/models/weather_report.dart';
import '../../data/sources/open_meteo_api_client.dart';

/// Weather for several places at once.
///
/// Unlike the web services beside it there is no key to read: Open-Meteo is
/// open, so this is always configured and the tool is never blocked.
class OpenMeteoWeatherService {
  const OpenMeteoWeatherService(this._client, {this.maxLocations = 5});

  final OpenMeteoApiClient _client;

  /// How many places one report covers. Five is a deliberate ceiling: each
  /// costs two requests and several lines of context, and a model with a few
  /// thousand tokens to spend cannot usefully compare more than a handful.
  final int maxLocations;

  static const String _logName = 'OpenMeteoWeatherService';

  /// Splits a comma-separated list into places, dropping blanks and repeats.
  ///
  /// `Paris, paris , Tokyo` is two places, not three: a small model asked for
  /// several cities will sometimes list one twice, and fetching it twice would
  /// spend a request to say the same thing again.
  List<String> parseLocations(String raw) {
    final seen = <String>{};
    final names = <String>[];
    for (final part in raw.split(RegExp(r'[,;\n]'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;
      names.add(trimmed);
      if (names.length == maxLocations) break;
    }
    return names;
  }

  /// The weather at every name in [raw] that could be placed.
  Future<WeatherReport> report(String raw, {bool metric = true}) async {
    final names = parseLocations(raw);
    if (names.isEmpty) {
      throw const OpenMeteoApiException(
        'A weather report needs at least one place name.',
      );
    }

    // Concurrently: five places one after another is five round trips of
    // latency on a phone, and they do not depend on each other.
    final found = await Future.wait(
      names.map((name) => _locate(name, metric: metric)),
    );

    final locations = <LocationWeather>[];
    final unresolved = <String>[];
    for (final (index, place) in found.indexed) {
      if (place == null) {
        unresolved.add(names[index]);
      } else {
        locations.add(place);
      }
    }

    if (locations.isEmpty) {
      throw OpenMeteoApiException(
        'None of those places could be found: ${unresolved.join(', ')}.',
      );
    }

    developer.log(
      'Reported on ${locations.length} of ${names.length} places',
      name: _logName,
    );
    return WeatherReport(locations: locations, unresolved: unresolved);
  }

  /// Geocode then forecast, or null when the name places nowhere.
  ///
  /// A failure on one place is swallowed to null rather than thrown: four
  /// cities and one apology beats no report at all.
  Future<LocationWeather?> _locate(String name, {required bool metric}) async {
    try {
      final place = await _client.geocode(name);
      if (place == null) return null;
      return await _client.forecast(place, metric: metric);
    } on OpenMeteoApiException catch (error) {
      developer.log('Could not report on $name: $error', name: _logName);
      return null;
    }
  }
}

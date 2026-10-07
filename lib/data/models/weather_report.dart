import 'json_read.dart';

/// Where a place name resolved to. Open-Meteo's forecast endpoint takes
/// coordinates only, so every name the user types costs a geocoding call
/// first, and the resolved name is what the report should quote back — the
/// user typed `Delhi`, the answer should say which Delhi it found.
class GeocodedPlace {
  const GeocodedPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.country,
    this.admin1,
  });

  factory GeocodedPlace.fromJson(Map<String, dynamic> json) => GeocodedPlace(
    name: readString(json['name']),
    latitude: readDouble(json['latitude']),
    longitude: readDouble(json['longitude']),
    country: readStringOrNull(json['country']),
    // The region within the country, e.g. `England`. Disambiguates the
    // dozen Springfields without quoting coordinates at the user.
    admin1: readStringOrNull(json['admin1']),
  );

  final String name;
  final double latitude;
  final double longitude;
  final String? country;
  final String? admin1;

  /// `Springfield, Illinois, United States` — as much as is known, no more.
  String get label => <String>[name, ?admin1, ?country].join(', ');
}

/// One day of the forecast.
class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.minTemp,
    required this.maxTemp,
    required this.precipitationMm,
    required this.precipitationChance,
    required this.weatherCode,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> daily, int index) {
    List<Object?> column(String key) {
      final values = daily[key];
      return values is List ? values : const <Object?>[];
    }

    Object? at(String key) {
      final values = column(key);
      return index < values.length ? values[index] : null;
    }

    return DailyForecast(
      date: readString(at('time')),
      minTemp: readDouble(at('temperature_2m_min')),
      maxTemp: readDouble(at('temperature_2m_max')),
      precipitationMm: readDouble(at('precipitation_sum')),
      precipitationChance: readInt(at('precipitation_probability_max')),
      weatherCode: readInt(at('weather_code'), fallback: -1),
    );
  }

  /// `2026-10-07`, as Open-Meteo gives it.
  final String date;

  final double minTemp;
  final double maxTemp;
  final double precipitationMm;

  /// Percent. Zero when the endpoint did not report one.
  final int precipitationChance;

  /// WMO code. -1 when absent, which [describeWeatherCode] reads as unknown.
  final int weatherCode;
}

/// The weather at one place: now, and the next few days.
class LocationWeather {
  const LocationWeather({
    required this.place,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.weatherCode,
    required this.isDay,
    required this.days,
    required this.temperatureUnit,
    required this.windUnit,
  });

  factory LocationWeather.fromJson(
    Map<String, dynamic> json, {
    required GeocodedPlace place,
    int dayCount = 3,
  }) {
    final current = readMap(json['current']);
    final units = readMap(json['current_units']);
    final daily = readMap(json['daily']);

    final times = daily['time'];
    final available = times is List ? times.length : 0;

    return LocationWeather(
      place: place,
      temperature: readDouble(current['temperature_2m']),
      feelsLike: readDouble(current['apparent_temperature']),
      humidity: readInt(current['relative_humidity_2m']),
      windSpeed: readDouble(current['wind_speed_10m']),
      weatherCode: readInt(current['weather_code'], fallback: -1),
      // Dark at 8am tells a traveller something a temperature does not.
      isDay: readInt(current['is_day'], fallback: 1) == 1,
      temperatureUnit: readString(units['temperature_2m'], fallback: '°'),
      windUnit: readString(units['wind_speed_10m'], fallback: ''),
      days: <DailyForecast>[
        for (var index = 0; index < available && index < dayCount; index++)
          DailyForecast.fromJson(daily, index),
      ],
    );
  }

  final GeocodedPlace place;
  final double temperature;
  final double feelsLike;

  /// Percent.
  final int humidity;

  final double windSpeed;

  /// WMO code. -1 when absent.
  final int weatherCode;

  final bool isDay;

  /// Today first. Empty when the endpoint returned no daily block.
  final List<DailyForecast> days;

  /// `°C` or `°F`, as the endpoint labelled it — rather than inferred from
  /// what was asked for, which would be a guess the response can settle.
  final String temperatureUnit;

  /// `km/h` or `mp/h`.
  final String windUnit;

  String get condition => describeWeatherCode(weatherCode);
}

/// Every location asked about, and the names that resolved to nothing.
class WeatherReport {
  const WeatherReport({required this.locations, this.unresolved = const []});

  final List<LocationWeather> locations;

  /// Names the geocoder could not place. Kept rather than dropped: a model
  /// told nothing about `Atlantis` would quietly report on four cities when
  /// it was asked about five.
  final List<String> unresolved;

  bool get isEmpty => locations.isEmpty;
}

/// The WMO weather code in words.
///
/// Open-Meteo reports conditions as a number, which means nothing to a
/// language model. The groupings are the ones the codes themselves define.
String describeWeatherCode(int code) => switch (code) {
  0 => 'clear sky',
  1 => 'mainly clear',
  2 => 'partly cloudy',
  3 => 'overcast',
  45 || 48 => 'fog',
  51 || 53 || 55 => 'drizzle',
  56 || 57 => 'freezing drizzle',
  61 => 'light rain',
  63 => 'rain',
  65 => 'heavy rain',
  66 || 67 => 'freezing rain',
  71 => 'light snow',
  73 => 'snow',
  75 => 'heavy snow',
  77 => 'snow grains',
  80 || 81 => 'rain showers',
  82 => 'violent rain showers',
  85 || 86 => 'snow showers',
  95 => 'thunderstorm',
  96 || 99 => 'thunderstorm with hail',
  _ => 'unknown conditions',
};

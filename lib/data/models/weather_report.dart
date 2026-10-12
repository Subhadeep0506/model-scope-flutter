import 'json_read.dart';

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

    admin1: readStringOrNull(json['admin1']),
  );

  final String name;
  final double latitude;
  final double longitude;
  final String? country;
  final String? admin1;

  String get label => <String>[name, ?admin1, ?country].join(', ');
}

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

  final String date;

  final double minTemp;
  final double maxTemp;
  final double precipitationMm;

  final int precipitationChance;

  final int weatherCode;
}

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

  final int humidity;

  final double windSpeed;

  final int weatherCode;

  final bool isDay;

  final List<DailyForecast> days;

  final String temperatureUnit;

  final String windUnit;

  String get condition => describeWeatherCode(weatherCode);
}

class WeatherReport {
  const WeatherReport({required this.locations, this.unresolved = const []});

  final List<LocationWeather> locations;

  final List<String> unresolved;

  bool get isEmpty => locations.isEmpty;
}

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

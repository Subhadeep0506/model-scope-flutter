library;

import '../../data/models/weather_report.dart';
import '../../data/sources/open_meteo_api_client.dart';
import '../services/open_meteo_weather_service.dart';
import 'tool_definition.dart';

/// Takes every place in one call rather than one call per place.
///
/// A small model asked about five cities reliably calls a one-city tool once
/// and then answers from memory for the other four. Handing it a list to pass
/// through removes the chance to get that wrong — and the agent runner only
/// counts a step as done when a tool was called at all, so a model that
/// stopped after the first city would still have passed the step.
ToolDefinition weatherTool(OpenMeteoWeatherService service) {
  Future<String> run({required String locations, required String units}) async {
    try {
      final report = await service.report(
        locations,
        metric: !units.toLowerCase().startsWith('imp'),
      );
      return formatWeatherReport(report);
    } on OpenMeteoApiException catch (error) {
      return 'The weather lookup failed. $error';
    }
  }

  return ToolDefinition(
    name: 'get_weather',
    description:
        'Get current conditions and a three-day forecast for one or more '
        'places. Pass every place you were asked about in a single call, '
        'separated by commas — do not call this once per place, and do not '
        'answer about the weather from memory.',
    function: run,
    parameterDescriptions: const <String, String>{
      'locations':
          'The places to report on, separated by commas, for example '
          '"London, Tokyo, New York". City names, not coordinates. At most '
          'five.',
      'units': 'Either "metric" for Celsius or "imperial" for Fahrenheit.',
    },
  );
}

/// The report as the plain text a model reads.
///
/// Laid out one place per block with labelled lines rather than as a table:
/// a small model copies a labelled figure across correctly far more often
/// than it reads one out of a column.
String formatWeatherReport(WeatherReport report) {
  if (report.isEmpty) {
    return 'No weather could be found for any of those places.';
  }

  final lines = <String>[];
  for (final location in report.locations) {
    lines.add('\n${location.place.label}');
    lines.add(
      '  Now: ${_round(location.temperature)}${location.temperatureUnit}, '
      '${location.condition}, feels like '
      '${_round(location.feelsLike)}${location.temperatureUnit}',
    );
    lines.add(
      '  Humidity ${location.humidity}%, wind '
      '${_round(location.windSpeed)}${location.windUnit}'
      '${location.isDay ? '' : ', after dark'}',
    );
    for (final (index, day) in location.days.indexed) {
      lines.add('  ${_dayLabel(index, day)}');
    }
  }

  if (report.unresolved.isNotEmpty) {
    lines.add(
      '\nThese places could not be found, and nothing is known about them: '
      '${report.unresolved.join(', ')}.',
    );
  }
  return lines.join('\n').trim();
}

/// `Today: 12 to 19, overcast, 80% chance of rain (4.2 of precipitation)`.
String _dayLabel(int index, DailyForecast day) {
  final name = switch (index) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => day.date,
  };
  final rain = day.precipitationChance > 0 || day.precipitationMm > 0
      ? ', ${day.precipitationChance}% chance of precipitation '
            '(${_round(day.precipitationMm)})'
      : ', no precipitation expected';
  return '$name: ${_round(day.minTemp)} to ${_round(day.maxTemp)}, '
      '${describeWeatherCode(day.weatherCode)}$rain';
}

/// One decimal place at most, and none when the value is whole — `19` rather
/// than `19.0`, which a model is apt to read as a precision it does not have.
String _round(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

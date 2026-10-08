import 'package:flutter/material.dart';

import 'generic_data_view.dart';
import 'price_table_view.dart';
import 'weather_forecast_view.dart';

/// Draws the JSON an agent's answer step returned.
///
/// An agent names one of these in its template as a plain string, and this
/// layer turns the string into a widget — the same arrangement `agentIconFor`
/// uses for icons, and for the same reason: a template is a JSON file that
/// `lib/data` must be able to parse without importing Flutter.
abstract interface class StructuredView {
  Widget build(BuildContext context, Map<String, dynamic> data);
}

/// The component for [name].
///
/// An unknown name falls back to [GenericDataView] rather than failing. Two
/// kinds of agent land there: one written by the user, which this build cannot
/// have a hand-made component for, and one written against a later build.
/// Both are better served by a plain table than by raw JSON.
StructuredView viewFor(String? name) => switch (name) {
  'price_table' => const PriceTableView(),
  'weather_forecast' => const WeatherForecastView(),
  _ => const GenericDataView(),
};

/// Whether [name] has a component written for it, as opposed to falling back.
/// Only the shipped-template test cares, so a typo in a built-in agent's view
/// name is caught before the phone is.
bool isKnownView(String? name) =>
    name == 'price_table' || name == 'weather_forecast';

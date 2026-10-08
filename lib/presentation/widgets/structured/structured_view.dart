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

/// One component an agent can name, for the builder's `DRAWN AS` picker.
class NamedView {
  const NamedView(this.name, this.label);

  /// What the template writes.
  final String name;

  /// What the picker shows.
  final String label;
}

/// Every component this build has, in the order the picker lists them.
///
/// An agent may name something not on this list — one written against a later
/// build, or a typo — and [viewFor] falls back to the generic table rather
/// than failing.
const List<NamedView> knownViews = <NamedView>[
  NamedView('price_table', 'Offers table'),
  NamedView('weather_forecast', 'Weather table and chart'),
];

/// Whether [name] has a component written for it, as opposed to falling back.
/// The builder greys out an unknown one, and the shipped-template test uses
/// this to catch a typo in a built-in agent before the phone does.
bool isKnownView(String? name) => knownViews.any((view) => view.name == name);

import 'package:flutter/material.dart';

import 'generic_data_view.dart';
import 'price_table_view.dart';
import 'weather_forecast_view.dart';

abstract interface class StructuredView {
  Widget build(BuildContext context, Map<String, dynamic> data);
}

StructuredView viewFor(String? name) => switch (name) {
  'price_table' => const PriceTableView(),
  'weather_forecast' => const WeatherForecastView(),
  _ => const GenericDataView(),
};

class NamedView {
  const NamedView(this.name, this.label);

  final String name;

  final String label;
}

const List<NamedView> knownViews = <NamedView>[
  NamedView('price_table', 'Offers table'),
  NamedView('weather_forecast', 'Weather table and chart'),
];

bool isKnownView(String? name) => knownViews.any((view) => view.name == name);

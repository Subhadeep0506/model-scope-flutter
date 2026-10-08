import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../data/models/json_read.dart';
import '../mono_label.dart';
import 'data_table_card.dart';
import 'headline_chips.dart';
import 'structured_view.dart';

/// Price Comparison's answer: the offers the model found, cheapest marked.
///
/// The cheapest row is tinted using the model's own `cheapest_retailer`
/// field rather than by this widget finding the lowest price itself. Picking
/// it out is the part of the job the agent exists to test; doing it here
/// would make the table always right and the measurement worthless.
class PriceTableView implements StructuredView {
  const PriceTableView();

  @override
  Widget build(BuildContext context, Map<String, dynamic> data) {
    final metrics = context.metrics;
    final offers = readObjectList(data['offers']);
    final currency = readString(data['currency']);
    final cheapest = readString(data['cheapest_retailer']);
    final product = readStringOrNull(data['product']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (product != null) ...<Widget>[
          Text(product, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: metrics.gapMd),
        ],
        HeadlineChips(
          headlines: <Headline>[
            Headline(label: 'Cheapest', value: cheapest, accent: true),
            Headline(
              label: 'Fastest',
              value: readString(data['best_for_speed']),
            ),
            Headline(label: 'Gap', value: _gap(data, currency)),
          ],
        ),
        SizedBox(height: metrics.gapLg),
        const MonoLabel('OFFERS', variant: MonoStyle.overline),
        SizedBox(height: metrics.gapSm),
        DataTableCard(
          columns: <DataField>[
            DataField(
              label: 'Retailer',
              flex: 3,
              cell: (row) => readString(row['retailer']),
            ),
            DataField(
              label: 'Price',
              flex: 2,
              numeric: true,
              cell: (row) => _price(row, currency),
            ),
            DataField(
              label: 'Shipping',
              flex: 2,
              cell: (row) => readString(row['shipping']),
            ),
            DataField(
              label: 'Stock',
              flex: 2,
              cell: (row) => readString(row['stock']),
            ),
          ],
          rows: offers,
          highlightRow: (row) =>
              cheapest.isNotEmpty &&
              readString(row['retailer']).toLowerCase() ==
                  cheapest.toLowerCase(),
          emptyMessage: 'The model found no offers to compare.',
        ),
      ],
    );
  }

  /// `₹ 25,750`, or whatever the model called the currency. Left empty when
  /// there is no number, so the cell draws a dash.
  static String _price(Map<String, dynamic> row, String currency) {
    final value = row['price'];
    if (value is! num) return readString(row['price']);
    return '${currency.isEmpty ? '' : '$currency '}${formatMoney(value)}';
  }

  static String _gap(Map<String, dynamic> data, String currency) {
    final value = data['price_gap'];
    if (value is! num || value == 0) return '';
    return '${currency.isEmpty ? '' : '$currency '}${formatMoney(value)}';
  }
}

/// `25750.5` → `25,750.50`, `25750` → `25,750`.
///
/// Thousands separated because a price column is there to be compared at a
/// glance, and trailing zeros dropped on a whole number because `₹ 25,750.00`
/// reads as more precision than a scraped price has.
String formatMoney(num value) {
  final rounded = (value * 100).round() / 100;
  final isWhole = rounded == rounded.truncateToDouble();
  final text = isWhole
      ? rounded.truncate().toString()
      : rounded.toStringAsFixed(2);

  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final rest = dot < 0 ? '' : text.substring(dot);

  final negative = whole.startsWith('-');
  final digits = negative ? whole.substring(1) : whole;

  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${negative ? '-' : ''}$grouped$rest';
}

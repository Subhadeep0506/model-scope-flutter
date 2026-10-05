import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import 'mono_label.dart';

/// A slider under a monospace caption with its value aligned to the right.
/// Shared by the Sampling sheet and the Runtime defaults card.
class LabelledSlider extends StatelessWidget {
  const LabelledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.range,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  /// Upper-case caption, e.g. `CONTEXT LENGTH`.
  final String label;

  final double value;

  /// The printed value, used for the label, tooltip and screen-reader
  /// announcement alike so all three agree.
  final String display;

  final (double, double) range;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: MonoLabel(label, variant: MonoStyle.sliderLabel)),
            MonoLabel(display, variant: MonoStyle.sliderValue),
          ],
        ),
        SizedBox(height: metrics.gapXs),
        Slider(
          value: value.clamp(range.$1, range.$2),
          min: range.$1,
          max: range.$2,
          divisions: divisions,
          label: display,
          semanticFormatterCallback: (_) => '$label $display',
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

/// Widens an integer range for a [LabelledSlider], which works in doubles.
(double, double) asDoubles((int, int) range) =>
    (range.$1.toDouble(), range.$2.toDouble());

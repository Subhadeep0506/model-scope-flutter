import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../view_models/agent_builder_state.dart';
import '../mono_label.dart';

/// What a step is wired to read.
///
/// The mockups draw this as a single-choice dropdown. It is a multi-select
/// here because the format stores a list and the shipped agents use it — the
/// Weather Report's answer reads two things at once, so a one-value control
/// could not express an agent this build ships with. It also lists earlier
/// steps as well as inputs, which the mockups do not.
class ReadsPicker extends StatelessWidget {
  const ReadsPicker({
    super.key,
    required this.available,
    required this.selected,
    required this.onToggle,
  });

  /// Everything this step may read: inputs, and the steps before it.
  final List<DraftReference> available;

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const MonoLabel('READS', variant: MonoStyle.overline),
        SizedBox(height: metrics.gapSm),
        if (available.isEmpty)
          Text(
            // The first step of an agent with no inputs. Saying so beats an
            // empty box the user taps at.
            'Nothing to read yet — add an input, or a step above this one.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          )
        else
          Wrap(
            spacing: metrics.gapSm,
            runSpacing: metrics.gapSm,
            children: <Widget>[
              for (final reference in available)
                _ReadChip(
                  reference: reference,
                  selected: selected.contains(reference.reference),
                  onTap: () => onToggle(reference.reference),
                ),
            ],
          ),
      ],
    );
  }
}

class _ReadChip extends StatelessWidget {
  const _ReadChip({
    required this.reference,
    required this.selected,
    required this.onTap,
  });

  final DraftReference reference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.pill : palette.fieldFill,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.radiusPill),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gapMd,
              vertical: metrics.gapSm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(metrics.radiusPill),
              border: Border.all(
                color: selected ? palette.primary : palette.outline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 14,
                  color: selected ? palette.primary : palette.muted,
                ),
                SizedBox(width: metrics.gapXs + 2),
                Text(
                  reference.label,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: selected ? palette.primary : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

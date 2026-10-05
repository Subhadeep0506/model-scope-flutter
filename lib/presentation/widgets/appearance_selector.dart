import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'section_card.dart';

/// The Dark / Light / System choice, drawn as a row of selectable cards.
/// System is a visible third tile, not an invisible default, because the app
/// starts there and an option you cannot get back to is a trap.
class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const List<(ThemeMode, String, IconData)> _options =
      <(ThemeMode, String, IconData)>[
        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
        (ThemeMode.system, 'System', Icons.phone_android_rounded),
      ];

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        for (final (mode, label, icon) in _options) ...<Widget>[
          Expanded(
            child: _ModeTile(
              label: label,
              icon: icon,
              selected: mode == value,
              onTap: () => onChanged(mode),
            ),
          ),
          if (mode != _options.last.$1) SizedBox(width: metrics.gapMd),
        ],
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final foreground = selected ? palette.primary : palette.ink;

    return Semantics(
      selected: selected,
      button: true,
      label: '$label appearance',
      child: SectionCard(
        onTap: onTap,
        color: selected ? palette.selectedTile : null,
        borderColor: selected ? palette.primary : null,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.gapSm,
          vertical: metrics.gapLg,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: foreground),
            SizedBox(width: metrics.gapSm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: foreground),
              ),
            ),
            if (selected) ...<Widget>[
              SizedBox(width: metrics.gapXs),
              Icon(Icons.check_rounded, size: 16, color: palette.primary),
            ],
          ],
        ),
      ),
    );
  }
}

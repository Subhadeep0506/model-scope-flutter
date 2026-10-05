import 'package:flutter/material.dart';

import 'mono_label.dart';

/// The Settings title block. The overline is a statement of fact, not
/// decoration: nothing signs in anywhere, and keys stay on the device.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const MonoLabel('LOCAL · NO ACCOUNT', variant: MonoStyle.overline),
        const SizedBox(height: 2),
        Text('Settings', style: Theme.of(context).textTheme.displaySmall),
      ],
    );
  }
}

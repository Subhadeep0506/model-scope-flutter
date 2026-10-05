import 'package:flutter/material.dart';

import 'mono_label.dart';

/// The Home title block. No model or quant is named: the dashboard reports on
/// every model in the library, not on the active one.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const MonoLabel('ON-DEVICE · NOBODYWHO', variant: MonoStyle.overline),
        const SizedBox(height: 2),
        Text('ModelScope', style: Theme.of(context).textTheme.displaySmall),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../widgets/mono_label.dart';

/// Stands in for a tab this part of the app does not implement.
///
/// This build exists to evaluate on-device generation, so only Chat is real.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(metrics.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const MonoLabel('NOT IN THIS BUILD', variant: MonoStyle.overline),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.displaySmall),
              SizedBox(height: metrics.gapLg),
              Text(
                'This part of the app focuses on chat generation with a local '
                'model. $title comes later.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

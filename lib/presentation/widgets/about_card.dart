import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'section_card.dart';

/// Version and runtime line at the foot of Settings.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  /// Kept in step with `pubspec.yaml`'s `version:` by hand.
  ///
  /// Reading it at runtime would mean `package_info_plus` and a platform
  /// channel for one string, which is not worth a dependency.
  static const String version = '0.0.1';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 18, color: palette.muted),
          SizedBox(width: metrics.gapSm),
          Expanded(
            child: Text(
              'Model Scope $version · inference by nobodywho (llama.cpp). '
              'Models run on this device; nothing is sent to a server.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

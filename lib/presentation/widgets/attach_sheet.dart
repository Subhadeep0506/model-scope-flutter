import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../domain/services/attachment_picker.dart';
import 'section_card.dart';
import 'sheet_scaffold.dart';

/// The Attach sheet: two branches, returning which one was chosen.
class AttachSheet extends StatelessWidget {
  const AttachSheet({super.key});

  static Future<AttachmentKind?> show(BuildContext context) =>
      SheetScaffold.show<AttachmentKind>(context, const AttachSheet());

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SheetScaffold(
      title: 'Attach',
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _AttachOption(
                kind: AttachmentKind.pdf,
                icon: Icons.description_outlined,
              ),
            ),
            SizedBox(width: metrics.gapMd),
            Expanded(
              child: _AttachOption(
                kind: AttachmentKind.image,
                icon: Icons.image_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({required this.kind, required this.icon});

  final AttachmentKind kind;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      button: true,
      label: 'Attach ${kind.label}',
      child: SectionCard(
        onTap: () => Navigator.of(context).pop(kind),
        padding: EdgeInsets.symmetric(vertical: metrics.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 24, color: palette.primary),
            SizedBox(height: metrics.gapSm),
            Text(kind.label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

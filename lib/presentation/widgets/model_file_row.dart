import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/catalog_model.dart';
import '../../data/models/gguf_file.dart';
import 'download_controls.dart';
import 'mono_chip.dart';
import 'mono_label.dart';
import 'section_card.dart';
import 'square_icon_button.dart';

/// One file in the model sheet: kind badge, quant, size, name, and the control
/// that acts on it.
///
/// Only weights get a download button. MMProj and adapter files are listed so
/// the repository's contents are not a mystery, but they cannot answer a prompt
/// on their own — downloading one would fail much later, inside the loader —
/// so theirs is an eye that explains what the file is for.
class ModelFileRow extends ConsumerWidget {
  const ModelFileRow({super.key, required this.model, required this.file});

  final CatalogModel model;
  final GgufFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final progress = ref.watch(
      downloadViewModelProvider.select((live) => live[file.id]),
    );
    final downloads = ref.read(downloadViewModelProvider.notifier);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Header(model: model, file: file, isBusy: progress != null),
          SizedBox(height: metrics.gapSm),
          MonoLabel(file.fileName, maxLines: 1),
          if (progress != null)
            DownloadControls(
              progress: progress,
              onPause: () => downloads.pause(file.id),
              onResume: () => downloads.resume(file.id),
              onCancel: () => downloads.cancel(file.id),
              onDismiss: () => downloads.dismiss(file.id),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.model,
    required this.file,
    required this.isBusy,
  });

  final CatalogModel model;
  final GgufFile file;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        MonoChip(file.kind.label),
        SizedBox(width: metrics.gapSm),
        // Expanded, not Flexible: a loose fit leaves its unused allocation as
        // slack at the end of the row, which pushes the size and the button
        // away from the card's edge by a width that varies with the quant.
        Expanded(
          child: MonoLabel(
            file.quantization,
            variant: MonoStyle.sliderValue,
            color: palette.primary,
            maxLines: 1,
          ),
        ),
        if (file.isHeavy) ...<Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: palette.warning,
            semanticLabel: 'Large file, may not load on this device',
          ),
          SizedBox(width: metrics.gapXs),
        ],
        MonoLabel(file.sizeLabel),
        SizedBox(width: metrics.gapMd),
        _Action(model: model, file: file, isBusy: isBusy),
      ],
    );
  }
}

class _Action extends ConsumerWidget {
  const _Action({
    required this.model,
    required this.file,
    required this.isBusy,
  });

  final CatalogModel model;
  final GgufFile file;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    if (!file.isDownloadable) {
      return SquareIconButton(
        icon: Icons.visibility_outlined,
        label: 'About ${file.fileName}',
        size: 40,
        foreground: palette.muted,
        borderColor: palette.outline,
        onPressed: () => _explain(context, file.kind),
      );
    }

    return SquareIconButton(
      icon: Icons.download_rounded,
      label: 'Download ${file.quantization}',
      size: 40,
      background: isBusy ? palette.primaryIdle : palette.primary,
      foreground: palette.onPrimary,
      // Null while a transfer is live: the controls below the row own it from
      // that point, and a second tap here would be a no-op the user can't see.
      onPressed: isBusy
          ? null
          : () => ref
                .read(downloadViewModelProvider.notifier)
                .start(model: model, file: file),
    );
  }

  static Future<void> _explain(BuildContext context, GgufFileKind kind) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${kind.label} file'),
        content: Text(_blurbOf(kind)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String _blurbOf(GgufFileKind kind) => switch (kind) {
    GgufFileKind.mmproj =>
      'A vision projector. It lets a model read images, but it holds no '
          'weights of its own and cannot answer a prompt, so it is listed here '
          'for reference rather than offered as a download.',
    GgufFileKind.adapter =>
      'An adapter. It adjusts a base model rather than replacing one, and this '
          'app loads whole models only, so it is listed here for reference '
          'rather than offered as a download.',
    GgufFileKind.model => 'Weights this app can download and load.',
  };
}

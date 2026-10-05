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

/// One file in the model sheet: kind badge, quant, size, name and its control.
/// Weights and projectors get a download button; adapters are listed for
/// reference, with an eye that explains what they are.
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
        // Expanded, not Flexible: a loose fit leaves slack at the end of the
        // row, pushing the size and button off the card's edge.
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

    // A repository holds one projector, so once it is in there is nothing
    // left to fetch — the row says so rather than offering the bytes again.
    final library = ref.watch(modelLibraryViewModelProvider).value;
    if (file.isProjector &&
        library?.projectorFor(file.repoId)?.fileName == file.fileName) {
      return Icon(
        Icons.check_rounded,
        size: 20,
        color: palette.primary,
        semanticLabel: '${file.fileName} is installed',
      );
    }

    return SquareIconButton(
      icon: Icons.download_rounded,
      label: 'Download ${file.quantization}',
      size: 40,
      background: isBusy ? palette.primaryIdle : palette.primary,
      foreground: palette.onPrimary,
      // Null while a transfer is live: the controls below the row own it then.
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
      'A vision projector. Download it alongside this repository\'s weights '
          'and every quant you have installed from here can read images.',
    GgufFileKind.adapter =>
      'An adapter. It adjusts a base model rather than replacing one, and this '
          'app loads whole models only, so it is listed here for reference '
          'rather than offered as a download.',
    GgufFileKind.model => 'Weights this app can download and load.',
  };
}

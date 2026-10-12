import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

class ImageThumbnail extends StatelessWidget {
  const ImageThumbnail({super.key, required this.path, this.onRemove});
  static const double size = 64;
  final String path;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final remove = onRemove;
    final radius = metrics.cardShape;

    return Semantics(
      image: true,
      label: 'Attached image',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: radius,
              child: _Picture(path: path),
            ),
            if (remove != null)
              Positioned(
                top: 0,
                right: 0,
                child: _RemoveButton(onPressed: remove),
              ),
          ],
        ),
      ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cache = (ImageThumbnail.size * 2).round();

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: cache,
      cacheHeight: cache,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => const _Missing(),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ColoredBox(
      color: palette.pill,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 20,
        color: palette.muted,
        semanticLabel: 'Image is no longer on this device',
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: 'Remove image',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Semantics(
          button: true,
          label: 'Remove image',
          child: Container(
            decoration: BoxDecoration(
              color: palette.ink.withValues(alpha: 0.65),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.close_rounded, size: 14, color: palette.surface),
          ),
        ),
      ),
    );
  }
}

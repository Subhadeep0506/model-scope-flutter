import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'square_icon_button.dart';

class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.titleAlign = TextAlign.center,
    this.action,
  }) : body = null;

  const SheetScaffold.body({
    super.key,
    required this.title,
    required Widget this.body,
    this.titleAlign = TextAlign.center,
    this.action,
  }) : children = const <Widget>[];

  final String title;
  final List<Widget> children;
  final Widget? body;

  final TextAlign titleAlign;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final custom = body;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SheetHeader(title: title, align: titleAlign, action: action),
            Flexible(
              child:
                  custom ??
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      metrics.pagePadding,
                      0,
                      metrics.pagePadding,
                      metrics.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: children,
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<T?> show<T>(BuildContext context, Widget child) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,

      useSafeArea: true,
      backgroundColor: context.palette.canvas,
      barrierColor: AppPalette.scrim,
      shape: RoundedRectangleBorder(borderRadius: context.metrics.sheetShape),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: _capped(child),
    );
  }

  static WidgetBuilder _capped(Widget child) =>
      (BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              context.metrics.sheetMaxHeightFactor,
        ),
        child: child,
      );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.align, this.action});

  final String title;
  final TextAlign align;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.gapMd,
        metrics.gapLg,
      ),
      child: Row(
        children: <Widget>[
          if (align == TextAlign.center) const SizedBox(width: 32),
          Expanded(
            child: Text(
              title,
              textAlign: align,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ?action,
          SizedBox(width: action == null ? 0 : metrics.gapSm),
          SquareIconButton(
            icon: Icons.close_rounded,
            label: 'Close',
            size: 32,
            iconSize: 18,
            foreground: palette.primary,
            borderColor: palette.primary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

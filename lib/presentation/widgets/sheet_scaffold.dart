import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'square_icon_button.dart';

/// Chrome shared by the Loaded models, Sampling and Attach sheets: a centred
/// title with an outlined close square in the top-right corner. The body
/// scrolls, so it survives large text scales and lifts clear of the keyboard.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.titleAlign = TextAlign.center,
    this.action,
  }) : body = null;

  /// For a sheet whose body scrolls itself — a lazy list, say — rather than
  /// one short enough to sit in a [SingleChildScrollView].
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

  /// Centred for the short titles — `Sampling`, `Attach` — and left for the
  /// model sheet, whose title is a model name long enough to wrap.
  final TextAlign titleAlign;

  /// An action between the title and the close square, for a sheet with
  /// something to do to its whole contents — the run log's `Copy all`. Most
  /// sheets have none.
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
      // Keeps the sheet out of the system bars' space, and the
      // `SafeArea(top: false)` inside handles the gesture bar.
      useSafeArea: true,
      backgroundColor: context.palette.canvas,
      barrierColor: AppPalette.scrim,
      shape: RoundedRectangleBorder(borderRadius: context.metrics.sheetShape),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: _capped(child),
    );
  }

  /// Bounds [child]'s height, which `isScrollControlled: true` otherwise
  /// leaves free: a scrolling body grows until its title sits under the status
  /// bar. Measured from the sheet's own context, not the opener's, since the
  /// two can disagree and it is the window's height that bounds a sheet.
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
          // Balances the close button so a centred title really does sit in
          // the middle of the sheet. A left-aligned one wants the width back.
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

import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'square_icon_button.dart';

/// Chrome shared by the Loaded models, Sampling and Attach sheets: a centred
/// title with an outlined close square in the top-right corner.
///
/// The body scrolls so the sheet still works at large system text scales and
/// lifts clear of the keyboard when a field inside it has focus.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.children})
    : body = null;

  /// For a sheet whose body scrolls itself — a lazy list, say — rather than
  /// one short enough to sit in a [SingleChildScrollView].
  const SheetScaffold.body({
    super.key,
    required this.title,
    required Widget this.body,
  }) : children = const <Widget>[];

  final String title;
  final List<Widget> children;
  final Widget? body;

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
            _SheetHeader(title: title),
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

  /// Opens [child] with the scrim, shape and background the mockups use.
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

  /// Bounds [child]'s height, which `isScrollControlled: true` otherwise leaves
  /// free: a sheet with a scrolling body grows until its title sits under the
  /// status bar, and `useSafeArea` alone does not stop that.
  ///
  /// The window is measured from the sheet's own context rather than the
  /// opener's. The two can disagree — the widget that opens a sheet may sit
  /// under a `MediaQuery` of its own — and the height that bounds a sheet is
  /// the window's.
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
  const _SheetHeader({required this.title});

  final String title;

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
          // Balances the close button so the title sits centred in the sheet.
          const SizedBox(width: 32),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
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

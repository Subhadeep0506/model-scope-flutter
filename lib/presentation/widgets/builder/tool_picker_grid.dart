import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/providers.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import 'labelled_field.dart';

/// What a tool is called on screen.
///
/// `web_search` is what a template writes and what the model is told; `Web
/// search` is what a person picking one should read. Lives here rather than on
/// the tool so `lib/domain` stays free of anything presentational, the same
/// split as `agentIconFor`. An unlisted tool falls back to its own name, so a
/// tool added later appears in the grid without being registered twice.
String toolLabelFor(String name) => switch (name) {
  'web_search' => 'Web search',
  'read_web_page' => 'Read a page',
  'get_weather' => 'Weather',
  'search_document' => 'Search a document',
  'calculator' => 'Calculator',
  'date_math' => 'Date maths',
  'unit_convert' => 'Convert units',
  _ => name,
};

IconData toolIconFor(String name) => switch (name) {
  'web_search' => Icons.search_rounded,
  'read_web_page' => Icons.public_rounded,
  'get_weather' => Icons.wb_sunny_outlined,
  'search_document' => Icons.description_outlined,
  'calculator' => Icons.calculate_outlined,
  'date_math' => Icons.event_outlined,
  'unit_convert' => Icons.straighten_rounded,
  _ => Icons.build_outlined,
};

/// The grid of tools a step can be given, and the warning when the chosen one
/// cannot run yet.
///
/// Two columns as the mockups draw it, but built from the registry rather than
/// the four tools they name — this build registers seven, and a grid that had
/// to be edited every time a tool was added would go stale.
class ToolPickerGrid extends ConsumerWidget {
  const ToolPickerGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final registry = ref.watch(toolRegistryProvider);
    final names = registry.names;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var row = 0; row < names.length; row += 2) ...<Widget>[
          if (row > 0) SizedBox(height: metrics.gapSm),
          Row(
            children: <Widget>[
              Expanded(
                child: _ToolTile(
                  name: names[row],
                  selected: names[row] == selected,
                  onTap: () => onSelected(names[row]),
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Expanded(
                child: row + 1 < names.length
                    ? _ToolTile(
                        name: names[row + 1],
                        selected: names[row + 1] == selected,
                        onTap: () => onSelected(names[row + 1]),
                      )
                    // An odd number of tools leaves a gap rather than a
                    // stretched last tile.
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
        if (selected != null) _Blocker(tool: selected ?? ''),
      ],
    );
  }
}

/// The amber `Needs Tavily key` line, asked of the registry.
///
/// A future rather than a value because readiness means reading the keychain,
/// and the answer changes while the builder is open — pasting a key into
/// Settings and coming back should clear it.
class _Blocker extends ConsumerWidget {
  const _Blocker({required this.tool});

  final String tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolRegistryProvider);

    return FutureBuilder<String?>(
      future: registry.blockerFor(tool),
      builder: (context, snapshot) {
        final blocker = snapshot.data;
        if (blocker == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: context.metrics.gapSm),
          child: BuilderWarning(text: blocker),
        );
      },
    );
  }
}

class _ToolTile extends ConsumerWidget {
  const _ToolTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    final description = ref
        .watch(toolRegistryProvider)
        .byName(name)
        ?.description;

    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: description ?? name,
        child: Material(
          color: selected ? palette.pill : palette.fieldFill,
          borderRadius: metrics.controlShape,
          child: InkWell(
            onTap: onTap,
            borderRadius: metrics.controlShape,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.gapMd,
                vertical: metrics.gapMd,
              ),
              decoration: BoxDecoration(
                borderRadius: metrics.controlShape,
                border: Border.all(
                  color: selected ? palette.primary : Colors.transparent,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    toolIconFor(name),
                    size: 16,
                    color: selected ? palette.primary : palette.muted,
                  ),
                  SizedBox(width: metrics.gapSm),
                  Expanded(
                    child: Text(
                      toolLabelFor(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: selected ? palette.primary : null),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

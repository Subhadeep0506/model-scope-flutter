import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/model_descriptor.dart';
import '../view_models/session_filter_view_model.dart';
import 'filter_dropdown.dart';
import 'section_card.dart';

/// Search field plus the model and time dropdowns, bound straight to
/// [sessionFilterProvider].
class SessionFilterBar extends ConsumerStatefulWidget {
  const SessionFilterBar({super.key});

  @override
  ConsumerState<SessionFilterBar> createState() => _SessionFilterBarState();
}

class _SessionFilterBarState extends ConsumerState<SessionFilterBar> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final filter = ref.watch(sessionFilterProvider);
    final notifier = ref.read(sessionFilterProvider.notifier);

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SearchField(controller: _search, onChanged: notifier.setQuery),
          SizedBox(height: metrics.gapMd),
          Row(
            children: <Widget>[
              Expanded(
                child: FilterDropdown<String?>(
                  icon: Icons.memory_rounded,
                  semanticLabel: 'Filter by model',
                  value: filter.modelId,
                  options: _modelOptions(ref),
                  onSelected: notifier.setModel,
                ),
              ),
              SizedBox(width: metrics.gapMd),
              Expanded(
                child: FilterDropdown<SessionTimeFilter>(
                  icon: Icons.calendar_today_rounded,
                  semanticLabel: 'Filter by date',
                  value: filter.time,
                  options: _timeOptions,
                  onSelected: notifier.setTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Only installed models are offered. Filtering by one that has been removed
  /// would be a dropdown entry that always returns nothing.
  static List<FilterOption<String?>> _modelOptions(WidgetRef ref) {
    final library = ref.watch(modelLibraryViewModelProvider).value;
    return <FilterOption<String?>>[
      (value: null, label: 'All models'),
      for (final model in library?.models ?? const <ModelDescriptor>[])
        (value: model.id, label: model.name),
    ];
  }

  static List<FilterOption<SessionTimeFilter>> get _timeOptions =>
      <FilterOption<SessionTimeFilter>>[
        for (final time in SessionTimeFilter.values)
          (value: time, label: time.label),
      ];
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search sessions',
        fillColor: palette.fieldFill,
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: palette.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: metrics.gapMd),
        // The search field reads as a soft fill with no hairline in the
        // mockup, unlike the outlined fields elsewhere.
        border: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: metrics.controlShape,
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
    );
  }
}

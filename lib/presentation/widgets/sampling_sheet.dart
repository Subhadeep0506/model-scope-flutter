import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../data/models/sampler_settings.dart';
import 'labelled_slider.dart';
import 'sheet_scaffold.dart';

/// The Sampling sheet: four monospace-labelled sliders, the system prompt, and
/// a reset.
class SamplingSheet extends ConsumerStatefulWidget {
  const SamplingSheet({super.key});

  static Future<void> show(BuildContext context) =>
      SheetScaffold.show<void>(context, const SamplingSheet());

  @override
  ConsumerState<SamplingSheet> createState() => _SamplingSheetState();
}

class _SamplingSheetState extends ConsumerState<SamplingSheet> {
  /// Long enough that a burst of typing is one write, short enough that the
  /// prompt is saved before the sheet is normally dismissed.
  static const Duration _typingPause = Duration(milliseconds: 500);

  final TextEditingController _prompt = TextEditingController();

  /// Held while a thumb is dragged, so the slider tracks the finger without a
  /// disk write and a model call on every frame.
  SamplerSettings? _draft;

  Timer? _promptTimer;
  bool _primed = false;

  @override
  void deactivate() {
    // Flush before the sheet leaves the tree, while `ref` is still usable.
    _flushPrompt();
    super.deactivate();
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  void _drag(SamplerSettings next) => setState(() => _draft = next);

  Future<void> _commit(SamplerSettings next) async {
    setState(() => _draft = null);
    await ref.read(samplerViewModelProvider.notifier).apply(next);
  }

  void _onPromptChanged(String value) {
    _promptTimer?.cancel();
    _promptTimer = Timer(_typingPause, _flushPrompt);
  }

  void _flushPrompt() {
    _promptTimer?.cancel();
    final notifier = ref.read(samplerViewModelProvider.notifier);
    unawaited(
      notifier.apply(notifier.current.copyWith(systemPrompt: _prompt.text)),
    );
  }

  Future<void> _reset() async {
    _promptTimer?.cancel();
    _prompt.text = SamplerSettings.defaultSystemPrompt;
    setState(() => _draft = null);
    await ref.read(samplerViewModelProvider.notifier).resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(samplerViewModelProvider).value;
    if (stored == null) {
      return const SheetScaffold(
        title: 'Sampling',
        children: <Widget>[Center(child: CircularProgressIndicator())],
      );
    }

    if (!_primed) {
      _primed = true;
      _prompt.text = stored.systemPrompt;
    }

    return SheetScaffold(
      title: 'Sampling',
      children: <Widget>[
        ..._sliders(_draft ?? stored),
        _SystemPromptField(
          controller: _prompt,
          onChanged: _onPromptChanged,
          onFocusLost: _flushPrompt,
        ),
        SizedBox(height: context.metrics.gapLg),
        OutlinedButton(
          onPressed: _reset,
          child: const Text('Reset to defaults'),
        ),
      ],
    );
  }

  List<Widget> _sliders(SamplerSettings settings) => <Widget>[
    LabelledSlider(
      label: 'TEMPERATURE',
      value: settings.temperature,
      display: settings.temperature.toStringAsFixed(2),
      range: SamplerSettings.temperatureRange,
      divisions: 40,
      onChanged: (v) => _drag(settings.copyWith(temperature: v)),
      onChangeEnd: (v) => _commit(settings.copyWith(temperature: v)),
    ),
    LabelledSlider(
      label: 'TOP_P',
      value: settings.topP,
      display: settings.topP.toStringAsFixed(2),
      range: SamplerSettings.topPRange,
      divisions: 20,
      onChanged: (v) => _drag(settings.copyWith(topP: v)),
      onChangeEnd: (v) => _commit(settings.copyWith(topP: v)),
    ),
    LabelledSlider(
      label: 'TOP_K',
      value: settings.topK.toDouble(),
      display: '${settings.topK}',
      range: asDoubles(SamplerSettings.topKRange),
      divisions: 99,
      onChanged: (v) => _drag(settings.copyWith(topK: v.round())),
      onChangeEnd: (v) => _commit(settings.copyWith(topK: v.round())),
    ),
    LabelledSlider(
      label: 'MAX_TOKENS',
      value: settings.maxTokens.toDouble(),
      display: '${settings.maxTokens}',
      range: asDoubles(SamplerSettings.maxTokensRange),
      divisions: 63,
      onChanged: (v) => _drag(settings.copyWith(maxTokens: v.round())),
      onChangeEnd: (v) => _commit(settings.copyWith(maxTokens: v.round())),
    ),
  ];
}

class _SystemPromptField extends StatelessWidget {
  const _SystemPromptField({
    required this.controller,
    required this.onChanged,
    required this.onFocusLost,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocusLost;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: metrics.gapSm),
        Text('System prompt', style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(height: metrics.gapSm),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) onFocusLost();
          },
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            onChanged: onChanged,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

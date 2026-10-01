import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/app_settings.dart';
import 'labelled_slider.dart';
import 'section_card.dart';

/// Context length, CPU threads and GPU offload.
///
/// Every control here is an argument to `Chat.fromPath`, so committing one
/// releases the loaded model — which is why the sliders only write on
/// `onChangeEnd` and track a local draft while a thumb is moving.
class RuntimeDefaultsCard extends ConsumerStatefulWidget {
  const RuntimeDefaultsCard({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<RuntimeDefaultsCard> createState() =>
      _RuntimeDefaultsCardState();
}

class _RuntimeDefaultsCardState extends ConsumerState<RuntimeDefaultsCard> {
  /// The slider's first slot means "let `nobodywho` count the cores", which is
  /// a real choice and the app's default — not a thread count of zero.
  static const (double, double) _threadRange = (0, 16);

  AppSettings? _draft;

  AppSettings get _shown => _draft ?? widget.settings;

  void _drag(AppSettings next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final notifier = ref.read(appSettingsViewModelProvider.notifier);
    final shown = _shown;
    final threads = shown.cpuThreads;

    return SectionCard(
      padding: EdgeInsets.fromLTRB(
        metrics.gapLg,
        metrics.gapLg,
        metrics.gapLg,
        metrics.gapSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LabelledSlider(
            label: 'CONTEXT LENGTH',
            value: shown.contextLength.toDouble(),
            display: '${shown.contextLength}',
            range: asDoubles(AppSettings.contextLengthRange),
            // 512-token steps across the range, matching how llama.cpp
            // actually allocates the KV cache.
            divisions: 15,
            onChanged: (v) => _drag(shown.copyWith(contextLength: v.round())),
            onChangeEnd: (v) {
              setState(() => _draft = null);
              notifier.setContextLength(v.round());
            },
          ),
          LabelledSlider(
            label: 'CPU THREADS',
            value: (threads ?? 0).toDouble(),
            display: threads == null ? 'AUTO' : '$threads',
            range: _threadRange,
            divisions: 16,
            onChanged: (v) => _drag(
              shown.copyWith(
                cpuThreads: v.round(),
                clearCpuThreads: v.round() == 0,
              ),
            ),
            onChangeEnd: (v) {
              setState(() => _draft = null);
              notifier.setCpuThreads(v.round() == 0 ? null : v.round());
            },
          ),
          SizedBox(height: metrics.gapSm),
          _GpuSwitch(value: shown.useGpu, onChanged: notifier.setUseGpu),
          SizedBox(height: metrics.gapSm),
        ],
      ),
    );
  }
}

class _GpuSwitch extends StatelessWidget {
  const _GpuSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('GPU acceleration', style: text.titleMedium),
              SizedBox(height: metrics.gapXs / 2),
              Text(
                // The mockup's GPU LAYERS slider has no counterpart in
                // nobodywho's API, which offers offload as all or nothing.
                'Offload layers to the GPU when the device supports it',
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
        SizedBox(width: metrics.gapSm),
        // Named here so a screen reader says what the switch is for, rather
        // than announcing a bare "switch" at the end of the row.
        Semantics(
          label: 'GPU acceleration',
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

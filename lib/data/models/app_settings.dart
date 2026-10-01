import 'package:flutter/material.dart' show ThemeMode;
import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

// Declared at library level for the same reason as in `sampler_settings.dart`:
// json_serializable copies default-value expressions verbatim into the
// generated part file, where a class-scoped name would not resolve.
const ThemeMode _themeMode = ThemeMode.system;
const int _contextLength = 4096;
const bool _useGpu = true;

/// Everything on the Settings screen that is not a sampling knob or an API key.
///
/// These map onto `Chat.fromPath` arguments rather than the sampler, which is
/// why changing one forces a model reload: unlike temperature, they cannot be
/// pushed onto a chat that is already running.
@JsonSerializable(fieldRename: FieldRename.snake)
class AppSettings {
  const AppSettings({
    this.themeMode = _themeMode,
    this.contextLength = _contextLength,
    this.cpuThreads,
    this.useGpu = _useGpu,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  static const int defaultContextLength = _contextLength;

  /// Slider range. The mockup's 4096 sits in the middle of this.
  static const (int, int) contextLengthRange = (512, 8192);

  /// `nobodywho` auto-detects the physical core count when given null, so the
  /// slider's minimum doubles as "leave it to the library".
  static const (int, int) cpuThreadsRange = (1, 16);

  final ThemeMode themeMode;

  /// Token budget for the model's context window.
  final int contextLength;

  /// CPU threads used for inference, or null to let `nobodywho` detect the
  /// device's physical core count — which is usually the right answer, since
  /// hyperthreads and efficiency cores make inference slower, not faster.
  final int? cpuThreads;

  /// Whether to offload to the GPU.
  ///
  /// The mockup draws a GPU LAYERS slider, but `nobodywho` exposes no layer
  /// count — only this switch — so a slider here would be a control that does
  /// nothing.
  final bool useGpu;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? contextLength,
    int? cpuThreads,
    bool clearCpuThreads = false,
    bool? useGpu,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    contextLength: contextLength ?? this.contextLength,
    cpuThreads: clearCpuThreads ? null : (cpuThreads ?? this.cpuThreads),
    useGpu: useGpu ?? this.useGpu,
  );

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          themeMode == other.themeMode &&
          contextLength == other.contextLength &&
          cpuThreads == other.cpuThreads &&
          useGpu == other.useGpu;

  @override
  int get hashCode => Object.hash(themeMode, contextLength, cpuThreads, useGpu);
}

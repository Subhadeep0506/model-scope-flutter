import 'package:flutter/material.dart' show ThemeMode;
import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

// Library level because json_serializable copies default-value expressions
// verbatim into the generated part, where a class-scoped name would not resolve.
const ThemeMode _themeMode = ThemeMode.system;
const int _contextLength = 4096;
const bool _useGpu = true;

/// Everything on the Settings screen that is not a sampling knob or an API key.
/// These map onto `Chat.fromPath` arguments, so changing one forces a model
/// reload — unlike temperature, they cannot be pushed onto a running chat.
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

  /// Null lets `nobodywho` detect the physical core count, usually the right
  /// answer: hyperthreads and efficiency cores make inference slower.
  final int? cpuThreads;

  /// A switch, not the mockup's GPU LAYERS slider, because `nobodywho` exposes
  /// no layer count — a slider here would control nothing.
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

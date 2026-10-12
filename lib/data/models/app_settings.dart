import 'package:flutter/material.dart' show ThemeMode;
import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

const ThemeMode _themeMode = ThemeMode.system;
const int _contextLength = 4096;
const bool _useGpu = true;

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

  static const (int, int) contextLengthRange = (512, 8192);

  static const (int, int) cpuThreadsRange = (1, 16);

  final ThemeMode themeMode;

  final int contextLength;

  final int? cpuThreads;

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

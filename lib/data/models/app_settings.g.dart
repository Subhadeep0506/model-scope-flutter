// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => AppSettings(
  themeMode:
      $enumDecodeNullable(_$ThemeModeEnumMap, json['theme_mode']) ?? _themeMode,
  contextLength: (json['context_length'] as num?)?.toInt() ?? _contextLength,
  cpuThreads: (json['cpu_threads'] as num?)?.toInt(),
  useGpu: json['use_gpu'] as bool? ?? _useGpu,
);

Map<String, dynamic> _$AppSettingsToJson(AppSettings instance) =>
    <String, dynamic>{
      'theme_mode': _$ThemeModeEnumMap[instance.themeMode]!,
      'context_length': instance.contextLength,
      'cpu_threads': instance.cpuThreads,
      'use_gpu': instance.useGpu,
    };

const _$ThemeModeEnumMap = {
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};

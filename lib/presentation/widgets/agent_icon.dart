import 'package:flutter/material.dart';

/// The glyph an agent template's `icon` token stands for.
///
/// Templates name an icon as a string so that `lib/data` never imports
/// Flutter — a template is a JSON file describing an agent, not a widget. This
/// is the one place those strings become glyphs, and an unknown one falls back
/// to the robot rather than throwing: a template written for a later build
/// should still draw.
IconData agentIconFor(String token) => switch (token) {
  'search' => Icons.search_rounded,
  'tag' => Icons.sell_outlined,
  'microscope' => Icons.biotech_outlined,
  'pulse' => Icons.monitor_heart_outlined,
  'weather' => Icons.wb_sunny_outlined,
  'document' => Icons.description_outlined,
  'braces' => Icons.data_object_rounded,
  'chat' => Icons.chat_bubble_outline_rounded,
  'bolt' => Icons.bolt_outlined,
  _ => Icons.smart_toy_outlined,
};

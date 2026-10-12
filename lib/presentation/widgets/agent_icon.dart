import 'package:flutter/material.dart';

const List<String> agentIconTokens = <String>[
  'search',
  'microscope',
  'tag',
  'weather',
  'document',
  'braces',
  'chat',
  'pulse',
  'bolt',
  'robot',
];

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

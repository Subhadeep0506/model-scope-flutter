import 'package:flutter/material.dart';

import 'mono_label.dart';

class AgentBenchHeader extends StatelessWidget {
  const AgentBenchHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      MonoLabel(
        '$count AGENT${count == 1 ? '' : 'S'} AVAILABLE',
        variant: MonoStyle.overline,
      ),
      const SizedBox(height: 2),
      Text('Agent bench', style: Theme.of(context).textTheme.displaySmall),
    ],
  );
}

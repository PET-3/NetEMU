import 'package:flutter/material.dart';

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (sub != null)
          Text(sub!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

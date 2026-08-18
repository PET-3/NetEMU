import 'package:flutter/material.dart';
import '../models/network_config.dart';

class DirectionCard extends StatelessWidget {
  final String title;
  final DirectionConfig config;
  final ValueChanged<DirectionConfig> onChanged;

  const DirectionCard({
    super.key,
    required this.title,
    required this.config,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _slider(
              context,
              label: '延迟',
              value: config.delayMs.toDouble(),
              min: 0,
              max: 60000,
              divisions: 120,
              display: '${config.delayMs} ms',
              onChanged: (v) => onChanged(config.copyWith(delayMs: v.round())),
            ),
            _slider(
              context,
              label: '抖动',
              value: config.jitterMs.toDouble(),
              min: 0,
              max: 60000,
              divisions: 120,
              display: '${config.jitterMs} ms',
              onChanged: (v) => onChanged(config.copyWith(jitterMs: v.round())),
            ),
            _slider(
              context,
              label: '带宽',
              value: config.bandwidthKbps.toDouble().clamp(0, 102400),
              min: 0,
              max: 102400,
              divisions: 200,
              display: config.bandwidthKbps == 0
                  ? '不限'
                  : (config.bandwidthKbps >= 1024
                      ? '${(config.bandwidthKbps / 1024).toStringAsFixed(1)} Mbps'
                      : '${config.bandwidthKbps} Kbps'),
              onChanged: (v) =>
                  onChanged(config.copyWith(bandwidthKbps: v.round())),
            ),
            _slider(
              context,
              label: '随机丢包',
              value: config.lossPercent,
              min: 0,
              max: 100,
              divisions: 100,
              display: '${config.lossPercent.toStringAsFixed(1)} %',
              onChanged: (v) =>
                  onChanged(config.copyWith(lossPercent: v)),
            ),
            const SizedBox(height: 8),
            Text('连续丢包 (放行/丢包)', style: theme.textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${config.continuousPass}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '放行',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (s) {
                      final v = int.tryParse(s) ?? 0;
                      onChanged(config.copyWith(continuousPass: v));
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('/'),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: '${config.continuousDrop}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '丢包',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (s) {
                      final v = int.tryParse(s) ?? 0;
                      onChanged(config.copyWith(continuousDrop: v));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(display, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

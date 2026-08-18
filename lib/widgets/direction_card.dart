import 'package:flutter/material.dart';
import '../models/network_config.dart';

/// Fixed bandwidth options in Kbps (0 = unlimited).
const kBandwidthOptions = <int>[
  0, 64, 128, 256, 512, 1024, 2048, 5120, 10240, 20480, 51200,
];

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
    final isTimeMode = config.continuousMode == ContinuousMode.time;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _slider(
              context,
              label: '延迟',
              value: config.delayMs.toDouble(),
              min: 0,
              max: 3000,
              divisions: 60,
              display: '${config.delayMs} ms',
              onChanged: (v) => onChanged(config.copyWith(delayMs: v.round())),
            ),
            _slider(
              context,
              label: '抖动',
              value: config.jitterMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 50,
              display: '${config.jitterMs} ms',
              onChanged: (v) => onChanged(config.copyWith(jitterMs: v.round())),
            ),
            // Bandwidth dropdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('带宽'),
                DropdownButton<int>(
                  value: kBandwidthOptions.contains(config.bandwidthKbps)
                      ? config.bandwidthKbps
                      : 0,
                  items: kBandwidthOptions.map((b) {
                    final label = b == 0
                        ? '不限速'
                        : (b >= 1024 ? '${b ~/ 1024} Mbps' : '$b Kbps');
                    return DropdownMenuItem(value: b, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(config.copyWith(bandwidthKbps: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _slider(
              context,
              label: '随机丢包',
              value: config.lossPercent,
              min: 0,
              max: 100,
              divisions: 100,
              display: '${config.lossPercent.toStringAsFixed(1)} %',
              onChanged: (v) => onChanged(config.copyWith(lossPercent: v)),
            ),
            const SizedBox(height: 8),
            // Continuous loss mode selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('连续丢包模式'),
                SegmentedButton<ContinuousMode>(
                  segments: const [
                    ButtonSegment(
                      value: ContinuousMode.packet,
                      label: Text('包数'),
                    ),
                    ButtonSegment(
                      value: ContinuousMode.time,
                      label: Text('时间'),
                    ),
                  ],
                  selected: {config.continuousMode},
                  onSelectionChanged: (s) {
                    onChanged(config.copyWith(continuousMode: s.first));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _slider(
              context,
              label: isTimeMode ? '放行时间' : '放行包数',
              value: config.continuousPass.toDouble(),
              min: 0,
              max: isTimeMode ? 10000 : 100,
              divisions: isTimeMode ? 100 : 50,
              display: isTimeMode
                  ? '${config.continuousPass} ms'
                  : '${config.continuousPass} 包',
              onChanged: (v) =>
                  onChanged(config.copyWith(continuousPass: v.round())),
            ),
            _slider(
              context,
              label: isTimeMode ? '丢包时间' : '丢包包数',
              value: config.continuousDrop.toDouble(),
              min: 0,
              max: isTimeMode ? 10000 : 100,
              divisions: isTimeMode ? 100 : 50,
              display: isTimeMode
                  ? '${config.continuousDrop} ms'
                  : '${config.continuousDrop} 包',
              onChanged: (v) =>
                  onChanged(config.copyWith(continuousDrop: v.round())),
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
            Text(display, style: Theme.of(context).textTheme.bodySmall),
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

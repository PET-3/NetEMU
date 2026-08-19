import 'package:flutter/material.dart';
import '../models/network_config.dart';
import 'param_editor.dart';
import 'param_infos.dart';

class DirectionCard extends StatelessWidget {
  final String title;
  final DirectionConfig config;
  final ValueChanged<DirectionConfig>? onChanged;
  final bool readOnly;

  const DirectionCard({
    super.key,
    required this.title,
    required this.config,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTime = config.continuousMode == ContinuousMode.time;

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
            ParamEditor(
              label: '延迟',
              value: config.delayMs.toDouble(),
              min: 0,
              max: 3000,
              divisions: 3000,
              unit: 'ms',
              readOnly: readOnly,
              info: ParamInfos.delay,
              onChanged: readOnly
                  ? null
                  : (v) => onChanged?.call(config.copyWith(delayMs: v.round())),
            ),
            ParamEditor(
              label: '抖动',
              value: config.jitterMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 1000,
              unit: 'ms',
              readOnly: readOnly,
              info: ParamInfos.jitter,
              onChanged: readOnly
                  ? null
                  : (v) =>
                      onChanged?.call(config.copyWith(jitterMs: v.round())),
            ),
            ParamEditor(
              label: '带宽',
              value: config.bandwidthKbps.toDouble(),
              min: 0,
              max: 51200,
              divisions: 512,
              unit: config.bandwidthKbps <= 0 ? '(不限)' : 'Kbps',
              readOnly: readOnly,
              info: ParamInfos.bandwidth,
              step: 64,
              onChanged: readOnly
                  ? null
                  : (v) => onChanged
                      ?.call(config.copyWith(bandwidthKbps: v.round())),
            ),
            ParamEditor(
              label: '随机丢包',
              value: config.lossPercent,
              min: 0,
              max: 100,
              divisions: 1000,
              unit: '%',
              isInt: false,
              step: 0.1,
              readOnly: readOnly,
              info: ParamInfos.loss,
              onChanged: readOnly
                  ? null
                  : (v) => onChanged?.call(config.copyWith(lossPercent: v)),
            ),
            if (!readOnly)
              Row(
                children: [
                  const Text('连续丢包'),
                  const Spacer(),
                  SegmentedButton<ContinuousMode>(
                    segments: const [
                      ButtonSegment(
                          value: ContinuousMode.packet, label: Text('包数')),
                      ButtonSegment(
                          value: ContinuousMode.time, label: Text('时间')),
                    ],
                    selected: {config.continuousMode},
                    onSelectionChanged: (s) {
                      onChanged
                          ?.call(config.copyWith(continuousMode: s.first));
                    },
                  ),
                ],
              ),
            ParamEditor(
              label: isTime ? '放行时间' : '放行包数',
              value: config.continuousPass.toDouble(),
              min: 0,
              max: isTime ? 10000 : 100,
              divisions: isTime ? 1000 : 100,
              unit: isTime ? 'ms' : '',
              readOnly: readOnly,
              info: ParamInfos.contPass,
              onChanged: readOnly
                  ? null
                  : (v) => onChanged
                      ?.call(config.copyWith(continuousPass: v.round())),
            ),
            ParamEditor(
              label: isTime ? '丢包时间' : '丢包包数',
              value: config.continuousDrop.toDouble(),
              min: 0,
              max: isTime ? 10000 : 100,
              divisions: isTime ? 1000 : 100,
              unit: isTime ? 'ms' : '',
              readOnly: readOnly,
              info: ParamInfos.contDrop,
              onChanged: readOnly
                  ? null
                  : (v) => onChanged
                      ?.call(config.copyWith(continuousDrop: v.round())),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';

/// Protocol filter + floating window toggles, to be placed on HomeScreen.
class ProtocolAndFloatSection extends StatelessWidget {
  const ProtocolAndFloatSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final cfg = ctrl.config;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('协议过滤',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<ProtocolFilter>(
              segments: const [
                ButtonSegment(value: ProtocolFilter.all, label: Text('全部')),
                ButtonSegment(value: ProtocolFilter.tcp, label: Text('仅TCP')),
                ButtonSegment(value: ProtocolFilter.udp, label: Text('仅UDP')),
              ],
              selected: {cfg.protocol},
              onSelectionChanged: (s) {
                ctrl.updateConfig(cfg.copyWith(protocol: s.first));
              },
            ),
            const SizedBox(height: 16),
            Text('悬浮窗',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '测试中可拖动调节参数，无需切回 App',
              style: theme.textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('控制悬浮窗'),
              subtitle: const Text('快速切换延迟/丢包预设'),
              value: cfg.showControlFloat,
              onChanged: (v) async {
                final next = cfg.copyWith(showControlFloat: v);
                ctrl.updateConfig(next);
                if (v) {
                  final ok = await ctrl.bridge.requestOverlayPermission();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请授予「显示在其他应用上层」权限')),
                    );
                  }
                  await ctrl.bridge.showControlFloat(v);
                } else {
                  await ctrl.bridge.showControlFloat(false);
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('信息悬浮窗'),
              subtitle: const Text('实时速度与丢包统计'),
              value: cfg.showInfoFloat,
              onChanged: (v) async {
                final next = cfg.copyWith(showInfoFloat: v);
                ctrl.updateConfig(next);
                if (v) {
                  final ok = await ctrl.bridge.requestOverlayPermission();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请授予「显示在其他应用上层」权限')),
                    );
                  }
                  await ctrl.bridge.showInfoFloat(v);
                } else {
                  await ctrl.bridge.showInfoFloat(false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

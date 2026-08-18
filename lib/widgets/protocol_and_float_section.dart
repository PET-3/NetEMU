import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';

/// 兼容旧组件：协议与浮窗开关（功能已分散到首页/测试页）
class ProtocolAndFloatSection extends StatelessWidget {
  const ProtocolAndFloatSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final cfg = ctrl.isTestMode ? ctrl.testConfig : ctrl.profileConfig;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ProtocolFilter>(
              segments: const [
                ButtonSegment(value: ProtocolFilter.all, label: Text('全')),
                ButtonSegment(value: ProtocolFilter.tcp, label: Text('TCP')),
                ButtonSegment(value: ProtocolFilter.udp, label: Text('UDP')),
              ],
              selected: {cfg.protocol},
              onSelectionChanged: (s) {
                final next = cfg.copyWith(protocol: s.first);
                ctrl.updateConfig(next);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('控制浮窗'),
              value: ctrl.showControlFloat,
              onChanged: (v) async {
                if (v) await ctrl.bridge.requestOverlayPermission();
                ctrl.setShowControlFloat(v);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('信息浮窗'),
              value: ctrl.showInfoFloat,
              onChanged: (v) async {
                if (v) await ctrl.bridge.requestOverlayPermission();
                ctrl.setShowInfoFloat(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

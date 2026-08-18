import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../widgets/direction_card.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';

/// 测试页：可调参数，相当于独立「自由调节」配置
class TestScreen extends StatelessWidget {
  const TestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final cfg = ctrl.testConfig;

    return Scaffold(
      appBar: AppBar(
        title: const Text('测试'),
        actions: [
          InfoIcon(title: '测试', message: ParamInfos.testMode),
          TextButton(
            onPressed: () => _saveDialog(context, ctrl),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('协议', style: Theme.of(context).textTheme.titleSmall),
              InfoIcon(title: '协议', message: ParamInfos.protocol),
              const Spacer(),
              SegmentedButton<ProtocolFilter>(
                segments: const [
                  ButtonSegment(value: ProtocolFilter.all, label: Text('全')),
                  ButtonSegment(value: ProtocolFilter.tcp, label: Text('TCP')),
                  ButtonSegment(value: ProtocolFilter.udp, label: Text('UDP')),
                ],
                selected: {cfg.protocol},
                onSelectionChanged: (s) {
                  ctrl.updateTestConfig(cfg.copyWith(protocol: s.first));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          DirectionCard(
            title: '上行',
            config: cfg.upload,
            onChanged: (c) =>
                ctrl.updateTestConfig(cfg.copyWith(upload: c)),
          ),
          const SizedBox(height: 12),
          DirectionCard(
            title: '下行',
            config: cfg.download,
            onChanged: (c) =>
                ctrl.updateTestConfig(cfg.copyWith(download: c)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDialog(
      BuildContext context, NetworkController ctrl) async {
    final nameCtrl = TextEditingController(text: '测试保存');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存到配置'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await ctrl.saveTestAsProfile(nameCtrl.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存并选中该配置')),
        );
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../widgets/direction_card.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';
import '../main.dart';

/// 调节页：临时模式或已选配置的参数调节
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  bool _dirty = false;
  NetworkConfig? _baseline;

  @override
  void initState() {
    super.initState();
    // Block parent PageView swipe while interacting with horizontal sliders.
    MainShellSwitch.setBlockSwipe?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<NetworkController>();
      ctrl.prepareAdjustEditor();
      _baseline = ctrl.testConfig;
      setState(() => _dirty = false);
    });
  }

  @override
  void dispose() {
    MainShellSwitch.setBlockSwipe?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final cfg = ctrl.runSource == RunSource.profile
        ? ctrl.profileConfig
        : ctrl.testConfig;
    final isTemp = ctrl.runSource == RunSource.test;
    final title = isTemp ? '调节 · 临时' : '调节 · ${ctrl.selectedProfileName ?? ""}';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await _confirmLeave(context);
        if (action == _LeaveAction.discard && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).maybePop();
        } else if (action == _LeaveAction.save && context.mounted) {
          await _saveFlow(context, ctrl);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            InfoIcon(title: '调节', message: ParamInfos.testMode),
            TextButton(
              onPressed: () => _saveFlow(context, ctrl),
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
                    ButtonSegment(
                        value: ProtocolFilter.all, label: Text('全')),
                    ButtonSegment(
                        value: ProtocolFilter.tcp, label: Text('TCP')),
                    ButtonSegment(
                        value: ProtocolFilter.udp, label: Text('UDP')),
                  ],
                  selected: {cfg.protocol},
                  onSelectionChanged: (s) {
                    _dirty = true;
                    ctrl.updateTestConfig(cfg.copyWith(protocol: s.first));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            DirectionCard(
              title: '上行',
              config: cfg.upload,
              onChanged: (c) {
                _dirty = true;
                ctrl.updateTestConfig(cfg.copyWith(upload: c));
              },
            ),
            const SizedBox(height: 12),
            DirectionCard(
              title: '下行',
              config: cfg.download,
              onChanged: (c) {
                _dirty = true;
                ctrl.updateTestConfig(cfg.copyWith(download: c));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<_LeaveAction?> _confirmLeave(BuildContext context) {
    return showDialog<_LeaveAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有未保存的修改'),
        content: const Text('退出将丢失当前调节，是否保存？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveAction.discard),
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _LeaveAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFlow(
      BuildContext context, NetworkController ctrl) async {
    final isProfile = ctrl.runSource == RunSource.profile &&
        ctrl.selectedProfileName != null;

    if (!isProfile) {
      // 临时模式：只能另存
      final name = await _askName(context, '临时保存');
      if (name == null || name.isEmpty) return;
      await ctrl.saveTestAsProfile(name);
      ctrl.setFlashProfile(name);
      _dirty = false;
      if (context.mounted) {
        MainShellSwitch.toProfiles(showAdjust: true);
      }
      return;
    }

    // 已选配置：弹窗1 替换 or 另存
    while (context.mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存修改'),
          content: Text('当前配置「${ctrl.selectedProfileName}」'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'as'),
              child: const Text('另存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('替换当前配置'),
            ),
          ],
        ),
      );

      if (choice == null || choice == 'cancel') return;

      if (choice == 'replace') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认替换'),
            content: Text('确定覆盖「${ctrl.selectedProfileName}」？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确认')),
            ],
          ),
        );
        if (ok == true) {
          final name = ctrl.selectedProfileName!;
          await ctrl.updateExistingProfile(
            ctrl.profileConfig.copyWith(name: name),
          );
          ctrl.setFlashProfile(name);
          _dirty = false;
          if (context.mounted) {
            MainShellSwitch.toProfiles(showAdjust: true);
          }
          return;
        }
        // 取消确认 → 回到弹窗1
        continue;
      }

      if (choice == 'as') {
        final name = await _askName(context, '新配置');
        if (name == null) continue; // back to dialog 1
        if (name.isEmpty) continue;
        await ctrl.saveTestAsProfile(name);
        ctrl.setFlashProfile(name);
        _dirty = false;
        if (context.mounted) {
          MainShellSwitch.toProfiles(showAdjust: true);
        }
        return;
      }
    }
  }

  Future<String?> _askName(BuildContext context, String initial) async {
    final nameCtrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
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
    if (ok == true) return nameCtrl.text.trim();
    return null; // cancelled
  }
}

enum _LeaveAction { save, discard }

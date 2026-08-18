import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../widgets/direction_bars.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';
import '../widgets/stat_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = ctrl.running;
    final source = ctrl.runSource;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NetEmu'),
        actions: [
          InfoIcon(title: '首页', message: ParamInfos.profile),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— 卡片0：悬浮窗 / 通知 / 最近任务 ——
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  title: const Text('控制浮窗'),
                  value: ctrl.showControlFloat,
                  onChanged: (v) async {
                    if (v) await ctrl.bridge.requestOverlayPermission();
                    ctrl.setShowControlFloat(v);
                  },
                  secondary: InfoIcon(
                      title: '控制浮窗', message: ParamInfos.floatControl),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('信息浮窗'),
                  value: ctrl.showInfoFloat,
                  onChanged: (v) async {
                    if (v) await ctrl.bridge.requestOverlayPermission();
                    ctrl.setShowInfoFloat(v);
                  },
                  secondary: InfoIcon(
                      title: '信息浮窗', message: ParamInfos.floatInfo),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('常驻通知'),
                  value: ctrl.showNotification,
                  onChanged: ctrl.setShowNotification,
                  secondary: InfoIcon(
                      title: '常驻通知', message: ParamInfos.notification),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('最近任务中隐藏'),
                  value: ctrl.hideFromRecents,
                  onChanged: ctrl.setHideFromRecents,
                  secondary: InfoIcon(
                      title: '最近任务', message: ParamInfos.hideRecent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // —— 卡片1：运行控制 ——
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 开始/停止：原状态图标变为按钮
                      IconButton.filledTonal(
                        iconSize: 36,
                        onPressed: () async {
                          if (!running && source == RunSource.none) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('请先选择测试或配置')),
                            );
                            return;
                          }
                          await ctrl.toggleRun();
                        },
                        icon: Icon(
                          running
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: running ? Colors.green : cs.outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              running ? '运行中' : '已停止',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              running
                                  ? (source == RunSource.test
                                      ? '测试 · ${ctrl.lockedBackend.label}'
                                      : '${ctrl.selectedProfileName ?? "-"} · ${ctrl.lockedBackend.label}')
                                  : ctrl.lockedBackend.label,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      InfoIcon(title: '运行', message: ParamInfos.backend),
                    ],
                  ),
                  if (!running) ...[
                    const SizedBox(height: 12),
                    // 未运行：测试 / 选择配置
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () {
                              ctrl.selectTestMode();
                              // 切到测试页：由 MainShell 监听 isTestMode
                              MainShellSwitch.toTest(context);
                            },
                            child: const Text('测试'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickProfile(context, ctrl),
                            child: Text(
                              source == RunSource.profile
                                  ? (ctrl.selectedProfileName ?? '配置')
                                  : '选择配置',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 运行后只显示来源名称（上面已显示），选择按钮已隐藏
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // —— 卡片2：参数图形化 ——
          if (source != RunSource.none)
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TitledRow(
                      title: '参数',
                      infoTitle: '参数图',
                      infoMessage: ParamInfos.stats,
                    ),
                    const SizedBox(height: 8),
                    DirectionBars(
                      upload: ctrl.config.upload,
                      download: ctrl.config.download,
                    ),
                  ],
                ),
              ),
            ),
          if (source != RunSource.none) const SizedBox(height: 12),

          // —— 卡片3：流量占比 + 丢包 ——
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TitledRow(
                    title: '流量',
                    infoTitle: '统计',
                    infoMessage: ParamInfos.stats,
                  ),
                  const SizedBox(height: 8),
                  TrafficShareBar(
                    uploadBytes: ctrl.stats.uploadBytes,
                    downloadBytes: ctrl.stats.downloadBytes,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '上传',
                          value: _fmtBytes(ctrl.stats.uploadBytes),
                          sub: _fmtSpeed(ctrl.stats.uploadSpeedBps),
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '下载',
                          value: _fmtBytes(ctrl.stats.downloadBytes),
                          sub: _fmtSpeed(ctrl.stats.downloadSpeedBps),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '随机丢包',
                          value: '${ctrl.stats.randomLossCount}',
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '连续丢包',
                          value: '${ctrl.stats.continuousLossCount}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProfile(
      BuildContext context, NetworkController ctrl) async {
    final profiles = ctrl.profiles;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无配置，请到配置页新建')),
      );
      return;
    }
    final picked = await showModalBottomSheet<NetworkConfig>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final p in profiles)
            ListTile(
              title: Text(p.name),
              subtitle: Text(
                  '↑${p.upload.delayMs}ms ↓${p.download.delayMs}ms'),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ctrl.selectProfile(picked);
    }
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}

/// 供首页「测试」按钮切换底部栏
class MainShellSwitch {
  static void Function(int index)? switchTab;

  static void toTest(BuildContext context) {
    switchTab?.call(1); // 测试页 index，由 MainShell 注册
  }
}

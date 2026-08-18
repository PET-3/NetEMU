import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../services/network_controller.dart';
import '../widgets/direction_card.dart';
import '../widgets/protocol_and_float_section.dart';
import '../widgets/stat_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);
    final readOnly = ctrl.isProfileSelected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络模拟器 NetEmu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.refreshBackends(),
            tooltip: '刷新后端状态',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        ctrl.running
                            ? Icons.play_circle_filled
                            : Icons.pause_circle_filled,
                        color: ctrl.running
                            ? Colors.green
                            : theme.colorScheme.outline,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ctrl.running ? '运行中' : '已停止',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '当前模式: ${ctrl.activeBackend.label}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (ctrl.recommendedReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ctrl.recommendedReason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 配置选中状态
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: readOnly
                          ? theme.colorScheme.secondaryContainer
                          : theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          readOnly ? Icons.lock_outline : Icons.tune,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            readOnly
                                ? '已选配置「${ctrl.selectedProfileName}」· 主页只读，按配置运行'
                                : '自由调节模式 · 可直接改参数',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (readOnly)
                          TextButton(
                            onPressed: () async {
                              await ctrl.clearProfileSelection();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('已进入自由调节模式')),
                                );
                              }
                            },
                            child: const Text('自由调节'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: ctrl.running
                              ? null
                              : () async {
                                  final ok = await ctrl.start();
                                  if (!context.mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('启动失败，请检查权限或日志'),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('开始'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: ctrl.running
                              ? () async {
                                  await ctrl.stop();
                                }
                              : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('停止'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 自由调节时才显示协议/悬浮窗开关编辑；只读时也显示当前协议
          if (!readOnly) const ProtocolAndFloatSection(),
          if (!readOnly) const SizedBox(height: 12),

          DirectionCard(
            title: '上行 (Upload)',
            config: ctrl.config.upload,
            readOnly: readOnly,
            onChanged: readOnly
                ? null
                : (c) => ctrl.updateConfig(ctrl.config.copyWith(upload: c)),
          ),
          const SizedBox(height: 12),
          DirectionCard(
            title: '下行 (Download)',
            config: ctrl.config.download,
            readOnly: readOnly,
            onChanged: readOnly
                ? null
                : (c) =>
                    ctrl.updateConfig(ctrl.config.copyWith(download: c)),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '上传',
                          value: _fmtBytes(ctrl.stats.uploadBytes),
                          sub:
                              '${_fmtSpeed(ctrl.stats.uploadSpeedBps)} · ${ctrl.stats.uploadPackets} pkts',
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '下载',
                          value: _fmtBytes(ctrl.stats.downloadBytes),
                          sub:
                              '${_fmtSpeed(ctrl.stats.downloadSpeedBps)} · ${ctrl.stats.downloadPackets} pkts',
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
                  const SizedBox(height: 8),
                  Text(
                    '后端: ${ctrl.stats.backend.isEmpty ? ctrl.activeBackend.label : ctrl.stats.backend}'
                    '  ·  接口: ${ctrl.stats.interfaceName.isEmpty ? "-" : ctrl.stats.interfaceName}'
                    '  ·  VPN: ${ctrl.stats.vpnActive ? "是" : "否"}'
                    '  ·  协议: ${ctrl.stats.protocolFilter}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '说明：此处速度为「模拟路径」统计（经 VPN/Emulator 的流量），'
                    '与系统状态栏/手机管家全网测速口径不同，数值不一致是正常现象。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

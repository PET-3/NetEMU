import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../services/network_controller.dart';

class BackendScreen extends StatelessWidget {
  const BackendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('后端选择')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('推荐模式', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    ctrl.recommendedReason,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('可用后端', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...ctrl.status.capabilities.map((c) {
            final selected = ctrl.config.backend == c.type.id ||
                (ctrl.config.backend == 'auto' &&
                    c.type == ctrl.status.recommended);
            return Card(
              elevation: 0,
              color: selected
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(
                  _icon(c.type),
                  color: c.available && c.authorized
                      ? Colors.green
                      : theme.colorScheme.outline,
                ),
                title: Text(c.type.label),
                subtitle: Text(
                  '${c.available ? "可用" : "不可用"} · ${c.authorized ? "已授权" : "未授权"}\n${c.message}',
                ),
                isThreeLine: true,
                trailing: selected
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  ctrl.setBackend(c.type);
                },
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => ctrl.refreshBackends(),
            child: const Text('重新检测'),
          ),
          const SizedBox(height: 24),
          Text('说明', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '• Root：最高权限，直接使用 tc/netem\n'
            '• Shizuku：无需 Root，通过 Shizuku 获取 shell 权限执行 tc\n'
            '• ADB Shell：开发者无线调试，适合调试场景；App 内直接执行受限时会导出命令\n'
            '• VPNService：无 Root 默认方案，通过 TUN 在用户态模拟延迟/丢包/限速\n\n'
            '优先级：Root > Shizuku > ADB > VPN',
          ),
        ],
      ),
    );
  }

  IconData _icon(BackendType t) {
    switch (t) {
      case BackendType.root:
        return Icons.security;
      case BackendType.shizuku:
        return Icons.extension;
      case BackendType.adb:
        return Icons.terminal;
      case BackendType.vpn:
        return Icons.vpn_lock;
      case BackendType.auto:
        return Icons.auto_awesome;
    }
  }
}

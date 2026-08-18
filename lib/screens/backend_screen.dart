import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../services/network_controller.dart';

/// 兼容旧入口：后端已迁至「设置」，此处保留避免分析报错。
class BackendScreen extends StatelessWidget {
  const BackendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('后端')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('请到「设置」管理后端（全局锁定）',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          ...ctrl.status.capabilities
              .where((c) => c.type != BackendType.auto)
              .map((c) {
            final selected = ctrl.lockedBackend == c.type;
            return ListTile(
              title: Text(c.type.label),
              subtitle: Text(c.message),
              selected: selected,
              onTap: () => ctrl.setLockedBackend(c.type),
            );
          }),
        ],
      ),
    );
  }
}

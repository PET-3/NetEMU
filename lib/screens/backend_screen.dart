import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '说明：\n'
                '· VPN：无 Root，推荐日常使用。\n'
                '· Root：直接 tc，效果最接近系统级。\n'
                '· Shizuku：当前版本未集成官方 API，因此不会出现在 Shizuku「授权应用」列表；'
                '在未接入库之前请用 Root / VPN / ADB 导出。\n'
                '· ADB：应用内不执行命令，请导出后在电脑运行。',
                style: theme.textTheme.bodySmall,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已选择 ${c.type.label}')),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => _exportAdb(context, ctrl),
            icon: const Icon(Icons.terminal),
            label: const Text('导出 ADB 命令（在电脑执行）'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAdb(
      BuildContext context, NetworkController ctrl) async {
    final cmds = await ctrl.bridge.exportAdbCommands();
    if (!context.mounted) return;
    final text = cmds.isEmpty
        ? '# 当前无延迟/丢包/限速参数，无需下发 tc'
        : cmds.join('\n');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ADB 命令'),
        content: SingleChildScrollView(
          child: SelectableText(text),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制')),
              );
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
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
        return Icons.computer;
      case BackendType.vpn:
        return Icons.vpn_key;
      case BackendType.auto:
        return Icons.auto_mode;
    }
  }
}

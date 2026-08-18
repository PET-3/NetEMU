import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../services/network_controller.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TitledRow(
            title: '后端（全局锁定）',
            infoTitle: '后端',
            infoMessage: ParamInfos.backend,
          ),
          const SizedBox(height: 8),
          ...ctrl.status.capabilities
              .where((c) => c.type != BackendType.auto)
              .map((c) {
            final selected = ctrl.lockedBackend == c.type;
            return Card(
              elevation: 0,
              color: selected
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                title: Text(c.type.label),
                subtitle: Text(
                  '${c.available ? "可用" : "不可用"} · ${c.message}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selected
                    ? Icon(Icons.lock, color: theme.colorScheme.primary)
                    : null,
                onTap: () => ctrl.setLockedBackend(c.type),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _exportAdb(context, ctrl),
            icon: const Icon(Icons.terminal),
            label: const Text('导出 ADB 命令'),
          ),
          const SizedBox(height: 24),
          TitledRow(title: '接口'),
          const SizedBox(height: 8),
          ...ctrl.interfaces.map((i) => Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  title: Text(i.name),
                  subtitle: Text('${i.type} · ${i.ip ?? "-"}'),
                  trailing: i.isDefault ? const Chip(label: Text('默认')) : null,
                ),
              )),
          TextButton(onPressed: ctrl.refreshBackends, child: const Text('刷新')),
          const SizedBox(height: 24),
          TitledRow(
            title: '日志',
            trailing: TextButton(
              onPressed: () {
                ctrl.clearLogs();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除')),
                );
              },
              child: const Text('清除'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: SizedBox(
              height: 220,
              child: ctrl.logs.isEmpty
                  ? const Center(child: Text('暂无日志'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: ctrl.logs.length,
                      itemBuilder: (_, i) => Text(
                        ctrl.logs[i],
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          TitledRow(title: '备份'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _export(context, ctrl),
                  child: const Text('导出'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _import(context, ctrl),
                  child: const Text('导入'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportAdb(
      BuildContext context, NetworkController ctrl) async {
    final cmds = await ctrl.bridge.exportAdbCommands();
    final text = cmds.isEmpty ? '# 无 tc 参数' : cmds.join('\n');
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ADB'),
        content: SelectableText(text),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: const Text('复制'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, NetworkController ctrl) async {
    final json = await ctrl.exportBackupJson();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出'),
        content: SingleChildScrollView(child: SelectableText(json)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
            },
            child: const Text('复制'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, NetworkController ctrl) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入'),
        content: TextField(
          controller: c,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('合并')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        final n = await ctrl.importBackupJson(c.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已导入 $n 条')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('失败: $e')));
        }
      }
    }
  }
}

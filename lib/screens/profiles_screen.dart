import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_controller.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('配置管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await ctrl.saveCurrentProfile();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已保存当前配置')),
                );
              }
            },
            tooltip: '保存当前配置',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: ctrl.profiles.length,
        itemBuilder: (context, i) {
          final p = ctrl.profiles[i];
          final active = p.name == ctrl.config.name;
          return Card(
            elevation: 0,
            color: active
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              title: Text(p.name),
              subtitle: Text(
                '上行: ${p.upload.delayMs}ms / ${p.upload.lossPercent}% · '
                '下行: ${p.download.delayMs}ms / ${p.download.lossPercent}%',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除配置'),
                          content: Text('确定删除「${p.name}」？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ctrl.deleteProfile(p.name);
                      }
                    },
                  ),
                ],
              ),
              onTap: () => ctrl.loadProfile(p),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ctrl),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, NetworkController ctrl) {
    final nameCtrl = TextEditingController(text: '自定义配置');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建配置'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final cfg = ctrl.config.copyWith(name: name);
              ctrl.updateConfig(cfg);
              ctrl.saveCurrentProfile();
              Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

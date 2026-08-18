import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../widgets/direction_card.dart';

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
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: '备份导出',
            onPressed: () => _exportBackup(context, ctrl),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '恢复导入',
            onPressed: () => _importBackup(context, ctrl),
          ),
        ],
      ),
      body: ctrl.profiles.isEmpty
          ? const Center(child: Text('暂无配置，点击下方新建'))
          : ListView.builder(
              // 底部留白，避免被 FAB 挡住删除按钮
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: ctrl.profiles.length,
              itemBuilder: (context, i) {
                final p = ctrl.profiles[i];
                final selected = ctrl.isProfileSelected &&
                    p.name == ctrl.selectedProfileName;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  color: selected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '↑ ${p.upload.delayMs}ms / ${p.upload.lossPercent}%  '
                            '↓ ${p.download.delayMs}ms / ${p.download.lossPercent}%\n'
                            '协议: ${p.protocol.name} · 后端: ${p.backend}',
                          ),
                          isThreeLine: true,
                          onTap: () async {
                            await ctrl.loadProfile(p);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('已选中「${p.name}」，主页只读运行')),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        // 操作行：避免挤在 trailing 被 FAB 挡住
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              if (selected)
                                Chip(
                                  avatar: Icon(Icons.check_circle,
                                      size: 16,
                                      color: theme.colorScheme.primary),
                                  label: const Text('使用中'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    _openEditor(context, ctrl, existing: p),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('修改'),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _confirmDelete(context, ctrl, p.name),
                                icon: Icon(Icons.delete_outline,
                                    size: 18, color: theme.colorScheme.error),
                                label: Text('删除',
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ctrl, existing: null),
        icon: const Icon(Icons.add),
        label: const Text('新建配置'),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, NetworkController ctrl, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除「$name」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await ctrl.deleteProfile(name);
    }
  }

  void _openEditor(BuildContext context, NetworkController ctrl,
      {NetworkConfig? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfileEditorPage(
          initial: existing ??
              NetworkConfig(
                name: '自定义配置',
                backend: ctrl.config.backend,
                upload: ctrl.config.upload,
                download: ctrl.config.download,
                protocol: ctrl.config.protocol,
              ),
          isNew: existing == null,
        ),
      ),
    );
  }

  Future<void> _exportBackup(
      BuildContext context, NetworkController ctrl) async {
    try {
      final json = await ctrl.exportBackupJson();
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备份配置'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(json),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: json));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _importBackup(
      BuildContext context, NetworkController ctrl) async {
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复配置'),
        content: TextField(
          controller: textCtrl,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: '粘贴备份 JSON',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入合并')),
        ],
      ),
    );
    if (ok != true || textCtrl.text.trim().isEmpty) return;
    try {
      final n = await ctrl.importBackupJson(textCtrl.text.trim(), merge: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 $n 条配置（按名称合并）')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }
}

/// 新建 / 修改配置全页编辑（含参数滑条+输入框）
class _ProfileEditorPage extends StatefulWidget {
  final NetworkConfig initial;
  final bool isNew;

  const _ProfileEditorPage({required this.initial, required this.isNew});

  @override
  State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  late TextEditingController _nameCtrl;
  late NetworkConfig _cfg;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
    _nameCtrl = TextEditingController(text: _cfg.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写名称')));
      return;
    }
    final ctrl = context.read<NetworkController>();
    final toSave = _cfg.copyWith(name: name);
    ctrl.forceUpdateConfig(toSave);
    await ctrl.saveCurrentProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isNew ? '已创建并选中「$name」' : '已保存「$name」')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '新建配置' : '修改配置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '配置名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('协议过滤', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ProtocolFilter>(
            segments: const [
              ButtonSegment(value: ProtocolFilter.all, label: Text('全部')),
              ButtonSegment(value: ProtocolFilter.tcp, label: Text('TCP')),
              ButtonSegment(value: ProtocolFilter.udp, label: Text('UDP')),
            ],
            selected: {_cfg.protocol},
            onSelectionChanged: (s) {
              setState(() => _cfg = _cfg.copyWith(protocol: s.first));
            },
          ),
          const SizedBox(height: 16),
          DirectionCard(
            title: '上行 (Upload)',
            config: _cfg.upload,
            onChanged: (c) => setState(() => _cfg = _cfg.copyWith(upload: c)),
          ),
          const SizedBox(height: 12),
          DirectionCard(
            title: '下行 (Download)',
            config: _cfg.download,
            onChanged: (c) =>
                setState(() => _cfg = _cfg.copyWith(download: c)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存配置'),
          ),
        ],
      ),
    );
  }
}

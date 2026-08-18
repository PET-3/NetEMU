import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/backend_status.dart';
import '../services/network_controller.dart';
import '../l10n/app_strings.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final s = context.watch<S>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— Backend ——

          // —— Backend ——
          TitledRow(
            title: s.backend,
            infoTitle: s.backend,
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

          Text(s.interfaces, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...ctrl.interfaces.map((i) => Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  title: Text(i.name),
                  subtitle: Text('${i.type} · ${i.ip ?? "-"}'),
                  trailing:
                      i.isDefault ? const Chip(label: Text('default')) : null,
                ),
              )),
          TextButton(
              onPressed: ctrl.refreshBackends,
              child: const Text('刷新')),
          const SizedBox(height: 24),

          TitledRow(
            title: s.logs,
            trailing: TextButton(
              onPressed: () {
                ctrl.clearLogs();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.clear)),
                );
              },
              child: Text(s.clear),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: SizedBox(
              height: 180,
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

          Text(s.backup, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _export(context, ctrl, s),
                  child: Text(s.export),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _import(context, ctrl, s),
                  child: Text(s.import_),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // —— About ——
          Text(s.about, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NetEmu',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(s.project),
                  SelectableText(
                    'https://github.com/PET-3/NetEMU',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(s.contact),
                  const SelectableText('Email: yyx3307022@gmail.com'),
                  const SelectableText('WeChat: yyx307022'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _exportAdb(
      BuildContext context, NetworkController ctrl) async {
    final cmds = await ctrl.bridge.exportAdbCommands();
    final text = cmds.isEmpty ? '# empty' : cmds.join('\n');
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
            child: const Text('Copy'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _export(
      BuildContext context, NetworkController ctrl, S s) async {
    final json = await ctrl.exportBackupJson();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.export),
        content: SingleChildScrollView(child: SelectableText(json)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _import(
      BuildContext context, NetworkController ctrl, S s) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.import_),
        content: TextField(
          controller: c,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.import_)),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        final n = await ctrl.importBackupJson(c.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('OK: $n')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }
}

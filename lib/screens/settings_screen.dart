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
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— 浮窗 / 通知（从首页移入）——
          Text('显示与通知', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
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
          const SizedBox(height: 24),

          // —— 图表 / 自适应 ——
          Text('统计与自适应', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  title: const Text('延迟 / 丢包曲线图'),
                  subtitle: const Text('首页显示简易采样曲线'),
                  value: ctrl.showCharts,
                  onChanged: ctrl.setShowCharts,
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('真实网络状态提示'),
                  subtitle: const Text(
                      '仅日志提示链路状态，不自动改弱网参数'),
                  value: ctrl.realNetworkAdaptive,
                  onChanged: ctrl.setRealNetworkAdaptive,
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('异常伪装（不可用）'),
                  subtitle: const Text(
                      '无法向应用同时谎报「正常网络」并实施弱网；VPN 会改变链路可见性'),
                  value: false,
                  onChanged: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

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
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              final ok = await ctrl.bridge.requestShizukuPermission();
              await ctrl.refreshBackends();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? '已发起 Shizuku 授权请求，请在弹窗中确认'
                          : '无法请求 Shizuku 授权（请先安装并启动 Shizuku）',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.verified_user),
            label: const Text('授权 Shizuku'),
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
              onPressed: ctrl.refreshBackends, child: const Text('刷新')),
          const SizedBox(height: 24),

          // —— 日志 ——
          TitledRow(
            title: s.logs,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    final text = ctrl.exportLogsText();
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制到剪贴板')),
                    );
                  },
                  child: const Text('导出'),
                ),
                TextButton(
                  onPressed: () {
                    ctrl.clearLogs();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.clear)),
                    );
                  },
                  child: Text(s.clear),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '自动保留最近 500 条，含时间戳与级别',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.outline),
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
                  const SizedBox(height: 8),
                  const Text('版本 1.1.0'),
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
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: const Text('复制'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定')),
        ],
      ),
    );
  }



}

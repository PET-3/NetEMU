import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/backend_status.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../services/profile_io.dart';
import '../widgets/direction_card.dart';
import '../main.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _flashCtrl;
  String? _flashingName;
  bool _multi = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _flashCtrl?.dispose();
    super.dispose();
  }

  void _ensureFlash(String? name) {
    if (name == null || name == _flashingName) return;
    _flashingName = name;
    _flashCtrl?.dispose();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    Future<void> run() async {
      await _flashCtrl!.forward();
      await _flashCtrl!.reverse();
      await _flashCtrl!.forward();
      await _flashCtrl!.reverse();
      if (mounted) {
        context.read<NetworkController>().clearFlashProfile();
        setState(() => _flashingName = null);
      }
    }
    run();
    setState(() {});
  }

  void _exitMulti() => setState(() {
        _multi = false;
        _selected.clear();
      });

  Future<void> _shareProfiles(
      BuildContext context, List<NetworkConfig> list) async {
    if (list.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: const Text('复制 JSON'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('分享 JSON 文件'),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('分享 ZIP（多文件）'),
              onTap: () => Navigator.pop(ctx, 'zip'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'copy') {
        final text = list.length == 1
            ? ProfileIo.encodeOne(list.first)
            : ProfileIo.encodeAll(list);
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制到剪贴板')),
          );
        }
      } else if (choice == 'json') {
        final f = await ProfileIo.writeJsonFile(list);
        await Share.shareXFiles([XFile(f.path)], text: 'NetEmu 配置');
      } else if (choice == 'zip') {
        final f = await ProfileIo.writeZip(list);
        await Share.shareXFiles([XFile(f.path)], text: 'NetEmu 配置包');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);
    if (ctrl.flashProfileName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureFlash(ctrl.flashProfileName);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_multi ? '已选 ${_selected.length}' : '配置'),
        leading: _multi
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMulti,
              )
            : null,
        actions: [
          if (_multi) ...[
            IconButton(
              tooltip: '分享',
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final list = ctrl.profiles
                          .where((p) => _selected.contains(p.name))
                          .toList();
                      _shareProfiles(context, list);
                    },
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: _selected.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('批量删除'),
                          content: Text('删除 ${_selected.length} 个配置？'),
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
                      if (ok == true) {
                        for (final n in _selected.toList()) {
                          await ctrl.deleteProfile(n);
                        }
                        _exitMulti();
                      }
                    },
              icon: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
            ),
          ] else
            IconButton(
              tooltip: '分享全部',
              onPressed: ctrl.profiles.isEmpty
                  ? null
                  : () => _shareProfiles(context, ctrl.profiles),
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: ctrl.profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('暂无配置'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => _openAdd(context, ctrl),
                    child: const Text('添加配置'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: ctrl.profiles.length,
              itemBuilder: (context, i) {
                final p = ctrl.profiles[i];
                final selected = ctrl.isProfileSelected &&
                    p.name == ctrl.selectedProfileName;
                final checked = _selected.contains(p.name);
                final isFlash =
                    p.name == _flashingName && _flashCtrl != null;

                Widget tile = Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  color: selected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      ListTile(
                        leading: _multi
                            ? Checkbox(
                                value: checked,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(p.name);
                                    } else {
                                      _selected.remove(p.name);
                                    }
                                  });
                                },
                              )
                            : null,
                        title: Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '↑${p.upload.delayMs}ms/${p.upload.lossPercent}%  '
                          '↓${p.download.delayMs}ms/${p.download.lossPercent}%',
                        ),
                        onTap: () async {
                          if (_multi) {
                            setState(() {
                              if (checked) {
                                _selected.remove(p.name);
                              } else {
                                _selected.add(p.name);
                              }
                            });
                            return;
                          }
                          await ctrl.selectProfile(p);
                          MainShellSwitch.toHome();
                        },
                        onLongPress: () {
                          setState(() {
                            _multi = true;
                            _selected.add(p.name);
                          });
                        },
                      ),
                      if (!_multi) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              if (selected)
                                const Chip(
                                  label: Text('使用中'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    _shareProfiles(context, [p]),
                                icon: const Icon(Icons.share_outlined,
                                    size: 18),
                                label: const Text('分享'),
                              ),
                              TextButton.icon(
                                onPressed: () => _edit(context, ctrl, p),
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                label: const Text('修改'),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _delete(context, ctrl, p.name),
                                icon: Icon(Icons.delete_outline,
                                    size: 18,
                                    color: theme.colorScheme.error),
                                label: Text('删除',
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                if (isFlash) {
                  tile = AnimatedBuilder(
                    animation: _flashCtrl!,
                    builder: (context, child) {
                      final t = _flashCtrl!.value;
                      final bg = Color.lerp(
                        theme.colorScheme.secondaryContainer,
                        theme.colorScheme.primaryContainer,
                        t,
                      );
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        color: bg,
                        child: (child as Card).child,
                      );
                    },
                    child: tile,
                  );
                }
                return tile;
              },
            ),
      floatingActionButton: _multi
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openAdd(context, ctrl),
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
    );
  }

  void _openAdd(BuildContext context, NetworkController ctrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const _AddProfilePage(),
    ));
  }

  Future<void> _delete(
      BuildContext context, NetworkController ctrl, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('删除「$name」？'),
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
    if (ok == true) await ctrl.deleteProfile(name);
  }

  void _edit(BuildContext context, NetworkController ctrl, NetworkConfig p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EditorPage(initial: p, isNew: false),
    ));
  }
}

/// 全屏：自定义 / JSON / ZIP 三种添加方式
class _AddProfilePage extends StatelessWidget {
  const _AddProfilePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.read<NetworkController>();
    return Scaffold(
      appBar: AppBar(title: const Text('添加配置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('选择来源', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _AddOption(
            icon: Icons.tune,
            title: '自定义',
            subtitle: '手动填写延迟、丢包、带宽等参数',
            onTap: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => _EditorPage(
                  initial: NetworkConfig(
                    name: '新配置',
                    backend: ctrl.lockedBackend.id,
                  ),
                  isNew: true,
                ),
              ));
            },
          ),
          const SizedBox(height: 12),
          _AddOption(
            icon: Icons.data_object,
            title: 'JSON',
            subtitle: '粘贴 JSON 文本，或从文件导入（单配置 / 备份包）',
            onTap: () => _importJson(context, ctrl),
          ),
          const SizedBox(height: 12),
          _AddOption(
            icon: Icons.folder_zip_outlined,
            title: 'ZIP',
            subtitle: '导入包含多个 .json 的压缩包',
            onTap: () => _importZip(context, ctrl),
          ),
        ],
      ),
    );
  }

  Future<void> _importJson(
      BuildContext context, NetworkController ctrl) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴 JSON'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('选择 JSON 文件'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    String? raw;
    if (choice == 'paste') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('粘贴 JSON'),
          content: TextField(
            controller: c,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '单配置或含 profiles 的备份 JSON',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('导入')),
          ],
        ),
      );
      if (ok == true) raw = c.text.trim();
    } else {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (r != null && r.files.isNotEmpty) {
        final f = r.files.first;
        raw = f.bytes != null
            ? String.fromCharCodes(f.bytes!)
            : (f.path != null ? await File(f.path!).readAsString() : null);
      }
    }
    if (raw == null || raw.isEmpty || !context.mounted) return;
    try {
      final n = await ctrl.importBackupJson(raw, merge: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入 $n 个配置')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _importZip(
      BuildContext context, NetworkController ctrl) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (r == null || r.files.isEmpty || !context.mounted) return;
    try {
      final f = r.files.first;
      final bytes = f.bytes ??
          (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) throw Exception('无法读取文件');
      final list = ProfileIo.parseZipBytes(bytes);
      if (list.isEmpty) throw Exception('ZIP 中未找到有效配置');
      final encoded = ProfileIo.encodeAll(list);
      final n = await ctrl.importBackupJson(encoded, merge: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已从 ZIP 导入 $n 个配置')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _AddOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EditorPage extends StatefulWidget {
  final NetworkConfig initial;
  final bool isNew;
  const _EditorPage({required this.initial, required this.isNew});

  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  late TextEditingController _nameCtrl;
  late NetworkConfig _cfg;
  late NetworkConfig _baseline;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
    _baseline = widget.initial;
    _nameCtrl = TextEditingController(text: _cfg.name);
    MainShellSwitch.setBlockSwipe?.call(true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    MainShellSwitch.setBlockSwipe?.call(false);
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final ctrl = context.read<NetworkController>();
    final toSave = _cfg.copyWith(name: name);
    if (widget.isNew) {
      await ctrl.createProfile(toSave);
      ctrl.setFlashProfile(name);
    } else {
      final fixed = toSave.copyWith(name: widget.initial.name);
      await ctrl.updateExistingProfile(fixed);
      ctrl.setFlashProfile(widget.initial.name);
    }
    _dirty = false;
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _onWillPop() async {
    if (!_dirty && _nameCtrl.text.trim() == _baseline.name) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有未保存的修改'),
        content: const Text('退出将丢失更改'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (action == 'save') {
      await _save();
      return false;
    }
    return action == 'exit';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? '新建' : '修改'),
          actions: [
            TextButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: widget.isNew,
              onChanged: (_) => _markDirty(),
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ProtocolFilter>(
              segments: const [
                ButtonSegment(value: ProtocolFilter.all, label: Text('全')),
                ButtonSegment(value: ProtocolFilter.tcp, label: Text('TCP')),
                ButtonSegment(value: ProtocolFilter.udp, label: Text('UDP')),
              ],
              selected: {_cfg.protocol},
              onSelectionChanged: (s) {
                _markDirty();
                setState(() => _cfg = _cfg.copyWith(protocol: s.first));
              },
            ),
            const SizedBox(height: 12),
            DirectionCard(
              title: '上行',
              config: _cfg.upload,
              onChanged: (c) {
                _markDirty();
                setState(() => _cfg = _cfg.copyWith(upload: c));
              },
            ),
            const SizedBox(height: 12),
            DirectionCard(
              title: '下行',
              config: _cfg.download,
              onChanged: (c) {
                _markDirty();
                setState(() => _cfg = _cfg.copyWith(download: c));
              },
            ),
          ],
        ),
      ),
    );
  }
}

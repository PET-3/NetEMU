import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
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
    // Two blinks: forward-reverse twice
    _flashCtrl!.forward().then((_) {
      return _flashCtrl!.reverse();
    }).then((_) {
      return _flashCtrl!.forward();
    }).then((_) {
      return _flashCtrl!.reverse();
    }).then((_) {
      if (mounted) {
        context.read<NetworkController>().clearFlashProfile();
        setState(() => _flashingName = null);
      }
    });
    setState(() {});
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
      appBar: AppBar(title: const Text('配置')),
      body: ctrl.profiles.isEmpty
          ? const Center(child: Text('暂无配置'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: ctrl.profiles.length,
              itemBuilder: (context, i) {
                final p = ctrl.profiles[i];
                final selected = ctrl.isProfileSelected &&
                    p.name == ctrl.selectedProfileName;
                final isFlash = p.name == _flashingName && _flashCtrl != null;

                Widget card = Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  color: selected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '↑${p.upload.delayMs}ms/${p.upload.lossPercent}%  '
                          '↓${p.download.delayMs}ms/${p.download.lossPercent}%',
                        ),
                        onTap: () async {
                          await ctrl.selectProfile(p);
                          MainShellSwitch.toHome();
                        },
                      ),
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
                              onPressed: () => _edit(context, ctrl, p),
                              icon: const Icon(Icons.edit_outlined, size: 18),
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
                  ),
                );

                if (isFlash) {
                  card = AnimatedBuilder(
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
                    child: card,
                  );
                }
                return card;
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ctrl),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
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

  void _create(BuildContext context, NetworkController ctrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EditorPage(
        initial: NetworkConfig(
          name: '新配置',
          backend: ctrl.lockedBackend.id,
        ),
        isNew: true,
      ),
    ));
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
      return false; // _save already pops
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

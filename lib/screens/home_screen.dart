import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_config.dart';
import '../services/network_controller.dart';
import '../widgets/direction_bars.dart';
import '../widgets/info_icon.dart';
import '../widgets/param_infos.dart';
import '../widgets/stat_tile.dart';
import '../main.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = ctrl.running;
    final source = ctrl.runSource;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NetEmu'),
        actions: [
          InfoIcon(title: '首页', message: ParamInfos.profile),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— 运行控制 ——
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filled(
                        iconSize: 36,
                        style: IconButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        onPressed: () async {
                          if (!running && source == RunSource.none) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('请先选择临时或配置')),
                            );
                            return;
                          }
                          await ctrl.toggleRun();
                        },
                        icon: Icon(
                          running
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              running ? '运行中' : '已停止',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              running
                                  ? (source == RunSource.test
                                      ? '临时 · ${ctrl.lockedBackend.label}'
                                      : '${ctrl.selectedProfileName ?? "-"} · ${ctrl.lockedBackend.label}')
                                  : ctrl.lockedBackend.label,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      InfoIcon(title: '运行', message: ParamInfos.backend),
                    ],
                  ),
                  if (!running) ...[
                    const SizedBox(height: 12),
                    _SourceButtons(ctrl: ctrl, source: source),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (source != RunSource.none)
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TitledRow(
                      title: '参数',
                      infoTitle: '参数图',
                      infoMessage: ParamInfos.stats,
                    ),
                    const SizedBox(height: 8),
                    DirectionBars(
                      upload: ctrl.config.upload,
                      download: ctrl.config.download,
                    ),
                  ],
                ),
              ),
            ),
          if (source != RunSource.none) const SizedBox(height: 12),

          if (ctrl.showCharts) ...[
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('延迟采样', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: _SimpleLineChart(
                        points: ctrl.latencyHistory,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('丢包累计', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: _SimpleLineChart(
                        points: ctrl.lossHistory,
                        color: cs.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TitledRow(
                    title: '流量',
                    infoTitle: '统计',
                    infoMessage: ParamInfos.stats,
                  ),
                  const SizedBox(height: 8),
                  TrafficShareBar(
                    uploadBytes: ctrl.stats.uploadBytes,
                    downloadBytes: ctrl.stats.downloadBytes,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '上传',
                          value: _fmtBytes(ctrl.stats.uploadBytes),
                          sub: _fmtSpeed(ctrl.stats.uploadSpeedBps),
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '下载',
                          value: _fmtBytes(ctrl.stats.downloadBytes),
                          sub: _fmtSpeed(ctrl.stats.downloadSpeedBps),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'TCP 连接',
                          value: '${ctrl.stats.tcpSessions}',
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: 'UDP 会话',
                          value: '${ctrl.stats.udpSessions}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '随机丢包',
                          value: '${ctrl.stats.randomLossCount}',
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '连续丢包',
                          value: '${ctrl.stats.continuousLossCount}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}

/// 临时 / 配置 选择按钮：未选等长灰色；选中蓝且 3/2，另一灰 1/2
class _SourceButtons extends StatelessWidget {
  final NetworkController ctrl;
  final RunSource source;

  const _SourceButtons({required this.ctrl, required this.source});

  Future<void> _pickProfile(BuildContext context) async {
    final profiles = ctrl.profiles;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无配置，请到配置页新建')),
      );
      return;
    }
    final picked = await showModalBottomSheet<NetworkConfig>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final p in profiles)
            ListTile(
              title: Text(p.name),
              subtitle:
                  Text('↑${p.upload.delayMs}ms ↓${p.download.delayMs}ms'),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ctrl.selectProfile(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final testSelected = source == RunSource.test;
    final profileSelected = source == RunSource.profile;
    final none = source == RunSource.none;

    // flex: equal 1:1 when none; selected 3, other 1
    final testFlex = none ? 1 : (testSelected ? 3 : 1);
    final profileFlex = none ? 1 : (profileSelected ? 3 : 1);

    Widget buildBtn({
      required bool selected,
      required String label,
      required VoidCallback onTap,
    }) {
      final bg = selected ? cs.primary : cs.surfaceContainerHigh;
      final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: testFlex,
          child: buildBtn(
            selected: testSelected,
            label: '临时',
            onTap: () {
              ctrl.selectTestMode();
              MainShellSwitch.toAdjust();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: profileFlex,
          child: buildBtn(
            selected: profileSelected,
            label: profileSelected
                ? (ctrl.selectedProfileName ?? '配置')
                : '选择配置',
            onTap: () => _pickProfile(context),
          ),
        ),
      ],
    );
  }
}

class _SimpleLineChart extends StatelessWidget {
  final List<double> points;
  final Color color;

  const _SimpleLineChart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text('运行后显示',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return CustomPaint(
      painter: _LinePainter(points: points, color: color),
      size: Size.infinite,
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  _LinePainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxV = points.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
      final y = size.height - (points[i] / maxV) * size.height * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points || old.color != color;
}

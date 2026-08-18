import 'package:flutter/material.dart';
import '../models/network_config.dart';

/// MD3 友好的上下行对比柱：中线上行、中线下行
class DirectionBars extends StatelessWidget {
  final DirectionConfig upload;
  final DirectionConfig download;

  /// 使用主题 primary / tertiary，避免刺眼纯红纯蓝
  const DirectionBars({
    super.key,
    required this.upload,
    required this.download,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final upColor = cs.primary;
    final downColor = cs.tertiary;

    final metrics = <_Metric>[
      _Metric('延迟', upload.delayMs.toDouble(), download.delayMs.toDouble(), 3000),
      _Metric('抖动', upload.jitterMs.toDouble(), download.jitterMs.toDouble(), 1000),
      _Metric(
        '丢包%',
        upload.lossPercent,
        download.lossPercent,
        100,
      ),
      _Metric(
        '带宽',
        upload.bandwidthKbps > 0 ? upload.bandwidthKbps.toDouble() : 0,
        download.bandwidthKbps > 0 ? download.bandwidthKbps.toDouble() : 0,
        51200,
      ),
    ];

    return Column(
      children: [
        for (final m in metrics)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                // 上行柱（向上）
                _HalfBar(
                  value: m.up,
                  max: m.max,
                  color: upColor,
                  upward: true,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        m.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const Spacer(),
                      Text(
                        '↑${_fmt(m.up, m.label)}  ↓${_fmt(m.down, m.label)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                // 下行柱（向下视觉：从顶对齐向下长）
                _HalfBar(
                  value: m.down,
                  max: m.max,
                  color: downColor,
                  upward: false,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmt(double v, String label) {
    if (label.startsWith('丢包')) return '${v.toStringAsFixed(0)}%';
    if (label == '带宽') {
      if (v <= 0) return '不限';
      if (v >= 1024) return '${(v / 1024).toStringAsFixed(1)}M';
      return '${v.toStringAsFixed(0)}K';
    }
    return '${v.toStringAsFixed(0)}ms';
  }
}

class _Metric {
  final String label;
  final double up;
  final double down;
  final double max;
  _Metric(this.label, this.up, this.down, this.max);
}

class _HalfBar extends StatelessWidget {
  final double value;
  final double max;
  final Color color;
  final bool upward;

  const _HalfBar({
    required this.value,
    required this.max,
    required this.color,
    required this.upward,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final h = 8.0 + 28.0 * ratio;
    return Align(
      alignment: upward ? Alignment.bottomCenter : Alignment.topCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: h,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// 上下行流量占比条
class TrafficShareBar extends StatelessWidget {
  final int uploadBytes;
  final int downloadBytes;

  const TrafficShareBar({
    super.key,
    required this.uploadBytes,
    required this.downloadBytes,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = uploadBytes + downloadBytes;
    final upR = total == 0 ? 0.5 : uploadBytes / total;
    final downR = total == 0 ? 0.5 : downloadBytes / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                Expanded(
                  flex: (upR * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: cs.primary.withValues(alpha: 0.85)),
                ),
                Expanded(
                  flex: (downR * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: cs.tertiary.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.arrow_upward, size: 14, color: cs.primary),
            Text(' 上传 ${(upR * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('下载 ${(downR * 100).toStringAsFixed(0)}% ',
                style: Theme.of(context).textTheme.labelSmall),
            Icon(Icons.arrow_downward, size: 14, color: cs.tertiary),
          ],
        ),
      ],
    );
  }
}

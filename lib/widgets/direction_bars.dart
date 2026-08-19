import 'package:flutter/material.dart';
import '../models/network_config.dart';

/// 分上下两部分的参数柱状图：
/// 上半 = 上行（从中线向上），下半 = 下行（从中线向下），带单位，随配置变化。
class DirectionBars extends StatelessWidget {
  final DirectionConfig upload;
  final DirectionConfig download;

  const DirectionBars({
    super.key,
    required this.upload,
    required this.download,
  });

  static const _barMaxH = 56.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final upColor = cs.primary;
    final downColor = cs.tertiary;
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    final items = <_Col>[
      _Col(
        name: '延迟',
        unit: 'ms',
        up: upload.delayMs.toDouble(),
        down: download.delayMs.toDouble(),
        max: 3000,
        fmt: (v) => v.round().toString(),
      ),
      _Col(
        name: '抖动',
        unit: 'ms',
        up: upload.jitterMs.toDouble(),
        down: download.jitterMs.toDouble(),
        max: 1000,
        fmt: (v) => v.round().toString(),
      ),
      _Col(
        name: '丢包',
        unit: '%',
        up: upload.lossPercent,
        down: download.lossPercent,
        max: 100,
        fmt: (v) => v.toStringAsFixed(0),
      ),
      _Col(
        name: '带宽',
        unit: 'Kbps',
        up: upload.bandwidthKbps > 0 ? upload.bandwidthKbps.toDouble() : 0,
        down:
            download.bandwidthKbps > 0 ? download.bandwidthKbps.toDouble() : 0,
        max: 51200,
        fmt: (v) {
          if (v <= 0) return '不限';
          if (v >= 1024) return '${(v / 1024).toStringAsFixed(1)}M';
          return v.round().toString();
        },
      ),
      _Col(
        name: '连丢放',
        unit: upload.continuousMode == ContinuousMode.time ? 'ms' : '包',
        up: upload.continuousPass.toDouble(),
        down: download.continuousPass.toDouble(),
        max: upload.continuousMode == ContinuousMode.time ? 10000 : 100,
        fmt: (v) => v.round().toString(),
      ),
      _Col(
        name: '连丢弃',
        unit: upload.continuousMode == ContinuousMode.time ? 'ms' : '包',
        up: upload.continuousDrop.toDouble(),
        down: download.continuousDrop.toDouble(),
        max: upload.continuousMode == ContinuousMode.time ? 10000 : 100,
        fmt: (v) => v.round().toString(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _legend(upColor, '上行'),
            const SizedBox(width: 12),
            _legend(downColor, '下行'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final c in items)
              Expanded(
                child: _MetricColumn(
                  col: c,
                  upColor: upColor,
                  downColor: downColor,
                  labelStyle: labelStyle,
                  barMaxH: _barMaxH,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _Col {
  final String name;
  final String unit;
  final double up;
  final double down;
  final double max;
  final String Function(double) fmt;

  _Col({
    required this.name,
    required this.unit,
    required this.up,
    required this.down,
    required this.max,
    required this.fmt,
  });
}

class _MetricColumn extends StatelessWidget {
  final _Col col;
  final Color upColor;
  final Color downColor;
  final TextStyle? labelStyle;
  final double barMaxH;

  const _MetricColumn({
    required this.col,
    required this.upColor,
    required this.downColor,
    required this.labelStyle,
    required this.barMaxH,
  });

  double _h(double v) {
    if (col.max <= 0) return 0;
    return (v / col.max).clamp(0.0, 1.0) * barMaxH;
  }

  @override
  Widget build(BuildContext context) {
    final upH = _h(col.up);
    final downH = _h(col.down);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            col.fmt(col.up),
            style: labelStyle?.copyWith(fontSize: 10, color: upColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(
            height: barMaxH,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: 14,
                height: upH < 2 && col.up > 0 ? 2 : (upH == 0 ? 0 : upH),
                decoration: BoxDecoration(
                  color: upColor.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                Text(col.name, style: labelStyle?.copyWith(fontSize: 10)),
                Text(
                  col.unit,
                  style: labelStyle?.copyWith(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: barMaxH,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: 14,
                height: downH < 2 && col.down > 0 ? 2 : (downH == 0 ? 0 : downH),
                decoration: BoxDecoration(
                  color: downColor.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Text(
            col.fmt(col.down),
            style: labelStyle?.copyWith(fontSize: 10, color: downColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 上传/下载流量占比动态条。
/// 无数据（初始）整条灰色；有流量后即使 1:1 也显示主色/第三色。
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
    final hasData = total > 0;
    final upR = hasData ? uploadBytes / total : 0.5;
    final downR = hasData ? downloadBytes / total : 0.5;
    final upFlex = (upR * 1000).round().clamp(1, 999);
    final downFlex = (downR * 1000).round().clamp(1, 999);
    final gray = cs.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 16,
            child: hasData
                ? Row(
                    children: [
                      Expanded(
                        flex: upFlex,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          color: cs.primary.withValues(alpha: 0.85),
                        ),
                      ),
                      Expanded(
                        flex: downFlex,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          color: cs.tertiary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  )
                : Container(color: gray),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.arrow_upward,
                size: 14, color: hasData ? cs.primary : gray),
            const SizedBox(width: 2),
            Text(
              hasData
                  ? '上传 ${(upR * 100).toStringAsFixed(0)}%'
                  : '上传 —',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const Spacer(),
            Text(
              hasData
                  ? '下载 ${(downR * 100).toStringAsFixed(0)}%'
                  : '下载 —',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_downward,
                size: 14, color: hasData ? cs.tertiary : gray),
          ],
        ),
      ],
    );
  }
}

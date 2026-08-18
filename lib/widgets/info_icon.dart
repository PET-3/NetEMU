import 'package:flutter/material.dart';

/// 紧凑 ⓘ，点击弹出说明，避免界面堆字。
class InfoIcon extends StatelessWidget {
  final String title;
  final String message;

  const InfoIcon({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(
        Icons.info_outline,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
      tooltip: title,
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 标题行 + 可选 ⓘ
class TitledRow extends StatelessWidget {
  final String title;
  final String? infoTitle;
  final String? infoMessage;
  final Widget? trailing;

  const TitledRow({
    super.key,
    required this.title,
    this.infoTitle,
    this.infoMessage,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (infoTitle != null && infoMessage != null)
          InfoIcon(title: infoTitle!, message: infoMessage!),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

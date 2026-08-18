import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_controller.dart';

/// 兼容旧入口：日志已迁至「设置」
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除')),
              );
            },
            child: const Text('清除'),
          ),
        ],
      ),
      body: ctrl.logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: ctrl.logs.length,
              itemBuilder: (_, i) => Text(
                ctrl.logs[i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
    );
  }
}

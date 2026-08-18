import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_controller.dart';

/// 兼容旧入口：接口列表已迁至「设置」。
class InterfacesScreen extends StatelessWidget {
  const InterfacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('接口'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.refreshBackends(),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: ctrl.interfaces.length,
        itemBuilder: (context, i) {
          final iface = ctrl.interfaces[i];
          return ListTile(
            title: Text(iface.name),
            subtitle: Text('${iface.type} · ${iface.ip ?? "-"}'),
            trailing: iface.isDefault ? const Chip(label: Text('默认')) : null,
            onTap: () {
              // 仅展示；接口选择若需要可在此扩展
            },
          );
        },
      ),
    );
  }
}

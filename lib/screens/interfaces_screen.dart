import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_controller.dart';

class InterfacesScreen extends StatelessWidget {
  const InterfacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<NetworkController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('接口管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.refreshBackends(),
          ),
        ],
      ),
      body: ctrl.interfaces.isEmpty
          ? const Center(child: Text('未检测到网络接口\n（VPN 模式下由系统自动处理）'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: ctrl.interfaces.length,
              itemBuilder: (context, i) {
                final iface = ctrl.interfaces[i];
                final selected =
                    ctrl.config.interfaceName == iface.name ||
                    (ctrl.config.interfaceName == null && iface.isDefault);
                return Card(
                  elevation: 0,
                  color: selected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(_typeIcon(iface.type)),
                    title: Text(iface.name),
                    subtitle: Text(
                      '${iface.type.toUpperCase()}'
                      '${iface.ip != null ? " · ${iface.ip}" : ""}'
                      '${iface.isDefault ? " · 默认出口" : ""}',
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle,
                            color: theme.colorScheme.primary)
                        : null,
                    onTap: () {
                      ctrl.updateConfig(
                        ctrl.config.copyWith(interfaceName: iface.name),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'wifi':
        return Icons.wifi;
      case 'mobile':
        return Icons.signal_cellular_alt;
      case 'vpn':
        return Icons.vpn_key;
      default:
        return Icons.device_hub;
    }
  }
}

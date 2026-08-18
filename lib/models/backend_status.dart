enum BackendType {
  auto,
  vpn,
  shizuku,
  adb,
  root,
}

extension BackendTypeExt on BackendType {
  String get label {
    switch (this) {
      case BackendType.auto:
        return 'Auto';
      case BackendType.vpn:
        return 'VPNService';
      case BackendType.shizuku:
        return 'Shizuku';
      case BackendType.adb:
        return 'ADB Shell';
      case BackendType.root:
        return 'Root';
    }
  }

  String get id => name;
}

class BackendCapability {
  final BackendType type;
  final bool available;
  final bool authorized;
  final String message;
  final int priority; // higher = better

  const BackendCapability({
    required this.type,
    required this.available,
    this.authorized = false,
    this.message = '',
    this.priority = 0,
  });
}

class BackendStatus {
  final BackendType active;
  final bool running;
  final List<BackendCapability> capabilities;
  final String recommendedReason;

  const BackendStatus({
    this.active = BackendType.vpn,
    this.running = false,
    this.capabilities = const [],
    this.recommendedReason = '',
  });

  BackendType get recommended {
    final sorted = List<BackendCapability>.from(capabilities)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (final c in sorted) {
      if (c.available && c.authorized) return c.type;
    }
    return BackendType.vpn;
  }
}

class NetworkInterfaceInfo {
  final String name;
  final String type; // wifi | mobile | vpn | other
  final String? ip;
  final bool isDefault;

  const NetworkInterfaceInfo({
    required this.name,
    required this.type,
    this.ip,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'ip': ip,
        'isDefault': isDefault,
      };

  factory NetworkInterfaceInfo.fromJson(Map<String, dynamic> json) {
    return NetworkInterfaceInfo(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'other',
      ip: json['ip'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

class SimulationStatistics {
  final int uploadBytes;
  final int downloadBytes;
  final double uploadSpeedBps;
  final double downloadSpeedBps;
  final int uploadPackets;
  final int downloadPackets;
  final int randomLossCount;
  final int continuousLossCount;
  final String backend;
  final String interfaceName;
  final bool vpnActive;
  final String protocolFilter;

  const SimulationStatistics({
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.uploadSpeedBps = 0,
    this.downloadSpeedBps = 0,
    this.uploadPackets = 0,
    this.downloadPackets = 0,
    this.randomLossCount = 0,
    this.continuousLossCount = 0,
    this.backend = '',
    this.interfaceName = '',
    this.vpnActive = false,
    this.protocolFilter = 'all',
  });

  factory SimulationStatistics.fromJson(Map<String, dynamic> json) {
    return SimulationStatistics(
      uploadBytes: (json['uploadBytes'] as num?)?.toInt() ?? 0,
      downloadBytes: (json['downloadBytes'] as num?)?.toInt() ?? 0,
      uploadSpeedBps: (json['uploadSpeedBps'] as num?)?.toDouble() ?? 0,
      downloadSpeedBps: (json['downloadSpeedBps'] as num?)?.toDouble() ?? 0,
      uploadPackets: (json['uploadPackets'] as num?)?.toInt() ?? 0,
      downloadPackets: (json['downloadPackets'] as num?)?.toInt() ?? 0,
      randomLossCount: (json['randomLossCount'] as num?)?.toInt() ?? 0,
      continuousLossCount: (json['continuousLossCount'] as num?)?.toInt() ?? 0,
      backend: json['backend'] as String? ?? '',
      interfaceName: json['interfaceName'] as String? ?? '',
      vpnActive: json['vpnActive'] as bool? ?? false,
      protocolFilter: json['protocolFilter'] as String? ?? 'all',
    );
  }
}

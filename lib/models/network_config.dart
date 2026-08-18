import 'dart:convert';

/// Direction-specific network simulation parameters.
class DirectionConfig {
  final int delayMs; // 0-60000
  final int jitterMs; // 0-60000
  final int bandwidthKbps; // 0 = unlimited
  final double lossPercent; // 0-100
  final int continuousPass; // consecutive packets to pass
  final int continuousDrop; // consecutive packets to drop

  const DirectionConfig({
    this.delayMs = 0,
    this.jitterMs = 0,
    this.bandwidthKbps = 0,
    this.lossPercent = 0.0,
    this.continuousPass = 0,
    this.continuousDrop = 0,
  });

  DirectionConfig copyWith({
    int? delayMs,
    int? jitterMs,
    int? bandwidthKbps,
    double? lossPercent,
    int? continuousPass,
    int? continuousDrop,
  }) {
    return DirectionConfig(
      delayMs: delayMs ?? this.delayMs,
      jitterMs: jitterMs ?? this.jitterMs,
      bandwidthKbps: bandwidthKbps ?? this.bandwidthKbps,
      lossPercent: lossPercent ?? this.lossPercent,
      continuousPass: continuousPass ?? this.continuousPass,
      continuousDrop: continuousDrop ?? this.continuousDrop,
    );
  }

  Map<String, dynamic> toJson() => {
        'delayMs': delayMs,
        'jitterMs': jitterMs,
        'bandwidthKbps': bandwidthKbps,
        'lossPercent': lossPercent,
        'continuousPass': continuousPass,
        'continuousDrop': continuousDrop,
      };

  factory DirectionConfig.fromJson(Map<String, dynamic> json) {
    return DirectionConfig(
      delayMs: json['delayMs'] as int? ?? 0,
      jitterMs: json['jitterMs'] as int? ?? 0,
      bandwidthKbps: json['bandwidthKbps'] as int? ?? 0,
      lossPercent: (json['lossPercent'] as num?)?.toDouble() ?? 0.0,
      continuousPass: json['continuousPass'] as int? ?? 0,
      continuousDrop: json['continuousDrop'] as int? ?? 0,
    );
  }

  bool get isActive =>
      delayMs > 0 ||
      jitterMs > 0 ||
      bandwidthKbps > 0 ||
      lossPercent > 0 ||
      (continuousPass > 0 && continuousDrop > 0);
}

/// Full simulation profile.
class NetworkConfig {
  final String name;
  final String backend; // auto | vpn | shizuku | adb | root
  final DirectionConfig upload;
  final DirectionConfig download;
  final String? interfaceName; // null = auto

  const NetworkConfig({
    this.name = 'Default',
    this.backend = 'auto',
    this.upload = const DirectionConfig(),
    this.download = const DirectionConfig(),
    this.interfaceName,
  });

  NetworkConfig copyWith({
    String? name,
    String? backend,
    DirectionConfig? upload,
    DirectionConfig? download,
    String? interfaceName,
  }) {
    return NetworkConfig(
      name: name ?? this.name,
      backend: backend ?? this.backend,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      interfaceName: interfaceName ?? this.interfaceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'backend': backend,
        'upload': upload.toJson(),
        'download': download.toJson(),
        'interfaceName': interfaceName,
      };

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    return NetworkConfig(
      name: json['name'] as String? ?? 'Default',
      backend: json['backend'] as String? ?? 'auto',
      upload: DirectionConfig.fromJson(
          Map<String, dynamic>.from(json['upload'] as Map? ?? {})),
      download: DirectionConfig.fromJson(
          Map<String, dynamic>.from(json['download'] as Map? ?? {})),
      interfaceName: json['interfaceName'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory NetworkConfig.fromJsonString(String s) =>
      NetworkConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

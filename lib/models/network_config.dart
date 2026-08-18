import 'dart:convert';

/// Continuous loss mode: by packet count or by time duration.
enum ContinuousMode {
  packet, // pass N packets / drop M packets
  time,   // pass N ms / drop M ms
}

/// Protocol filter for simulation.
enum ProtocolFilter {
  all,
  tcp,
  udp,
}

/// Direction-specific network simulation parameters.
class DirectionConfig {
  final int delayMs; // 0-3000
  final int jitterMs; // 0-1000
  final int bandwidthKbps; // 0 = unlimited
  final double lossPercent; // 0-100
  final ContinuousMode continuousMode;
  final int continuousPass; // packets (packet mode) or ms (time mode)
  final int continuousDrop; // packets (packet mode) or ms (time mode)

  const DirectionConfig({
    this.delayMs = 0,
    this.jitterMs = 0,
    this.bandwidthKbps = 0,
    this.lossPercent = 0.0,
    this.continuousMode = ContinuousMode.packet,
    this.continuousPass = 0,
    this.continuousDrop = 0,
  });

  DirectionConfig copyWith({
    int? delayMs,
    int? jitterMs,
    int? bandwidthKbps,
    double? lossPercent,
    ContinuousMode? continuousMode,
    int? continuousPass,
    int? continuousDrop,
  }) {
    return DirectionConfig(
      delayMs: delayMs ?? this.delayMs,
      jitterMs: jitterMs ?? this.jitterMs,
      bandwidthKbps: bandwidthKbps ?? this.bandwidthKbps,
      lossPercent: lossPercent ?? this.lossPercent,
      continuousMode: continuousMode ?? this.continuousMode,
      continuousPass: continuousPass ?? this.continuousPass,
      continuousDrop: continuousDrop ?? this.continuousDrop,
    );
  }

  Map<String, dynamic> toJson() => {
        'delayMs': delayMs,
        'jitterMs': jitterMs,
        'bandwidthKbps': bandwidthKbps,
        'lossPercent': lossPercent,
        'continuousMode': continuousMode.name,
        'continuousPass': continuousPass,
        'continuousDrop': continuousDrop,
      };

  factory DirectionConfig.fromJson(Map<String, dynamic> json) {
    final modeStr = json['continuousMode'] as String? ?? 'packet';
    final mode = ContinuousMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ContinuousMode.packet,
    );
    return DirectionConfig(
      delayMs: (json['delayMs'] as int? ?? 0).clamp(0, 3000),
      jitterMs: (json['jitterMs'] as int? ?? 0).clamp(0, 1000),
      bandwidthKbps: json['bandwidthKbps'] as int? ?? 0,
      lossPercent:
          ((json['lossPercent'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0),
      continuousMode: mode,
      continuousPass: (json['continuousPass'] as int? ?? 0).clamp(0, 10000),
      continuousDrop: (json['continuousDrop'] as int? ?? 0).clamp(0, 10000),
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
  final String? interfaceName;
  final ProtocolFilter protocol;
  final bool showControlFloat;
  final bool showInfoFloat;

  const NetworkConfig({
    this.name = 'Default',
    this.backend = 'auto',
    this.upload = const DirectionConfig(),
    this.download = const DirectionConfig(),
    this.interfaceName,
    this.protocol = ProtocolFilter.all,
    this.showControlFloat = false,
    this.showInfoFloat = false,
  });

  NetworkConfig copyWith({
    String? name,
    String? backend,
    DirectionConfig? upload,
    DirectionConfig? download,
    String? interfaceName,
    ProtocolFilter? protocol,
    bool? showControlFloat,
    bool? showInfoFloat,
  }) {
    return NetworkConfig(
      name: name ?? this.name,
      backend: backend ?? this.backend,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      interfaceName: interfaceName ?? this.interfaceName,
      protocol: protocol ?? this.protocol,
      showControlFloat: showControlFloat ?? this.showControlFloat,
      showInfoFloat: showInfoFloat ?? this.showInfoFloat,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'backend': backend,
        'upload': upload.toJson(),
        'download': download.toJson(),
        'interfaceName': interfaceName,
        'protocol': protocol.name,
        'showControlFloat': showControlFloat,
        'showInfoFloat': showInfoFloat,
      };

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    final protoStr = json['protocol'] as String? ?? 'all';
    final protocol = ProtocolFilter.values.firstWhere(
      (e) => e.name == protoStr,
      orElse: () => ProtocolFilter.all,
    );
    return NetworkConfig(
      name: json['name'] as String? ?? 'Default',
      backend: json['backend'] as String? ?? 'auto',
      upload: DirectionConfig.fromJson(
          Map<String, dynamic>.from(json['upload'] as Map? ?? {})),
      download: DirectionConfig.fromJson(
          Map<String, dynamic>.from(json['download'] as Map? ?? {})),
      interfaceName: json['interfaceName'] as String?,
      protocol: protocol,
      showControlFloat: json['showControlFloat'] as bool? ?? false,
      showInfoFloat: json['showInfoFloat'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory NetworkConfig.fromJsonString(String s) =>
      NetworkConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

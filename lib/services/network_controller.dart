import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/backend_status.dart';
import '../models/network_config.dart';
import 'native_bridge.dart';
import 'config_service.dart';

class NetworkController extends ChangeNotifier {
  final NativeBridge bridge = NativeBridge();
  final ConfigService configService = ConfigService();

  NetworkConfig _config = const NetworkConfig();
  BackendStatus _status = const BackendStatus();
  SimulationStatistics _stats = const SimulationStatistics();
  List<NetworkInterfaceInfo> _interfaces = [];
  List<NetworkConfig> _profiles = [];
  List<String> _logs = [];
  bool _initialized = false;
  bool _running = false;
  String _recommendedReason = '';

  NetworkConfig get config => _config;
  BackendStatus get status => _status;
  SimulationStatistics get stats => _stats;
  List<NetworkInterfaceInfo> get interfaces => _interfaces;
  List<NetworkConfig> get profiles => _profiles;
  List<String> get logs => _logs;
  bool get initialized => _initialized;
  bool get running => _running;
  String get recommendedReason => _recommendedReason;
  BackendType get activeBackend => _status.active;

  Future<void> initialize() async {
    if (_initialized) return;
    bridge.startListening();
    bridge.statisticsStream.listen((s) {
      _stats = s;
      notifyListeners();
    });
    bridge.logStream.listen((msg) {
      _addLog(msg);
    });

    await _detect();
    _profiles = await configService.loadProfiles();
    if (_profiles.isEmpty) {
      _profiles = List.from(ConfigService.presets);
      await configService.saveProfiles(_profiles);
    }
    final active = await configService.getActiveProfile();
    if (active != null) {
      _config = active;
    } else if (_profiles.isNotEmpty) {
      _config = _profiles.first;
    }

    _interfaces = await bridge.getInterfaces();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _detect() async {
    final data = await bridge.detectBackends();
    final caps = <BackendCapability>[];

    final rootAvail = data['root'] == true;
    caps.add(BackendCapability(
      type: BackendType.root,
      available: rootAvail,
      authorized: rootAvail,
      message: rootAvail ? 'su available' : 'no root',
      priority: 100,
    ));

    final shizuku = Map<String, dynamic>.from(data['shizuku'] as Map? ?? {});
    final shizukuOk = shizuku['authorized'] == true;
    caps.add(BackendCapability(
      type: BackendType.shizuku,
      available: shizuku['installed'] == true,
      authorized: shizukuOk,
      message: shizuku['message'] as String? ?? '',
      priority: 80,
    ));

    final adbOk = data['adb'] == true;
    caps.add(BackendCapability(
      type: BackendType.adb,
      available: adbOk,
      authorized: adbOk,
      message: adbOk ? 'adb shell reachable' : 'adb not available in-app',
      priority: 40,
    ));

    caps.add(const BackendCapability(
      type: BackendType.vpn,
      available: true,
      authorized: true,
      message: 'VpnService always available',
      priority: 20,
    ));

    final recommended = caps
        .where((c) => c.available && c.authorized)
        .fold<BackendCapability?>(
            null,
            (prev, c) =>
                prev == null || c.priority > prev.priority ? c : prev);

    _recommendedReason = recommended != null
        ? '推荐 ${recommended.type.label}: ${recommended.message}'
        : '使用 VPNService';

    _status = BackendStatus(
      active: recommended?.type ?? BackendType.vpn,
      running: false,
      capabilities: caps,
      recommendedReason: _recommendedReason,
    );
    notifyListeners();
  }

  void updateConfig(NetworkConfig config) {
    _config = config;
    notifyListeners();
    if (_running) {
      bridge.updateConfig(config);
    }
  }

  Future<bool> start() async {
    if (_running) return true;
    final ok = await bridge.startSimulation(_config);
    if (ok) {
      _running = true;
      _status = BackendStatus(
        active: _status.active,
        running: true,
        capabilities: _status.capabilities,
        recommendedReason: _status.recommendedReason,
      );
      _addLog('Simulation started with backend: ${_config.backend}');
      notifyListeners();
    } else {
      _addLog('Failed to start simulation');
    }
    return ok;
  }

  Future<bool> stop() async {
    if (!_running) return true;
    final ok = await bridge.stopSimulation();
    _running = false;
    _status = BackendStatus(
      active: _status.active,
      running: false,
      capabilities: _status.capabilities,
      recommendedReason: _status.recommendedReason,
    );
    _addLog('Simulation stopped');
    notifyListeners();
    return ok;
  }

  Future<void> refreshBackends() async {
    await _detect();
    _interfaces = await bridge.getInterfaces();
    notifyListeners();
  }

  Future<void> setBackend(BackendType type) async {
    _config = _config.copyWith(backend: type.id);
    notifyListeners();
  }

  Future<void> saveCurrentProfile() async {
    await configService.saveProfile(_config);
    _profiles = await configService.loadProfiles();
    await configService.setActiveProfile(_config.name);
    notifyListeners();
  }

  Future<void> loadProfile(NetworkConfig profile) async {
    _config = profile;
    await configService.setActiveProfile(profile.name);
    if (_running) {
      await bridge.updateConfig(profile);
    }
    notifyListeners();
  }

  Future<void> deleteProfile(String name) async {
    await configService.deleteProfile(name);
    _profiles = await configService.loadProfiles();
    notifyListeners();
  }

  void _addLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logs.insert(0, '[$ts] $msg');
    if (_logs.length > 200) _logs.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    bridge.dispose();
    super.dispose();
  }
}

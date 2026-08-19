import 'package:shared_preferences/shared_preferences.dart';
import '../models/network_config.dart';
import '../models/backend_status.dart';

class ConfigService {
  static const _keyProfiles = 'netemu_profiles';
  static const _keyActive = 'netemu_active_profile';

  static const _keyLockedBackend = 'netemu_locked_backend';

  Future<void> setLockedBackend(BackendType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLockedBackend, type.name);
  }

  Future<BackendType?> getLockedBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLockedBackend);
    if (s == null || s.isEmpty) return null;
    try {
      return BackendType.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return null;
    }
  }


  Future<List<NetworkConfig>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyProfiles) ?? [];
    return raw.map((s) {
      try {
        return NetworkConfig.fromJsonString(s);
      } catch (_) {
        return const NetworkConfig();
      }
    }).toList();
  }

  Future<void> saveProfiles(List<NetworkConfig> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyProfiles,
      profiles.map((p) => p.toJsonString()).toList(),
    );
  }

  Future<void> saveProfile(NetworkConfig profile) async {
    final list = await loadProfiles();
    final idx = list.indexWhere((p) => p.name == profile.name);
    if (idx >= 0) {
      list[idx] = profile;
    } else {
      list.add(profile);
    }
    await saveProfiles(list);
  }

  Future<void> deleteProfile(String name) async {
    final list = await loadProfiles();
    list.removeWhere((p) => p.name == name);
    await saveProfiles(list);
  }

  Future<NetworkConfig?> getActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyActive);
    if (name == null || name.isEmpty) return null;
    final list = await loadProfiles();
    try {
      return list.firstWhere((p) => p.name == name);
    } catch (_) {
      return null;
    }
  }

  Future<void> setActiveProfile(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActive, name);
  }

  static List<NetworkConfig> get presets => [
        const NetworkConfig(
          name: '正常网络',
          backend: 'vpn',
          upload: DirectionConfig(delayMs: 20),
          download: DirectionConfig(delayMs: 20),
        ),
        const NetworkConfig(
          name: '2G',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 400,
            jitterMs: 100,
            lossPercent: 5.0,
            bandwidthKbps: 64,
          ),
          download: DirectionConfig(
            delayMs: 350,
            jitterMs: 80,
            lossPercent: 5.0,
            bandwidthKbps: 128,
          ),
        ),
        const NetworkConfig(
          name: '3G',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 150,
            jitterMs: 50,
            lossPercent: 3.0,
            bandwidthKbps: 384,
            continuousMode: ContinuousMode.packet,
            continuousPass: 8,
            continuousDrop: 2,
          ),
          download: DirectionConfig(
            delayMs: 120,
            jitterMs: 40,
            lossPercent: 3.0,
            bandwidthKbps: 1536,
            continuousMode: ContinuousMode.packet,
            continuousPass: 8,
            continuousDrop: 2,
          ),
        ),
        const NetworkConfig(
          name: '4G弱网',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 80,
            jitterMs: 30,
            lossPercent: 2.0,
            bandwidthKbps: 2048,
          ),
          download: DirectionConfig(
            delayMs: 60,
            jitterMs: 25,
            lossPercent: 2.0,
            bandwidthKbps: 8192,
          ),
        ),
        const NetworkConfig(
          name: '4G',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 50,
            jitterMs: 10,
            lossPercent: 1.0,
            bandwidthKbps: 5120,
          ),
          download: DirectionConfig(
            delayMs: 40,
            jitterMs: 10,
            lossPercent: 1.0,
            bandwidthKbps: 20480,
          ),
        ),
        const NetworkConfig(
          name: '5G高延迟',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 120,
            jitterMs: 40,
            lossPercent: 0.5,
            bandwidthKbps: 50000,
          ),
          download: DirectionConfig(
            delayMs: 100,
            jitterMs: 35,
            lossPercent: 0.5,
            bandwidthKbps: 100000,
          ),
        ),
        const NetworkConfig(
          name: '地铁',
          backend: 'vpn',
          upload: DirectionConfig(
            delayMs: 200,
            jitterMs: 80,
            lossPercent: 8.0,
            bandwidthKbps: 1024,
            continuousMode: ContinuousMode.time,
            continuousPass: 4000,
            continuousDrop: 1500,
          ),
          download: DirectionConfig(
            delayMs: 180,
            jitterMs: 70,
            lossPercent: 8.0,
            bandwidthKbps: 3072,
            continuousMode: ContinuousMode.time,
            continuousPass: 4000,
            continuousDrop: 1500,
          ),
        ),
        const NetworkConfig(
          name: '电梯',
          backend: 'vpn',
          upload: DirectionConfig(
            continuousMode: ContinuousMode.time,
            continuousPass: 2000,
            continuousDrop: 3000,
            lossPercent: 20.0,
          ),
          download: DirectionConfig(
            continuousMode: ContinuousMode.time,
            continuousPass: 2000,
            continuousDrop: 3000,
            lossPercent: 20.0,
          ),
        ),
        const NetworkConfig(
          name: '丢包严重网络',
          backend: 'vpn',
          upload: DirectionConfig(lossPercent: 25.0, delayMs: 100, jitterMs: 50),
          download: DirectionConfig(lossPercent: 25.0, delayMs: 100, jitterMs: 50),
        ),
        const NetworkConfig(
          name: '高延迟',
          backend: 'vpn',
          upload: DirectionConfig(delayMs: 300, jitterMs: 50),
          download: DirectionConfig(delayMs: 300, jitterMs: 50),
        ),
        const NetworkConfig(
          name: '间歇断网(时间)',
          backend: 'vpn',
          upload: DirectionConfig(
            continuousMode: ContinuousMode.time,
            continuousPass: 3000,
            continuousDrop: 1000,
          ),
          download: DirectionConfig(
            continuousMode: ContinuousMode.time,
            continuousPass: 3000,
            continuousDrop: 1000,
          ),
        ),
        const NetworkConfig(
          name: '限速512K',
          backend: 'vpn',
          upload: DirectionConfig(bandwidthKbps: 512),
          download: DirectionConfig(bandwidthKbps: 512),
        ),
        const NetworkConfig(
          name: '仅UDP弱网',
          backend: 'vpn',
          protocol: ProtocolFilter.udp,
          upload: DirectionConfig(delayMs: 80, lossPercent: 5.0),
          download: DirectionConfig(delayMs: 60, lossPercent: 3.0),
        ),
      ];
}


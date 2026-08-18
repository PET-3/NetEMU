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
          name: '高延迟',
          backend: 'vpn',
          upload: DirectionConfig(delayMs: 300, jitterMs: 50),
          download: DirectionConfig(delayMs: 300, jitterMs: 50),
        ),
        const NetworkConfig(
          name: '高丢包',
          backend: 'vpn',
          upload: DirectionConfig(lossPercent: 15.0),
          download: DirectionConfig(lossPercent: 15.0),
        ),
        const NetworkConfig(
          name: '间歇断网(时间)',
          backend: 'vpn',
          upload: DirectionConfig(
            continuousMode: ContinuousMode.time,
            continuousPass: 3000, // 3s pass
            continuousDrop: 1000, // 1s drop
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

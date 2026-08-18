import 'package:shared_preferences/shared_preferences.dart';
import '../models/network_config.dart';

class ConfigService {
  static const _keyProfiles = 'netemu_profiles';
  static const _keyActive = 'netemu_active_profile';

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
    if (name == null) return null;
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
          backend: 'auto',
          upload: DirectionConfig(delayMs: 20),
          download: DirectionConfig(delayMs: 20),
        ),
        const NetworkConfig(
          name: '4G',
          backend: 'auto',
          upload: DirectionConfig(delayMs: 50, jitterMs: 10, lossPercent: 1.0, bandwidthKbps: 5120),
          download: DirectionConfig(delayMs: 40, jitterMs: 10, lossPercent: 1.0, bandwidthKbps: 20480),
        ),
        const NetworkConfig(
          name: '3G',
          backend: 'auto',
          upload: DirectionConfig(delayMs: 150, jitterMs: 50, lossPercent: 3.0, bandwidthKbps: 384),
          download: DirectionConfig(delayMs: 120, jitterMs: 40, lossPercent: 3.0, bandwidthKbps: 1536),
        ),
        const NetworkConfig(
          name: '高延迟',
          backend: 'auto',
          upload: DirectionConfig(delayMs: 500, jitterMs: 100, lossPercent: 5.0),
          download: DirectionConfig(delayMs: 500, jitterMs: 100, lossPercent: 5.0),
        ),
        const NetworkConfig(
          name: '极差网络',
          backend: 'auto',
          upload: DirectionConfig(
            delayMs: 1000,
            jitterMs: 300,
            lossPercent: 10.0,
            bandwidthKbps: 128,
            continuousPass: 5,
            continuousDrop: 2,
          ),
          download: DirectionConfig(
            delayMs: 1000,
            jitterMs: 300,
            lossPercent: 10.0,
            bandwidthKbps: 256,
            continuousPass: 5,
            continuousDrop: 2,
          ),
        ),
      ];
}

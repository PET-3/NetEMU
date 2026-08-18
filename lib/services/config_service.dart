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

  /// Built-in example profiles.
  static List<NetworkConfig> get presets => [
        const NetworkConfig(
          name: '4G弱网',
          backend: 'auto',
          upload: DirectionConfig(
            delayMs: 80,
            jitterMs: 30,
            bandwidthKbps: 512,
            lossPercent: 2.0,
          ),
          download: DirectionConfig(
            delayMs: 60,
            jitterMs: 20,
            bandwidthKbps: 2048,
            lossPercent: 1.5,
          ),
        ),
        const NetworkConfig(
          name: '3G弱网',
          backend: 'auto',
          upload: DirectionConfig(
            delayMs: 200,
            jitterMs: 80,
            bandwidthKbps: 128,
            lossPercent: 5.0,
            continuousPass: 5,
            continuousDrop: 2,
          ),
          download: DirectionConfig(
            delayMs: 150,
            jitterMs: 50,
            bandwidthKbps: 384,
            lossPercent: 3.0,
            continuousPass: 5,
            continuousDrop: 2,
          ),
        ),
        const NetworkConfig(
          name: '高延迟',
          backend: 'auto',
          upload: DirectionConfig(delayMs: 300, jitterMs: 50),
          download: DirectionConfig(delayMs: 300, jitterMs: 50),
        ),
        const NetworkConfig(
          name: '高丢包',
          backend: 'auto',
          upload: DirectionConfig(lossPercent: 15.0),
          download: DirectionConfig(lossPercent: 15.0),
        ),
        const NetworkConfig(
          name: '限速512K',
          backend: 'auto',
          upload: DirectionConfig(bandwidthKbps: 512),
          download: DirectionConfig(bandwidthKbps: 512),
        ),
      ];
}

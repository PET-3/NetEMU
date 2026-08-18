import 'dart:async';
import 'dart:convert';
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
  final List<String> _logs = [];
  bool _initialized = false;
  bool _running = false;
  String _recommendedReason = '';

  /// 非 null 表示已选中某个配置：主页只读展示，按该配置运行
  String? _selectedProfileName;

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

  /// 是否处于「已选配置」只读模式
  bool get isProfileSelected =>
      _selectedProfileName != null && _selectedProfileName!.isNotEmpty;

  String? get selectedProfileName => _selectedProfileName;

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
      _selectedProfileName = active.name;
    } else {
      _config = const NetworkConfig(name: '自由调节');
      _selectedProfileName = null;
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
      message: rootAvail ? 'su 可用，可直接下发 tc' : '无 Root',
      priority: 100,
    ));

    final shizuku = Map<String, dynamic>.from(data['shizuku'] as Map? ?? {});
    final installed = shizuku['installed'] == true;
    final shizukuOk = shizuku['authorized'] == true;
    caps.add(BackendCapability(
      type: BackendType.shizuku,
      available: installed,
      authorized: shizukuOk,
      message: installed
          ? (shizukuOk
              ? '已授权'
              : '已安装但未完成 API 授权。当前版本未集成 Shizuku 官方库，应用不会出现在 Shizuku 授权列表中；请优先使用 Root 或 VPN，或导出 ADB 命令。')
          : '未安装 Shizuku',
      priority: 80,
    ));

    // ADB：应用内无法直接执行，始终提供「导出命令」
    caps.add(const BackendCapability(
      type: BackendType.adb,
      available: true,
      authorized: true,
      message: '应用内不直接执行 adb。请在「后端」页导出命令，到电脑上执行。',
      priority: 40,
    ));

    caps.add(const BackendCapability(
      type: BackendType.vpn,
      available: true,
      authorized: true,
      message: '无 Root 可用，用户态模拟（推荐）',
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
    // 已选配置模式下主页不可改；配置页编辑会先 clear 或走 saveProfile
    if (isProfileSelected) {
      _addLog('当前为配置只读模式，请到「配置」页修改或点击「自由调节」');
      return;
    }
    _config = config;
    notifyListeners();
    if (_running) {
      bridge.updateConfig(config);
    }
  }

  /// 配置页强制更新（编辑/新建时）
  void forceUpdateConfig(NetworkConfig config) {
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
    _selectedProfileName = _config.name;
    notifyListeners();
  }

  /// 选中配置：主页只读 + 按该配置运行
  Future<void> loadProfile(NetworkConfig profile) async {
    _config = profile;
    _selectedProfileName = profile.name;
    await configService.setActiveProfile(profile.name);
    if (_running) {
      await bridge.updateConfig(profile);
    }
    notifyListeners();
  }

  /// 取消选中 → 主页可自由调节参数
  Future<void> clearProfileSelection() async {
    _selectedProfileName = null;
    await configService.setActiveProfile('');
    notifyListeners();
  }

  Future<void> deleteProfile(String name) async {
    await configService.deleteProfile(name);
    _profiles = await configService.loadProfiles();
    if (_selectedProfileName == name) {
      _selectedProfileName = null;
    }
    notifyListeners();
  }

  /// 导出全部配置为 JSON 字符串（备份）
  Future<String> exportBackupJson() async {
    final list = await configService.loadProfiles();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': list.map((e) => e.toJson()).toList(),
    });
  }

  /// 从 JSON 恢复配置（覆盖或合并）
  Future<int> importBackupJson(String raw, {bool merge = true}) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw FormatException('无效备份格式');
    final list = decoded['profiles'];
    if (list is! List) throw FormatException('缺少 profiles');
    final imported = <NetworkConfig>[];
    for (final item in list) {
      if (item is Map) {
        imported.add(
            NetworkConfig.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    if (imported.isEmpty) throw FormatException('备份中没有配置');
    if (merge) {
      final existing = await configService.loadProfiles();
      final byName = {for (final p in existing) p.name: p};
      for (final p in imported) {
        byName[p.name] = p;
      }
      await configService.saveProfiles(byName.values.toList());
    } else {
      await configService.saveProfiles(imported);
    }
    _profiles = await configService.loadProfiles();
    notifyListeners();
    return imported.length;
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

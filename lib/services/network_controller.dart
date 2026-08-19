import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/backend_status.dart';
import '../models/network_config.dart';
import 'native_bridge.dart';
import 'config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 运行来源：已选配置 / 测试页
enum RunSource { none, profile, test }

class NetworkController extends ChangeNotifier {
  final NativeBridge bridge = NativeBridge();
  final ConfigService configService = ConfigService();

  NetworkConfig _config = const NetworkConfig();
  /// 测试页独立参数（不自动写入配置）
  NetworkConfig _testConfig = const NetworkConfig(name: '测试');
  BackendStatus _status = const BackendStatus();
  SimulationStatistics _stats = const SimulationStatistics();
  List<NetworkInterfaceInfo> _interfaces = [];
  List<NetworkConfig> _profiles = [];
  final List<String> _logs = [];
  bool _initialized = false;
  bool _running = false;
  String _recommendedReason = '';

  String? _selectedProfileName;
  RunSource _runSource = RunSource.none;
  bool _showControlFloat = false;
  bool _showInfoFloat = false;
  bool _showNotification = true;
  bool _hideFromRecents = false;
  bool _showCharts = false;
  bool _realNetworkAdaptive = false;
  /// Highlight this profile name briefly on profiles list after save.
  String? _flashProfileName;
  final List<double> _latencyHistory = [];
  final List<double> _lossHistory = [];
  static const _maxHistory = 60;
  static const _maxLogs = 500;

  /// 全局锁定后端（不再 auto 切换）
  BackendType _lockedBackend = BackendType.vpn;

  NetworkConfig get config =>
      _runSource == RunSource.test ? _testConfig : _config;
  NetworkConfig get testConfig => _testConfig;
  NetworkConfig get profileConfig => _config;
  BackendStatus get status => _status;
  SimulationStatistics get stats => _stats;
  List<NetworkInterfaceInfo> get interfaces => _interfaces;
  List<NetworkConfig> get profiles => _profiles;
  List<String> get logs => List.unmodifiable(_logs);
  bool get initialized => _initialized;
  bool get running => _running;
  String get recommendedReason => _recommendedReason;
  BackendType get activeBackend => _lockedBackend;
  BackendType get lockedBackend => _lockedBackend;
  String? get selectedProfileName => _selectedProfileName;
  RunSource get runSource => _runSource;
  bool get isProfileSelected =>
      _runSource == RunSource.profile && _selectedProfileName != null;
  bool get isTestMode => _runSource == RunSource.test;
  bool get showControlFloat => _showControlFloat;
  bool get showInfoFloat => _showInfoFloat;
  bool get showNotification => _showNotification;
  bool get hideFromRecents => _hideFromRecents;
  bool get showCharts => _showCharts;
  bool get realNetworkAdaptive => _realNetworkAdaptive;
  String? get flashProfileName => _flashProfileName;
  List<double> get latencyHistory => List.unmodifiable(_latencyHistory);
  List<double> get lossHistory => List.unmodifiable(_lossHistory);

  Future<void> initialize() async {
    if (_initialized) return;
    bridge.startListening();
    bridge.statisticsStream.listen((s) {
      _stats = s;
      if (_running) {
        final delaySample = (config.upload.delayMs + config.download.delayMs) /
            2.0;
        _latencyHistory.add(delaySample);
        if (_latencyHistory.length > _maxHistory) {
          _latencyHistory.removeAt(0);
        }
        final loss = (s.randomLossCount + s.continuousLossCount).toDouble();
        _lossHistory.add(loss);
        if (_lossHistory.length > _maxHistory) {
          _lossHistory.removeAt(0);
        }
      }
      notifyListeners();
    });
    bridge.logStream.listen(_addLog);

    await _detect();
    _profiles = await configService.loadProfiles();
    if (_profiles.isEmpty) {
      _profiles = List.from(ConfigService.presets);
      await configService.saveProfiles(_profiles);
    }
    final savedBackend = await configService.getLockedBackend();
    if (savedBackend != null) {
      _lockedBackend = savedBackend;
    }
    final active = await configService.getActiveProfile();
    if (active != null) {
      _config = active.copyWith(backend: _lockedBackend.id);
      _selectedProfileName = active.name;
      _runSource = RunSource.profile;
    }
    _interfaces = await bridge.getInterfaces();
    _initialized = true;
    notifyListeners();
    _syncFloatPrefs();
  }

  Future<void> _detect() async {
    final data = await bridge.detectBackends();
    final caps = <BackendCapability>[];

    final rootAvail = data['root'] == true;
    caps.add(BackendCapability(
      type: BackendType.root,
      available: rootAvail,
      authorized: rootAvail,
      message: rootAvail ? 'su 可用' : '无 Root',
      priority: 100,
    ));

    final shizuku = Map<String, dynamic>.from(data['shizuku'] as Map? ?? {});
    final shizukuReady = shizuku['authorized'] == true;
    caps.add(BackendCapability(
      type: BackendType.shizuku,
      available: shizuku['installed'] == true,
      authorized: shizukuReady,
      message: (shizuku['message'] as String?) ??
          (shizukuReady
              ? 'Shizuku 已授权'
              : (shizuku['running'] == true
                  ? '已运行，待授权'
                  : '请安装并启动 Shizuku')),
      priority: 80,
    ));

    caps.add(const BackendCapability(
      type: BackendType.adb,
      available: true,
      authorized: true,
      message: '仅导出命令到 PC 执行（应用无法直接 adb）',
      priority: 40,
    ));

    caps.add(const BackendCapability(
      type: BackendType.vpn,
      available: true,
      authorized: true,
      message: '无 Root',
      priority: 20,
    ));

    _recommendedReason = '';
    _status = BackendStatus(
      active: _lockedBackend,
      running: _running,
      capabilities: caps,
      recommendedReason: '',
    );
    notifyListeners();
  }

  Future<void> setLockedBackend(BackendType type) async {
    if (type == BackendType.auto) type = BackendType.vpn;
    _lockedBackend = type;
    await configService.setLockedBackend(type);
    _config = _config.copyWith(backend: type.id);
    _testConfig = _testConfig.copyWith(backend: type.id);
    _status = BackendStatus(
      active: type,
      running: _running,
      capabilities: _status.capabilities,
      recommendedReason: '',
    );
    notifyListeners();
    if (_running) {
      await bridge.updateConfig(config.copyWith(backend: type.id));
    }
  }

  void selectTestMode() {
    _runSource = RunSource.test;
    _selectedProfileName = null;
    _testConfig = _testConfig.copyWith(name: '临时', backend: _lockedBackend.id);
    notifyListeners();
    _syncFloatPrefs();
  }

  Future<void> selectProfile(NetworkConfig profile) async {
    _config = profile.copyWith(backend: _lockedBackend.id);
    _selectedProfileName = profile.name;
    _runSource = RunSource.profile;
    await configService.setActiveProfile(profile.name);
    notifyListeners();
    if (_running) {
      await bridge.updateConfig(_config);
    }
  }

  void updateTestConfig(NetworkConfig c) {
    _testConfig = c.copyWith(
      name: _runSource == RunSource.profile
          ? (_selectedProfileName ?? c.name)
          : '临时',
      backend: _lockedBackend.id,
    );
    // When adjusting a selected profile, also mirror into working config.
    if (_runSource == RunSource.profile) {
      _config = _testConfig;
    }
    notifyListeners();
    if (_running) {
      bridge.updateConfig(_runSource == RunSource.test ? _testConfig : _config);
    }
  }

  /// Load selected profile params into the adjust page editor state.
  void prepareAdjustEditor() {
    if (_runSource == RunSource.profile) {
      _testConfig = _config;
    }
  }

  void setFlashProfile(String? name) {
    _flashProfileName = name;
    notifyListeners();
  }

  void clearFlashProfile() {
    if (_flashProfileName != null) {
      _flashProfileName = null;
      notifyListeners();
    }
  }

  /// 修改已有配置（按名称覆盖，不新增）
  Future<void> updateExistingProfile(NetworkConfig profile) async {
    final list = await configService.loadProfiles();
    final idx = list.indexWhere((p) => p.name == profile.name);
    if (idx < 0) {
      _addLog('配置不存在，未修改: ${profile.name}');
      return;
    }
    list[idx] = profile.copyWith(backend: _lockedBackend.id);
    await configService.saveProfiles(list);
    _profiles = list;
    if (_selectedProfileName == profile.name) {
      _config = list[idx];
      if (_running) await bridge.updateConfig(_config);
    }
    notifyListeners();
  }

  Future<void> saveTestAsProfile(String name) async {
    final p = _testConfig.copyWith(name: name, backend: _lockedBackend.id);
    await configService.saveProfile(p);
    _profiles = await configService.loadProfiles();
    await selectProfile(p);
  }

  Future<void> deleteProfile(String name) async {
    await configService.deleteProfile(name);
    _profiles = await configService.loadProfiles();
    if (_selectedProfileName == name) {
      _selectedProfileName = null;
      _runSource = RunSource.none;
    }
    notifyListeners();
  }

  Future<void> createProfile(NetworkConfig profile) async {
    await configService.saveProfile(
        profile.copyWith(backend: _lockedBackend.id));
    _profiles = await configService.loadProfiles();
    notifyListeners();
  }

  void setShowControlFloat(bool v) {
    _showControlFloat = v;
    notifyListeners();
    bridge.showControlFloat(v);
  }

  void setShowInfoFloat(bool v) {
    _showInfoFloat = v;
    notifyListeners();
    bridge.showInfoFloat(v);
  }

  void setShowNotification(bool v) {
    _showNotification = v;
    notifyListeners();
    bridge.setNotificationEnabled(v);
  }

  void setHideFromRecents(bool v) {
    _hideFromRecents = v;
    notifyListeners();
    bridge.setHideFromRecents(v);
  }

  void setShowCharts(bool v) {
    _showCharts = v;
    notifyListeners();
  }

  void setRealNetworkAdaptive(bool v) {
    _realNetworkAdaptive = v;
    _addLog(v
        ? '已开启「真实网络自适应」提示（参数仍手动/配置驱动，不自动改弱网强度）'
        : '已关闭真实网络自适应提示');
    notifyListeners();
  }

  Future<bool> start() async {
    if (_running) return true;
    if (_runSource == RunSource.none) {
      _addLog('请先选择「临时」或一个配置');
      return false;
    }
    final cfg = config.copyWith(backend: _lockedBackend.id);
    final ok = await bridge.startSimulation(cfg);
    if (ok) {
      _running = true;
      _status = BackendStatus(
        active: _lockedBackend,
        running: true,
        capabilities: _status.capabilities,
        recommendedReason: '',
      );
      _addLog('已启动 · ${_runSource == RunSource.test ? "临时" : _selectedProfileName} · ${_lockedBackend.label}');
      if (_showControlFloat) bridge.showControlFloat(true);
      if (_showInfoFloat) bridge.showInfoFloat(true);
    } else {
      _addLog('启动失败');
    }
    notifyListeners();
    return ok;
  }

  Future<bool> stop() async {
    if (!_running) return true;
    await bridge.stopSimulation();
    _running = false;
    _status = BackendStatus(
      active: _lockedBackend,
      running: false,
      capabilities: _status.capabilities,
      recommendedReason: '',
    );
    _addLog('已停止');
    notifyListeners();
    return true;
  }

  Future<void> toggleRun() async {
    if (_running) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> refreshBackends() async {
    await _detect();
    _interfaces = await bridge.getInterfaces();
    notifyListeners();
  }


  /// 兼容旧 UI：等同 setLockedBackend
  Future<void> setBackend(BackendType type) => setLockedBackend(type);

  /// 兼容旧 UI：按当前运行源更新参数
  void updateConfig(NetworkConfig config) {
    if (_runSource == RunSource.test) {
      updateTestConfig(config);
    } else if (_runSource == RunSource.profile) {
      // 只读配置模式：忽略主页乱改；旧控件若调用则尝试热更新展示用副本
      _config = config.copyWith(backend: _lockedBackend.id);
      notifyListeners();
      if (_running) bridge.updateConfig(_config);
    } else {
      _testConfig = config.copyWith(backend: _lockedBackend.id);
      notifyListeners();
    }
  }


  Future<void> _syncFloatPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final source = _runSource == RunSource.test
          ? 'test'
          : (_runSource == RunSource.profile ? 'profile' : '');
      await prefs.setString('netemu_float_run_source', source);
      await prefs.setString('netemu_float_profile', _selectedProfileName ?? '');
      final names = _profiles.map((e) => e.name).toList();
      await prefs.setString('netemu_profile_names', names.join(','));
    } catch (_) {}
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Export all profiles as one JSON document.
  Future<String> exportBackupJson() async {
    final list = await configService.loadProfiles();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': list.map((e) => e.toJson()).toList(),
    });
  }

  /// Export each profile as a separate JSON string (for multi-file / zip).
  Future<Map<String, String>> exportProfilesAsFiles() async {
    final list = await configService.loadProfiles();
    final map = <String, String>{};
    for (final p in list) {
      final safe = p.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-]+'), '_');
      map['$safe.json'] = const JsonEncoder.withIndent('  ').convert(p.toJson());
    }
    map['_index.json'] = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': list.length,
      'names': list.map((e) => e.name).toList(),
    });
    return map;
  }

  Future<int> importBackupJson(String raw, {bool merge = true}) async {
    final decoded = jsonDecode(raw);
    final imported = <NetworkConfig>[];
    if (decoded is Map) {
      if (decoded['profiles'] is List) {
        for (final item in decoded['profiles'] as List) {
          if (item is Map) {
            imported.add(
                NetworkConfig.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } else if (decoded.containsKey('name') && decoded.containsKey('upload')) {
        // single profile json
        imported.add(NetworkConfig.fromJson(Map<String, dynamic>.from(decoded)));
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          imported
              .add(NetworkConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (imported.isEmpty) throw FormatException('无效备份：未找到配置');
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
    _addLog('导入 ${imported.length} 个配置 (merge=$merge)');
    return imported.length;
  }

  void _addLog(String msg, {String level = 'INFO'}) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logs.insert(0, '[$ts][$level] $msg');
    while (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  String exportLogsText() => _logs.reversed.join('\n');

  @override
  void dispose() {
    bridge.dispose();
    super.dispose();
  }
}

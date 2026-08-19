import 'dart:async';
import 'package:flutter/services.dart';
import '../models/backend_status.dart';
import '../models/network_config.dart';

/// Flutter <-> Android MethodChannel / EventChannel bridge.
class NativeBridge {
  static const MethodChannel _method =
      MethodChannel('com.netemu.netemu/method');
  static const EventChannel _event =
      EventChannel('com.netemu.netemu/events');

  StreamSubscription? _eventSub;
  final _statsController =
      StreamController<SimulationStatistics>.broadcast();
  final _logController = StreamController<String>.broadcast();

  Stream<SimulationStatistics> get statisticsStream =>
      _statsController.stream;
  Stream<String> get logStream => _logController.stream;

  void startListening() {
    _eventSub?.cancel();
    _eventSub = _event.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final type = event['type'] as String?;
        if (type == 'stats') {
          _statsController.add(
              SimulationStatistics.fromJson(Map<String, dynamic>.from(event)));
        } else if (type == 'log') {
          _logController.add(event['message'] as String? ?? '');
        }
      }
    }, onError: (e) {
      _logController.add('EventChannel error: $e');
    });
  }

  void dispose() {
    _eventSub?.cancel();
    _statsController.close();
    _logController.close();
  }

  Future<Map<String, dynamic>> detectBackends() async {
    try {
      final result = await _method.invokeMethod<Map>('detectBackends');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      return {'error': e.message};
    }
  }

  Future<bool> startSimulation(NetworkConfig config) async {
    try {
      final result = await _method.invokeMethod<bool>(
        'startSimulation',
        config.toJson(),
      );
      return result ?? false;
    } on PlatformException catch (e) {
      _logController.add('startSimulation failed: ${e.message}');
      return false;
    }
  }

  Future<bool> stopSimulation() async {
    try {
      final result = await _method.invokeMethod<bool>('stopSimulation');
      return result ?? false;
    } on PlatformException catch (e) {
      _logController.add('stopSimulation failed: ${e.message}');
      return false;
    }
  }

  Future<String> getActiveBackend() async {
    try {
      final result = await _method.invokeMethod<String>('getBackend');
      return result ?? 'vpn';
    } on PlatformException {
      return 'vpn';
    }
  }

  Future<List<NetworkInterfaceInfo>> getInterfaces() async {
    try {
      final result = await _method.invokeMethod<List>('getInterfaces');
      if (result == null) return [];
      return result
          .map((e) => NetworkInterfaceInfo.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PlatformException {
      return [];
    }
  }

  Future<bool> updateConfig(NetworkConfig config) async {
    try {
      final result = await _method.invokeMethod<bool>(
        'updateConfig',
        config.toJson(),
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<SimulationStatistics> getStatistics() async {
    try {
      final result = await _method.invokeMethod<Map>('getStatistics');
      if (result == null) return const SimulationStatistics();
      return SimulationStatistics.fromJson(Map<String, dynamic>.from(result));
    } on PlatformException {
      return const SimulationStatistics();
    }
  }

  Future<Map<String, dynamic>> executeCommand(String command) async {
    try {
      final result = await _method.invokeMethod<Map>(
        'executeCommand',
        {'command': command},
      );
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      return {
        'exitCode': -1,
        'stdout': '',
        'stderr': e.message ?? 'Platform error',
      };
    }
  }

  Future<bool> requestVpnPermission() async {
    try {
      final result = await _method.invokeMethod<bool>('requestVpnPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, dynamic>> getShizukuStatus() async {
    try {
      final result = await _method.invokeMethod<Map>('getShizukuStatus');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException {
      return {'installed': false, 'running': false, 'authorized': false};
    }
  }

  Future<bool> requestShizukuPermission() async {
    try {
      final result =
          await _method.invokeMethod<bool>('requestShizukuPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isRootAvailable() async {
    try {
      final result = await _method.invokeMethod<bool>('isRootAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<String>> exportAdbCommands() async {
    try {
      final result = await _method.invokeMethod<List>('exportAdbCommands');
      return (result ?? []).cast<String>();
    } on PlatformException {
      return [];
    }
  }

  Future<bool> requestOverlayPermission() async {
    try {
      final result =
          await _method.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> showControlFloat(bool show) async {
    try {
      final result = await _method.invokeMethod<bool>(
        'showControlFloat',
        {'show': show},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> showInfoFloat(bool show) async {
    try {
      final result = await _method.invokeMethod<bool>(
        'showInfoFloat',
        {'show': show},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setNotificationEnabled(bool enabled) async {
    try {
      await _method.invokeMethod('setNotificationEnabled', {'enabled': enabled});
    } on PlatformException {
      // ignore
    }
  }

  Future<void> setHideFromRecents(bool hide) async {
    try {
      await _method.invokeMethod('setHideFromRecents', {'hide': hide});
    } on PlatformException {
      // ignore
    }
  }

}

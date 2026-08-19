import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/network_config.dart';

/// Import / export helpers for profiles (JSON / multi-file / ZIP).
class ProfileIo {
  /// Parse one or many profiles from raw text (backup blob or single profile).
  static List<NetworkConfig> parseJsonText(String raw) {
    final decoded = jsonDecode(raw);
    final out = <NetworkConfig>[];
    if (decoded is Map) {
      if (decoded['profiles'] is List) {
        for (final item in decoded['profiles'] as List) {
          if (item is Map) {
            out.add(NetworkConfig.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } else if (decoded.containsKey('name')) {
        out.add(NetworkConfig.fromJson(Map<String, dynamic>.from(decoded)));
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          out.add(NetworkConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return out;
  }

  static String encodeAll(List<NetworkConfig> list) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': list.map((e) => e.toJson()).toList(),
    });
  }

  static String encodeOne(NetworkConfig p) {
    return const JsonEncoder.withIndent('  ').convert(p.toJson());
  }

  static Future<File> writeZip(List<NetworkConfig> list) async {
    final archive = Archive();
    for (final p in list) {
      final safe = p.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-]+'), '_');
      final bytes = utf8.encode(encodeOne(p));
      archive.addFile(ArchiveFile('$safe.json', bytes.length, bytes));
    }
    final index = utf8.encode(encodeAll(list));
    archive.addFile(ArchiveFile('_index.json', index.length, index));
    final zipBytes = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/netemu_profiles_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await file.writeAsBytes(zipBytes!, flush: true);
    return file;
  }

  static Future<File> writeJsonFile(List<NetworkConfig> list) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/netemu_profiles_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(encodeAll(list), flush: true);
    return file;
  }

  static List<NetworkConfig> parseZipBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <NetworkConfig>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.toLowerCase();
      if (!name.endsWith('.json')) continue;
      try {
        final text = utf8.decode(f.content as List<int>);
        out.addAll(parseJsonText(text));
      } catch (_) {}
    }
    // de-dupe by name (last wins)
    final map = <String, NetworkConfig>{};
    for (final p in out) {
      map[p.name] = p;
    }
    return map.values.toList();
  }
}

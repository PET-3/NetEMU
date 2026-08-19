import 'package:flutter_test/flutter_test.dart';
import 'package:netemu/models/network_config.dart';

void main() {
  group('DirectionConfig', () {
    test('defaults are zero / unlimited', () {
      const d = DirectionConfig();
      expect(d.delayMs, 0);
      expect(d.jitterMs, 0);
      expect(d.bandwidthKbps, 0);
      expect(d.lossPercent, 0.0);
      expect(d.continuousMode, ContinuousMode.packet);
      expect(d.continuousPass, 0);
      expect(d.continuousDrop, 0);
    });

    test('copyWith preserves unspecified fields', () {
      const d = DirectionConfig(delayMs: 100, lossPercent: 5.0);
      final d2 = d.copyWith(jitterMs: 20);
      expect(d2.delayMs, 100);
      expect(d2.jitterMs, 20);
      expect(d2.lossPercent, 5.0);
    });
  });

  group('NetworkConfig JSON', () {
    test('round-trip serialize', () {
      const cfg = NetworkConfig(
        name: 'test-3g',
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
        download: DirectionConfig(delayMs: 120, bandwidthKbps: 1536),
        protocol: ProtocolFilter.tcp,
      );
      final json = cfg.toJson();
      final restored = NetworkConfig.fromJson(json);
      expect(restored.name, 'test-3g');
      expect(restored.backend, 'vpn');
      expect(restored.upload.delayMs, 150);
      expect(restored.upload.continuousMode, ContinuousMode.packet);
      expect(restored.upload.continuousPass, 8);
      expect(restored.download.bandwidthKbps, 1536);
      expect(restored.protocol, ProtocolFilter.tcp);
    });

    test('fromJsonString / toJsonString', () {
      const cfg = NetworkConfig(name: 'round', upload: DirectionConfig(delayMs: 10));
      final s = cfg.toJsonString();
      final restored = NetworkConfig.fromJsonString(s);
      expect(restored.name, 'round');
      expect(restored.upload.delayMs, 10);
    });
  });

  group('ContinuousMode', () {
    test('time mode values', () {
      const d = DirectionConfig(
        continuousMode: ContinuousMode.time,
        continuousPass: 3000,
        continuousDrop: 1000,
      );
      expect(d.continuousMode, ContinuousMode.time);
      expect(d.continuousPass, 3000);
    });
  });
}

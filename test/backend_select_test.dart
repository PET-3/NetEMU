import 'package:flutter_test/flutter_test.dart';
import 'package:netemu/models/backend_status.dart';

void main() {
  group('BackendStatus.recommended', () {
    test('picks highest priority available+authorized', () {
      const status = BackendStatus(
        capabilities: [
          BackendCapability(
            type: BackendType.vpn,
            available: true,
            authorized: true,
            priority: 20,
          ),
          BackendCapability(
            type: BackendType.root,
            available: true,
            authorized: true,
            priority: 100,
          ),
          BackendCapability(
            type: BackendType.shizuku,
            available: true,
            authorized: false,
            priority: 80,
          ),
        ],
      );
      expect(status.recommended, BackendType.root);
    });

    test('falls back to vpn when others not authorized', () {
      const status = BackendStatus(
        capabilities: [
          BackendCapability(
            type: BackendType.root,
            available: false,
            authorized: false,
            priority: 100,
          ),
          BackendCapability(
            type: BackendType.shizuku,
            available: true,
            authorized: false,
            priority: 80,
          ),
          BackendCapability(
            type: BackendType.vpn,
            available: true,
            authorized: true,
            priority: 20,
          ),
        ],
      );
      expect(status.recommended, BackendType.vpn);
    });

    test('shizuku preferred over vpn when authorized', () {
      const status = BackendStatus(
        capabilities: [
          BackendCapability(
            type: BackendType.shizuku,
            available: true,
            authorized: true,
            priority: 80,
          ),
          BackendCapability(
            type: BackendType.vpn,
            available: true,
            authorized: true,
            priority: 20,
          ),
        ],
      );
      expect(status.recommended, BackendType.shizuku);
    });
  });

  group('BackendType', () {
    test('labels and ids', () {
      expect(BackendType.root.label, 'Root');
      expect(BackendType.vpn.id, 'vpn');
      expect(BackendType.shizuku.id, 'shizuku');
    });
  });
}

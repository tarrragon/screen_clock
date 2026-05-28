import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/services/auto_launch_service.dart';

void main() {
  group('InMemoryAutoLaunchService', () {
    test('respects initial value', () async {
      final InMemoryAutoLaunchService off =
          InMemoryAutoLaunchService(initial: false);
      final InMemoryAutoLaunchService on =
          InMemoryAutoLaunchService(initial: true);
      expect(await off.isEnabled(), false);
      expect(await on.isEnabled(), true);
    });

    test('setEnabled updates subsequent isEnabled', () async {
      final InMemoryAutoLaunchService service = InMemoryAutoLaunchService();
      expect(await service.isEnabled(), false);
      await service.setEnabled(true);
      expect(await service.isEnabled(), true);
      await service.setEnabled(false);
      expect(await service.isEnabled(), false);
    });

    test('setEnabled always reports success', () async {
      final InMemoryAutoLaunchService service = InMemoryAutoLaunchService();
      expect(await service.setEnabled(true), true);
      expect(await service.setEnabled(false), true);
    });
  });
}

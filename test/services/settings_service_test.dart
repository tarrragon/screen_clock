import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferencesSettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('first launch returns defaults', () async {
      final PreferencesSettingsService service =
          PreferencesSettingsService();
      final SettingsModel loaded = await service.load();
      expect(loaded, SettingsModel.defaults());
    });

    test('round-trip: save -> load returns the same model', () async {
      final PreferencesSettingsService service =
          PreferencesSettingsService();
      final SettingsModel original = SettingsModel.defaults().copyWith(
        fontSize: 80,
        targetScreenIndex: 1,
        autoLaunch: true,
      );
      await service.save(original);
      final SettingsModel loaded = await service.load();
      expect(loaded, original);
    });

    test('corrupt JSON falls back to defaults without throwing',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.${PreferencesSettingsService.storageKey}':
            '{not valid json',
      });
      final PreferencesSettingsService service =
          PreferencesSettingsService();
      final SettingsModel loaded = await service.load();
      expect(loaded, SettingsModel.defaults());
    });

    test('non-object JSON falls back to defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.${PreferencesSettingsService.storageKey}': jsonEncode(42),
      });
      final PreferencesSettingsService service =
          PreferencesSettingsService();
      final SettingsModel loaded = await service.load();
      expect(loaded, SettingsModel.defaults());
    });
  });

  group('InMemorySettingsService', () {
    test('returns seed on first load', () async {
      final SettingsModel seed =
          SettingsModel.defaults().copyWith(autoLaunch: true);
      final InMemorySettingsService service =
          InMemorySettingsService(seed: seed);
      expect(await service.load(), seed);
    });

    test('save updates subsequent load', () async {
      final InMemorySettingsService service = InMemorySettingsService();
      final SettingsModel updated = SettingsModel.defaults().copyWith(
        targetScreenIndex: 2,
      );
      await service.save(updated);
      expect(await service.load(), updated);
    });
  });
}

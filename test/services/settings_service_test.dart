import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';
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

  group('PreferencesSettingsService bindings seed migration (W3-002)', () {
    String prefKey() => 'flutter.${PreferencesSettingsService.storageKey}';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
        'legacy save (no bindings, no seed flag) seeds default bindings '
        'and preserves other fields', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        prefKey(): jsonEncode(<String, Object>{
          'schemaVersion': 2,
          'fontSize': 72.0,
          'targetScreenIndex': 1,
          'autoLaunch': true,
        }),
      });
      final PreferencesSettingsService service = PreferencesSettingsService();

      final SettingsModel loaded = await service.load();

      expect(loaded.bindings, SettingsModel.defaults().bindings);
      expect(loaded.bindingsSeeded, isTrue);
      // 其他欄位不丟失（acceptance 1）。
      expect(loaded.fontSize, 72.0);
      expect(loaded.targetScreenIndex, 1);
      expect(loaded.autoLaunch, isTrue);
    });

    test('seed migration is persisted to storage on load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        prefKey(): jsonEncode(<String, Object>{
          'schemaVersion': 2,
          'fontSize': 72.0,
        }),
      });
      final PreferencesSettingsService service = PreferencesSettingsService();

      await service.load();

      // 直接檢查底層存檔已被改寫（證明 load 內有 save，而非每次重算）。
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(PreferencesSettingsService.storageKey);
      expect(raw, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['bindingsSeeded'], true);
      expect(decoded['bindings'], isNotEmpty);
    });

    test('existing non-empty bindings without seed flag are not clobbered',
        () async {
      // 模擬 schema v3 早期存檔：已有自訂綁定，但存檔時尚無 bindingsSeeded 旗標。
      final Map<String, Object> legacyV3 = Map<String, Object>.from(
        SettingsModel.defaults().copyWith(
          bindings: <MouseBinding>[
            const MouseBinding(buttonNumber: 5, action: DragScrollAction()),
          ],
        ).toJson(),
      )..remove('bindingsSeeded');
      SharedPreferences.setMockInitialValues(<String, Object>{
        prefKey(): jsonEncode(legacyV3),
      });
      final PreferencesSettingsService service = PreferencesSettingsService();

      final SettingsModel loaded = await service.load();

      // 不可被 defaults 的 button 4 覆蓋；保留使用者既有 button 5。
      expect(loaded.bindings, hasLength(1));
      expect(loaded.bindings.single.buttonNumber, 5);
      expect(loaded.bindingsSeeded, isTrue);
    });

    test('already-seeded save with empty bindings is not re-seeded', () async {
      // 使用者升級後（已 seed）又主動清空綁定：旗標為 true → 不應重新 seed。
      final PreferencesSettingsService service = PreferencesSettingsService();
      final SettingsModel seededEmpty = SettingsModel.defaults().copyWith(
        bindings: const <MouseBinding>[],
        bindingsSeeded: true,
      );
      await service.save(seededEmpty);

      final SettingsModel loaded = await service.load();

      expect(loaded.bindings, isEmpty);
      expect(loaded.bindingsSeeded, isTrue);
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

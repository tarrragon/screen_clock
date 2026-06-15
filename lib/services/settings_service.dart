import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings_model.dart';

/// 設定讀寫介面（SPEC-004 FR-03）。
///
/// 透過介面切離儲存實作，方便測試以 [InMemorySettingsService] 取代。
abstract class SettingsService {
  Future<SettingsModel> load();
  Future<void> save(SettingsModel settings);
}

/// 預設實作：將 [SettingsModel] 以 JSON 字串寫入 [SharedPreferences]
/// 單一 key 下（SPEC-004 儲存方案決策）。
class PreferencesSettingsService implements SettingsService {
  PreferencesSettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String storageKey = 'screen_clock.settings.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _resolvePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<SettingsModel> load() async {
    try {
      final SharedPreferences prefs = await _resolvePrefs();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return SettingsModel.defaults();
      }
      final Object decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '[SettingsService] stored payload is not a JSON object; '
          'using defaults',
        );
        return SettingsModel.defaults();
      }
      final SettingsModel loaded = SettingsModel.fromJson(decoded);
      return _migrateBindingSeed(loaded);
    } catch (error, stack) {
      debugPrint(
        '[SettingsService] load failed; using defaults; error=$error',
      );
      debugPrint(stack.toString());
      return SettingsModel.defaults();
    }
  }

  /// 一次性預設綁定 seed migration（W3-002）。
  ///
  /// 舊資料缺 bindingsSeeded 旗標（false）時：僅當綁定為空才補入預設綁定，
  /// 避免覆蓋 schema v3 早期使用者的自訂綁定；無論如何標記 seeded 並持久化，
  /// 使後續清空綁定不再重新 seed。
  Future<SettingsModel> _migrateBindingSeed(SettingsModel loaded) async {
    if (loaded.bindingsSeeded) {
      return loaded;
    }
    final SettingsModel migrated = loaded.copyWith(
      bindings: loaded.bindings.isEmpty
          ? SettingsModel.defaults().bindings
          : loaded.bindings,
      bindingsSeeded: true,
    );
    await save(migrated);
    return migrated;
  }

  @override
  Future<void> save(SettingsModel settings) async {
    try {
      final SharedPreferences prefs = await _resolvePrefs();
      final String encoded = jsonEncode(settings.toJson());
      await prefs.setString(storageKey, encoded);
    } catch (error, stack) {
      debugPrint('[SettingsService] save failed; error=$error');
      debugPrint(stack.toString());
    }
  }
}

/// 測試替身：把 [SettingsModel] 放在記憶體中，避免依賴平台 channel。
class InMemorySettingsService implements SettingsService {
  InMemorySettingsService({SettingsModel? seed})
      : _current = seed ?? SettingsModel.defaults();

  SettingsModel _current;

  @override
  Future<SettingsModel> load() async => _current;

  @override
  Future<void> save(SettingsModel settings) async {
    _current = settings;
  }
}

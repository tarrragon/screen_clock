import 'package:flutter/foundation.dart';

import '../models/settings_model.dart';
import '../services/settings_service.dart';

/// 設定的可變狀態（SPEC-005 FR-04）。
///
/// 採內建 [ValueNotifier] 取代第三方狀態管理套件，維持 MVP 依賴簡潔。
/// 啟動時保留 [_initial] 快照供「取消」還原；「儲存」會寫入 [SettingsService]。
class SettingsController extends ValueNotifier<SettingsModel> {
  SettingsController({
    required SettingsModel initial,
    required SettingsService service,
  })  : _initial = initial,
        _service = service,
        super(initial);

  final SettingsModel _initial;
  final SettingsService _service;

  SettingsModel get initial => _initial;

  /// 取消編輯：還原為啟動時快照（SPEC-005 FR-04 / Settings Panel Cancel）。
  void resetToStartup() {
    value = _initial;
  }

  /// 儲存當前 value 並非同步寫入持久層。
  /// 失敗由 [SettingsService] 內部 log，不拋例外（SPEC-004 FR-03）。
  Future<void> persist() => _service.save(value);

  /// 修改單一欄位的便利方法（避免外部寫死大量 copyWith 呼叫）。
  void update(SettingsModel Function(SettingsModel current) mutate) {
    final SettingsModel next = mutate(value);
    if (next != value) {
      value = next;
    }
  }
}

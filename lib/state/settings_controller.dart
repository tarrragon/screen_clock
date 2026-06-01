import 'package:flutter/foundation.dart';

import '../models/settings_model.dart';
import '../services/auto_launch_service.dart';
import '../services/settings_service.dart';

/// 設定轉換規則：收當前設定、回傳改好的新設定（通常以 [SettingsModel.copyWith] 實作）。
typedef SettingsMutator = SettingsModel Function(SettingsModel current);

/// 設定的可變狀態（SPEC-005 FR-04 + SPEC-006 FR-01）。
///
/// 採內建 [ValueNotifier] 取代第三方狀態管理套件，維持 MVP 依賴簡潔。
/// 啟動時保留 [_initial] 快照供「取消」還原；「儲存」會寫入 [SettingsService]
/// 並同步 OS 的開機啟動狀態（[AutoLaunchService]）。
class SettingsController extends ValueNotifier<SettingsModel> {
  SettingsController({
    required SettingsModel initial,
    required SettingsService service,
    required AutoLaunchService autoLaunchService,
  })  : _initial = initial,
        _service = service,
        _autoLaunchService = autoLaunchService,
        super(initial);

  final SettingsModel _initial;
  final SettingsService _service;
  final AutoLaunchService _autoLaunchService;

  SettingsModel get initial => _initial;

  /// 取消編輯：還原為啟動時快照（SPEC-005 FR-04 / Settings Panel Cancel）。
  void resetToStartup() {
    value = _initial;
  }

  /// 儲存當前 value 並非同步寫入持久層 + 套用開機啟動。
  /// 失敗由各自服務內部 log，不拋例外（SPEC-004 FR-03 + SPEC-006 FR-01）。
  Future<void> persist() async {
    await _service.save(value);
    final bool osState =
        await _autoLaunchService.setEnabled(value.autoLaunch);
    if (osState != value.autoLaunch) {
      // OS 沒有真的切換成功時把 UI 狀態同步回 OS 真實狀態。
      value = value.copyWith(autoLaunch: osState);
      await _service.save(value);
    }
  }

  /// 套用一條「目前設定 → 新設定」的轉換規則（避免外部寫死大量 copyWith 呼叫）。
  ///
  /// 傳入的 [transform] 收當前設定、回傳改好的新設定；本方法負責取值、去重
  /// （值未變不重設）、賦回並通知監聽者重繪。
  ///
  /// 範例：`controller.update((s) => s.copyWith(fillColor: c));`
  void update(SettingsMutator transform) {
    final SettingsModel next = transform(value);
    if (next != value) {
      value = next;
    }
  }
}

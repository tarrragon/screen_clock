import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../app_constants.dart';
import '../models/settings_model.dart';
import 'cursor_locator.dart';

/// 熱鍵註冊 / 解除的最小介面（ticket 1.4.0-W2-005 D1：可測性）。
///
/// `hotkey_manager` 的 `hotKeyManager` 是全域單例，單元測試無法真實觸發
/// 系統層註冊。本介面讓 [CursorLocatorHotkeyController] 可注入替身記錄
/// 呼叫序列，不依賴真實平台 API（測試斷言禁計時，見
/// `.claude/rules/core/test-assertion-design-rules.md` D 規則）。
abstract class HotKeyRegistrar {
  Future<void> register(HotKey hotKey, {required HotKeyHandler keyDownHandler});

  Future<void> unregister(HotKey hotKey);
}

/// 委派至 `hotkey_manager` 全域單例的預設實作。
class HotkeyManagerRegistrar implements HotKeyRegistrar {
  const HotkeyManagerRegistrar();

  @override
  Future<void> register(
    HotKey hotKey, {
    required HotKeyHandler keyDownHandler,
  }) {
    return hotKeyManager.register(hotKey, keyDownHandler: keyDownHandler);
  }

  @override
  Future<void> unregister(HotKey hotKey) => hotKeyManager.unregister(hotKey);
}

/// 滑鼠定位器全域熱鍵生命週期（SPEC-008 FR-01，ticket 1.4.0-W2-005）。
///
/// 依 [SettingsModel.cursorLocatorEnabled] 的翻轉註冊 / 解除
/// `Cmd + Option + L`（UC-06 主成功場景步驟 1、替代場景 06c：停用後該
/// 組合鍵須真正回歸系統預設行為，非僅忽略觸發）。觸發時呼叫
/// [CursorLocator.play]，播放參數（時長、主色調）於觸發當下讀取最新設定值
/// （D3：值域 0.5-3.0 的執行期夾制屬 1.4.0-W2-010，本類別僅單位換算）。
///
/// 註冊失敗依 SPEC-008 EX-06-01：記錄 warning 日誌、定位器維持停用，
/// 不做 GUI 提示（本票不動 `settings_panel.dart`，見 ticket AC 裁決）。
///
/// [settings] 收窄為 [ValueListenable]（而非具體的 `SettingsController`）：
/// 本類別全程只用到 `.value` / `.addListener` / `.removeListener`，不需要
/// `SettingsController` 額外攜帶的 `persist()` / `resetToStartup()` 等能力
/// （Phase 4 coupling 審查：依賴窄化，`SettingsController` 已是
/// `ValueListenable<SettingsModel>` 子型別，呼叫端無需改動）。
class CursorLocatorHotkeyController {
  CursorLocatorHotkeyController({
    required ValueListenable<SettingsModel> settings,
    required CursorLocator locator,
    HotKeyRegistrar? registrar,
  }) : _settings = settings,
       _locator = locator,
       _registrar = registrar ?? const HotkeyManagerRegistrar();

  static const String _tag = 'cursor-locator-hotkey';

  final ValueListenable<SettingsModel> _settings;
  final CursorLocator _locator;
  final HotKeyRegistrar _registrar;

  HotKey? _registeredHotKey;
  bool _lastEnabled = false;

  /// 目前是否已向系統註冊熱鍵（供測試 / 觀察用）。
  bool get isRegistered => _registeredHotKey != null;

  /// 依目前設定值同步初始熱鍵狀態，並開始監聽後續啟用開關翻轉。
  Future<void> start() async {
    _lastEnabled = _settings.value.cursorLocatorEnabled;
    if (_lastEnabled) {
      await _register();
    }
    _settings.addListener(_onSettingsChanged);
  }

  /// 停止監聽並解除已註冊的熱鍵（app 結束 / controller 釋放時呼叫）。
  Future<void> stop() async {
    _settings.removeListener(_onSettingsChanged);
    await _unregister();
  }

  /// 僅在 `cursorLocatorEnabled` 真的翻轉時動作，避免時長、主色調等其他
  /// 設定變更誤觸重複註冊 / 解除（D2）。
  void _onSettingsChanged() {
    final bool enabled = _settings.value.cursorLocatorEnabled;
    if (enabled == _lastEnabled) return;
    _lastEnabled = enabled;
    if (enabled) {
      unawaited(_register());
    } else {
      unawaited(_unregister());
    }
  }

  Future<void> _register() async {
    if (_registeredHotKey != null) return;
    final HotKey hotKey = HotKey(
      key: AppCursorLocator.hotkeyPhysicalKey,
      modifiers: AppCursorLocator.hotkeyModifiers,
      scope: HotKeyScope.system,
    );
    try {
      await _registrar.register(hotKey, keyDownHandler: (_) => _onTriggered());
      _registeredHotKey = hotKey;
    } catch (error) {
      // EX-06-01：warning 日誌 + 定位器維持停用，無 GUI 提示。
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('熱鍵註冊失敗: $error', name: _tag, level: 900);
    }
  }

  Future<void> _unregister() async {
    final HotKey? hotKey = _registeredHotKey;
    if (hotKey == null) return;
    _registeredHotKey = null;
    try {
      await _registrar.unregister(hotKey);
    } catch (error) {
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('熱鍵解除失敗: $error', name: _tag, level: 900);
    }
  }

  /// 熱鍵觸發：讀取當下最新設定值換算播放參數，經 [CursorLocator.play]
  /// 呼叫特效層入口。
  void _onTriggered() {
    final SettingsModel value = _settings.value;
    unawaited(
      _locator.play(
        duration: Duration(
          milliseconds:
              (value.cursorLocatorEffectDurationSeconds *
                      Duration.millisecondsPerSecond)
                  .round(),
        ),
        tint: value.cursorLocatorPrimaryColor,
      ),
    );
  }
}

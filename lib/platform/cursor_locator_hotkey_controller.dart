import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../app_constants.dart';
import '../models/settings_model.dart';
import 'cursor_locator.dart';

/// 熱鍵註冊 / 解除的最小介面（可測性）。
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
/// 組合鍵須真正回歸系統預設行為，非僅忽略觸發）。觸發時讀取當下最新設定值
/// 換算播放參數——設定變更立即生效，不需重新註冊熱鍵；時長值域由
/// [SettingsModel] 保證，本類別只做單位換算。
///
/// 註冊 / 解除失敗依 SPEC-008 EX-06-01：記錄 warning 日誌，內部狀態只在
/// 操作成功時更新，失敗維持操作前的實際值，保留下次設定翻轉時重試的機會；
/// 不做 GUI 提示（本票不動 `settings_panel.dart`，見 ticket AC 裁決）。
///
/// [settings] 收窄為 [ValueListenable]（而非具體的 `SettingsController`）：
/// 本類別全程只用到 `.value` / `.addListener` / `.removeListener`，不需要
/// `SettingsController` 額外攜帶的 `persist()` / `resetToStartup()` 等能力。
class CursorLocatorHotkeyController {
  CursorLocatorHotkeyController({
    required ValueListenable<SettingsModel> settings,
    required CursorLocator locator,
    HotKeyRegistrar? registrar,
  }) : _settings = settings,
       _locator = locator,
       _registrar = registrar ?? const HotkeyManagerRegistrar();

  static const String _tag = 'cursor-locator-hotkey';

  /// 熱鍵定義固定不變（引用 [AppCursorLocatorHotkey] 常數，無硬編碼字面）；
  /// 建一次重用，避免每次註冊 / 解除都新建等價物件。
  static final HotKey _hotKey = HotKey(
    key: AppCursorLocatorHotkey.physicalKey,
    modifiers: AppCursorLocatorHotkey.modifiers,
    scope: HotKeyScope.system,
  );

  final ValueListenable<SettingsModel> _settings;
  final CursorLocator _locator;
  final HotKeyRegistrar _registrar;

  bool _started = false;
  bool _isRegistered = false;

  /// register / unregister 序列化佇列：避免設定快速連續翻轉時，前一個尚未
  /// 完成的操作與後一個操作交錯執行，讓 [_isRegistered] 落到與系統實際狀態
  /// 不一致的中間態。
  Future<void> _pending = Future<void>.value();

  /// 目前是否已向系統註冊熱鍵。
  bool get isRegistered => _isRegistered;

  /// 依目前設定值同步初始熱鍵狀態，並開始監聽後續啟用開關翻轉。
  /// 重複呼叫視為 no-op，不會疊加監聽器。
  Future<void> start() {
    if (_started) return _pending;
    _started = true;
    _settings.addListener(_onSettingsChanged);
    return _sync();
  }

  /// 停止監聽並解除已註冊的熱鍵（app 結束 / controller 釋放時呼叫）。
  Future<void> stop() {
    if (!_started) return _pending;
    _started = false;
    _settings.removeListener(_onSettingsChanged);
    return _apply(desired: false);
  }

  void _onSettingsChanged() => unawaited(_sync());

  Future<void> _sync() => _apply(desired: _settings.value.cursorLocatorEnabled);

  /// 將「期望是否已註冊」排入序列化佇列；已是目標狀態則不動作
  /// （此守衛本身即完成非啟用開關變更的去重，無需額外的翻轉追蹤變數）。
  Future<void> _apply({required bool desired}) {
    _pending = _pending.then((_) async {
      if (desired == _isRegistered) return;
      if (desired) {
        await _register();
      } else {
        await _unregister();
      }
    });
    return _pending;
  }

  /// 操作成功才更新 [_isRegistered]，失敗維持原狀態（未註冊），保留下次
  /// 設定翻轉時重試的機會。
  Future<void> _register() async {
    try {
      await _registrar.register(_hotKey, keyDownHandler: (_) => _onTriggered());
      _isRegistered = true;
    } catch (error) {
      // EX-06-01：warning 日誌 + 定位器維持停用，無 GUI 提示。
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('熱鍵註冊失敗: $error', name: _tag, level: 900);
    }
  }

  /// 操作成功才更新 [_isRegistered]，失敗維持原狀態（已註冊），保留下次
  /// 設定翻轉時重試的機會——不在呼叫前先清空狀態，避免解除失敗時系統仍
  /// 持有註冊、但內部狀態誤判為已解除而無法重試。
  Future<void> _unregister() async {
    try {
      await _registrar.unregister(_hotKey);
      _isRegistered = false;
    } catch (error) {
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('熱鍵解除失敗: $error', name: _tag, level: 900);
    }
  }

  /// 熱鍵觸發：讀取當下最新設定值（非註冊當下快照）換算播放參數，經
  /// [CursorLocator.play] 呼叫特效層入口。
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

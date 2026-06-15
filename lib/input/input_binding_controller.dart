import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_constants.dart';
import 'input_binding_channel.dart';
import 'mouse_binding.dart';

/// 滑鼠輸入綁定控制器（SPEC-007 FR-03/FR-07，ticket 1.3.0-W2-003）。
///
/// 連接設定層與原生橋接：app 啟動時把 [SettingsModel.bindings] 下傳原生
/// （由原生 CGEventTap 依綁定分派事件）；設定變更時重新下傳，使綁定即時生效。
///
/// 啟動時若有綁定但尚未取得輔助使用授權，主動觸發系統授權提示，讓使用者
/// 能直接啟用功能（避免有綁定卻因未授權而靜默失效）。授權狀態變化由原生
/// 經 channel 回報，控制器再補下傳一次綁定，確保授權後綁定立即套用。
class InputBindingController {
  InputBindingController({InputBindingChannel? channel})
      : _channel = channel ?? InputBindingChannel();

  final InputBindingChannel _channel;

  bool _started = false;

  /// 輔助使用授權狀態。供面板層監聽以切換引導與功能啟用狀態（FR-07）。
  /// 內部以可寫 notifier 維護，對外僅暴露唯讀 [permissionGranted]。
  /// 本專案 controller 無 dispose 生命週期，故 stop() 不釋放此 notifier。
  final ValueNotifier<bool> _permissionGranted = ValueNotifier<bool>(false);

  /// 對 UI 暴露的唯讀授權狀態（true=已取得輔助使用授權）。
  ValueListenable<bool> get permissionGranted => _permissionGranted;

  /// 進行中的側鍵捕捉回呼；null 代表目前未在捕捉。
  ValueChanged<int>? _captureCallback;

  /// 捕捉逾時計時器；逾時自動結束捕捉，避免長期停留捕捉狀態。
  Timer? _captureTimer;

  /// 啟動控制器：監聽授權變化、下傳初始綁定，必要時請求授權。
  ///
  /// [bindings] 為目前設定的綁定清單；空清單時不下傳、不請求授權
  /// （無綁定即無需 tap，避免無謂的系統授權提示）。
  Future<void> start(List<MouseBinding> bindings) async {
    if (_started) return;
    _started = true;
    _channel.start(
      onPermissionChanged: _onPermissionChanged,
      onButtonCaptured: _onButtonCaptured,
    );
    await syncBindings(bindings);
    if (bindings.isNotEmpty) {
      await _ensurePermission();
    }
  }

  /// 設定變更時重新下傳綁定，使原生分派即時反映新綁定。
  Future<void> syncBindings(List<MouseBinding> bindings) async {
    await _channel.updateBindings(bindings);
  }

  /// 主動查詢輔助使用授權狀態並寫入對外 notifier（SPEC-007 FR-07）。
  ///
  /// 面板開啟時呼叫：start() 僅在「有綁定」時經 _ensurePermission 更新授權狀態，
  /// 空綁定情境（即使系統已授權）notifier 仍停在 false，須主動刷新才反映真實授權。
  Future<void> refreshPermission() async {
    _permissionGranted.value = await _channel.queryPermission();
  }

  /// 觸發系統輔助使用授權提示後刷新狀態（SPEC-007 FR-07）。
  ///
  /// 供面板「開啟系統授權」按鈕呼叫；提示後使用者於系統設定的最終操作結果
  /// 由原生經 onPermissionChanged 回報，這裡再刷新一次確保 notifier 同步。
  Future<void> requestPermission() async {
    await _channel.requestPermission();
    await refreshPermission();
  }

  /// 停止監聽並釋放原生 handler。捕捉進行中時一併結束。
  void stop() {
    if (!_started) return;
    _started = false;
    _clearCapture();
    _channel.stop();
  }

  /// 查詢授權狀態寫入對外 notifier；未授權且有綁定時觸發系統提示。
  /// 空綁定清單不呼叫此方法（無綁定即無需 tap，避免無謂查詢與提示）。
  Future<void> _ensurePermission() async {
    final bool granted = await _channel.queryPermission();
    _permissionGranted.value = granted;
    if (!granted) {
      await _channel.requestPermission();
    }
  }

  /// 進入側鍵捕捉模式（SPEC-007 FR-06）。
  ///
  /// 登記 [onCaptured]，請原生開始監聽下一個側鍵；[timeout] 內未捕捉到任何
  /// 側鍵則自動結束。捕捉進行中再次呼叫會先結束前一個 session（防重入）。
  Future<void> startButtonCapture({
    required ValueChanged<int> onCaptured,
    Duration timeout = AppDurations.buttonCaptureTimeout,
  }) async {
    if (_captureCallback != null) {
      await cancelButtonCapture();
    }
    _captureCallback = onCaptured;
    _captureTimer = Timer(timeout, cancelButtonCapture);
    await _channel.beginCaptureButton();
  }

  /// 取消捕捉：通知原生離開捕捉模式，並清除登記的回呼與計時器。
  Future<void> cancelButtonCapture() async {
    if (_captureCallback == null) return;
    _clearCapture();
    await _channel.endCaptureButton();
  }

  /// 原生回報捕捉到側鍵：分派給登記的回呼後自動結束捕捉。
  void _onButtonCaptured(int buttonNumber) {
    final ValueChanged<int>? callback = _captureCallback;
    if (callback == null) return;
    _clearCapture();
    callback(buttonNumber);
    unawaited(_channel.endCaptureButton());
  }

  /// 清除捕捉登記與計時器（不發原生呼叫）。
  void _clearCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _captureCallback = null;
  }

  /// 授權狀態變化：更新對外 notifier；剛取得授權時補下傳一次綁定，
  /// 確保 tap 立即拿到最新綁定。
  void _onPermissionChanged(bool granted) {
    _permissionGranted.value = granted;
    if (!granted) return;
    debugPrint('[input-binding] 已取得輔助使用授權，補下傳綁定');
  }
}

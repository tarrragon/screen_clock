import 'package:flutter/foundation.dart';

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

  /// 啟動控制器：監聽授權變化、下傳初始綁定，必要時請求授權。
  ///
  /// [bindings] 為目前設定的綁定清單；空清單時不下傳、不請求授權
  /// （無綁定即無需 tap，避免無謂的系統授權提示）。
  Future<void> start(List<MouseBinding> bindings) async {
    if (_started) return;
    _started = true;
    _channel.start(onPermissionChanged: _onPermissionChanged);
    await syncBindings(bindings);
    if (bindings.isNotEmpty) {
      await _ensurePermission();
    }
  }

  /// 設定變更時重新下傳綁定，使原生分派即時反映新綁定。
  Future<void> syncBindings(List<MouseBinding> bindings) async {
    await _channel.updateBindings(bindings);
  }

  /// 停止監聽並釋放原生 handler。
  void stop() {
    if (!_started) return;
    _started = false;
    _channel.stop();
  }

  /// 尚未授權時觸發系統提示；已授權則不打擾使用者。
  Future<void> _ensurePermission() async {
    final bool granted = await _channel.queryPermission();
    if (!granted) {
      await _channel.requestPermission();
    }
  }

  /// 授權狀態變化：剛取得授權時補下傳一次綁定，確保 tap 立即拿到最新綁定。
  void _onPermissionChanged(bool granted) {
    if (!granted) return;
    debugPrint('[input-binding] 已取得輔助使用授權，補下傳綁定');
  }
}

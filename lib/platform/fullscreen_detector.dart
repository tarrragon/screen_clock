import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_constants.dart';

/// 假全螢幕覆蓋偵測橋接（ticket 1.2.1-W2-001）。
///
/// 監聽原生端（macos/Runner/MainFlutterWindow.swift 的
/// [FullscreenCoverageDetector]）經 method channel 回報的覆蓋狀態變化，
/// 將「目標螢幕是否被假全螢幕視窗鋪滿」轉成 Dart 端 callback。
///
/// 由 main.dart 持有，覆蓋狀態變化時切換 `_clockVisible`：
/// - covered=true → 隱藏時鐘（讓位給影片 / 簡報 / 遊戲）
/// - covered=false → 復現時鐘
///
/// 不動原生視窗，沿用 v1.2.0 的 Flutter 層條件渲染隱藏機制。
class FullscreenDetector {
  FullscreenDetector({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(AppFullscreenDetect.channelName);

  final MethodChannel _channel;

  /// 覆蓋狀態變化回呼。參數為「目標螢幕是否被假全螢幕覆蓋」。
  ValueChanged<bool>? _onCoverageChanged;

  /// 開始監聽原生覆蓋狀態通知。
  ///
  /// [onCoverageChanged] 在每次原生回報覆蓋狀態變化時呼叫（true=被覆蓋）。
  void start({required ValueChanged<bool> onCoverageChanged}) {
    _onCoverageChanged = onCoverageChanged;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// 停止監聽並清除 handler。
  void stop() {
    _onCoverageChanged = null;
    _channel.setMethodCallHandler(null);
  }

  /// 處理原生端 method call；僅認得覆蓋狀態變化方法。
  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != AppFullscreenDetect.onCoverageChangedMethod) {
      debugPrint('[fullscreen-detect] 未知原生方法: ${call.method}');
      return;
    }
    final bool covered = _parseCovered(call.arguments);
    _onCoverageChanged?.call(covered);
  }

  /// 從原生參數解析 covered 旗標；型別不符時保守視為未覆蓋。
  bool _parseCovered(Object? arguments) {
    if (arguments is Map) {
      final Object? value = arguments[AppFullscreenDetect.coveredArgKey];
      if (value is bool) {
        return value;
      }
    }
    debugPrint('[fullscreen-detect] 參數格式異常: $arguments');
    return false;
  }
}

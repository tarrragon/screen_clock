import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../app_constants.dart';

/// 滑鼠定位器 method channel 橋接（ticket 1.4.0-W1-001.3，SPEC-008 FR-01）。
///
/// Dart → 原生：於游標所在螢幕觸發定位特效播放（[play]）。本票只建立橋接
/// 骨架，原生端收到 play 僅以 NSLog 記錄；特效視窗管理留
/// 1.4.0-W2-006、視覺特效繪製留 1.4.0-W3-001。
///
/// channel 名 / 方法名 / 參數鍵一律引用 [AppCursorLocator] 常數，Swift 端
/// 以對應的常數宣告承載相同字面（method channel 無法跨語言共用常數定義）。
class CursorLocator {
  CursorLocator({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppCursorLocator.channelName);

  static const String _tag = 'cursor-locator';

  final MethodChannel _channel;

  /// 觸發原生端於游標所在螢幕播放定位特效。
  ///
  /// [durationSeconds] 為設定層單位（雙精度秒，SettingsModel 儲存格式），
  /// [tint] 為設定層色彩物件；本方法是設定層與傳輸層的換算點——
  /// 傳輸層以整數毫秒（[AppCursorLocator.durationMsArgKey]）與 ARGB 整數
  /// （[AppCursorLocator.tintArgbArgKey]）傳遞，換算集中於
  /// [_durationSecondsToMs] 與 [_tintToArgb] 兩個具名轉換點，避免單位變更
  /// 隱含在呼叫式中無從察覺（1.4.0-W1-011 實測 E3）。
  Future<void> play({
    required double durationSeconds,
    required Color tint,
  }) async {
    final int durationMs = _durationSecondsToMs(durationSeconds);
    final int tintArgb = _tintToArgb(tint);
    // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
    developer.log('play 呼叫: durationMs=$durationMs, tintArgb=$tintArgb', name: _tag);
    try {
      await _channel.invokeMethod<void>(
        AppCursorLocator.playMethod,
        <String, Object?>{
          AppCursorLocator.durationMsArgKey: durationMs,
          AppCursorLocator.tintArgbArgKey: tintArgb,
        },
      );
    } on PlatformException catch (e) {
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('play PlatformException: code=${e.code} message=${e.message}', name: _tag, level: 900);
    } on MissingPluginException catch (e) {
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('play MissingPluginException: message=${e.message}', name: _tag, level: 900);
    }
  }

  /// 設定層（雙精度秒）→ 傳輸層（整數毫秒）換算點。
  int _durationSecondsToMs(double durationSeconds) =>
      (durationSeconds * 1000).round();

  /// 設定層（Color 物件）→ 傳輸層（ARGB 整數）換算點。
  int _tintToArgb(Color tint) => tint.toARGB32();
}

import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../app_constants.dart';
import 'method_channel_safety.dart';

/// 滑鼠定位器 method channel 橋接（ticket 1.4.0-W1-001.3，SPEC-008 FR-01）。
///
/// Dart → 原生：於游標所在螢幕觸發定位特效播放（[play]）。本票只建立橋接
/// 骨架，原生端收到 play 僅以 NSLog 記錄；特效視窗管理留
/// 1.4.0-W2-006、視覺特效繪製留 1.4.0-W3-001。
///
/// channel 名 / 方法名 / 參數鍵一律引用 [AppCursorLocatorChannel] 常數，
/// Swift 端以對應的常數宣告承載相同字面（method channel 無法跨語言共用
/// 常數定義）。
class CursorLocator {
  CursorLocator({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(AppCursorLocatorChannel.channelName);

  static const String _tag = 'cursor-locator';

  final MethodChannel _channel;

  /// 觸發原生端於游標所在螢幕播放定位特效。
  ///
  /// [duration] 與 [tint] 為 SPEC-008 介面規格節訂的簽章；本方法是設定層
  /// （[Duration] / [Color]）與傳輸層的換算點——傳輸層以整數毫秒
  /// （[AppCursorLocatorChannel.durationMsArgKey]）與 ARGB 整數
  /// （[AppCursorLocatorChannel.tintArgbArgKey]）傳遞。色彩換算集中於 [_tintToArgb]
  /// 具名轉換點，與時長換算（`duration.inMilliseconds`）維持同一層級、
  /// 同一風格，皆不散落在呼叫式中。轉換與 channel 呼叫同在 try 區塊內，
  /// NaN / Infinite 等異常輸入與 [PlatformException] 共用同一 catch-log
  /// 路徑。
  ///
  /// 例外契約：原生端不可用或拋錯時本方法不拋例外，僅記錄；呼叫端無法由
  /// 回傳值得知播放是否成功。
  Future<void> play({required Duration duration, required Color tint}) async {
    try {
      final int durationMs = duration.inMilliseconds;
      final int tintArgb = _tintToArgb(tint);
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log(
        'play 呼叫: durationMs=$durationMs, tintArgb=$tintArgb',
        name: _tag,
      );
      await invokeMethodSafely<void>(
        _channel,
        AppCursorLocatorChannel.playMethod,
        tag: _tag,
        arguments: <String, Object?>{
          AppCursorLocatorChannel.durationMsArgKey: durationMs,
          AppCursorLocatorChannel.tintArgbArgKey: tintArgb,
        },
      );
    } on UnsupportedError catch (e) {
      // 色彩換算（NaN/Infinite 分量）失敗於呼叫 invokeMethod 前即拋出，
      // 屬本方法的換算邏輯而非 method channel 呼叫本身，故不收進共用包裝。
      // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
      developer.log('play 轉換失敗: message=${e.message}', name: _tag, level: 900);
    }
  }

  /// 設定層（Color 物件）→ 傳輸層（ARGB 整數）換算點。
  int _tintToArgb(Color tint) => tint.toARGB32();
}

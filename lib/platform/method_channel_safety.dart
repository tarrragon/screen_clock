import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// method channel 呼叫失敗安全包裝共用實作（ticket 1.4.0-W2-007）。
///
/// 收斂 `cursor_locator.dart` 與 `input_binding_channel.dart` 原本各自
/// 一份的 try / catch PlatformException / catch MissingPluginException /
/// 記錄後安全吞掉骨架。呼叫失敗時回傳 null，不外洩例外——維持兩側呼叫端
/// 既有的「記錄後吞掉不外洩」契約不變（是否改為讓呼叫端能感知失敗，屬
/// 1.4.0-W2-016 評估範圍，本票不處理）。
///
/// 涵蓋範圍僅 [PlatformException] 與 [MissingPluginException]：這兩者是
/// `invokeMethod` 本身會拋出的例外，為兩側呼叫端共同需要。
/// `cursor_locator.dart` 另有的 `UnsupportedError` 分支，捕捉的是呼叫
/// `invokeMethod` 前色彩換算（[Color.toARGB32]）對 NaN/Infinite 分量拋出
/// 的例外，屬呼叫端業務邏輯而非「呼叫 method channel」這件事本身，故不
/// 收進共用包裝，維持在呼叫端自行 catch。
Future<T?> invokeMethodSafely<T>(
  MethodChannel channel,
  String method, {
  required String tag,
  Object? arguments,
}) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (e) {
    // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
    developer.log(
      '$method PlatformException: code=${e.code} message=${e.message}',
      name: tag,
      level: 900,
    );
    return null;
  } on MissingPluginException catch (e) {
    // i18n-exempt: 開發者除錯日誌，非 user-facing 文字。
    developer.log(
      '$method MissingPluginException: message=${e.message}',
      name: tag,
      level: 900,
    );
    return null;
  }
}

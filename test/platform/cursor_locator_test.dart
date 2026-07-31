// CursorLocator 單元測試（ticket 1.4.0-W1-001.3；簽章與例外路徑於
// 1.4.0-W1-001.5 調整）。
//
// 驗證 Dart → 原生的 play 呼叫橋接：method channel 名 / 方法名 / 參數鍵
// 引用 AppCursorLocator 常數、參數換算（Duration→毫秒、Color→ARGB）、
// PlatformException / MissingPluginException / 轉換期例外不外洩。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/platform/cursor_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late CursorLocator locator;
  late List<MethodCall> calls;

  setUp(() {
    channel = const MethodChannel(AppCursorLocator.channelName);
    locator = CursorLocator(channel: channel);
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('play 呼叫使用 AppCursorLocator.playMethod 並帶入換算後參數', () async {
    await locator.play(
      duration: const Duration(milliseconds: 1500),
      tint: const Color(0xFF2196F3),
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, AppCursorLocator.playMethod);
    expect(
      calls.single.arguments,
      <String, Object?>{
        AppCursorLocator.durationMsArgKey: 1500,
        AppCursorLocator.tintArgbArgKey: 0xFF2196F3,
      },
    );
  });

  test('PlatformException 不外洩', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ERROR', message: 'boom');
    });

    await expectLater(
      locator.play(
        duration: const Duration(seconds: 1),
        tint: const Color(0xFFFFFFFF),
      ),
      completes,
    );
  });

  test('MissingPluginException 不外洩', () async {
    // 未註冊 handler 時 invokeMethod 會自然拋出 MissingPluginException。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    await expectLater(
      locator.play(
        duration: const Duration(seconds: 1),
        tint: const Color(0xFFFFFFFF),
      ),
      completes,
    );
  });

  test('色彩轉換期例外（NaN 分量）不外洩，走 catch-log 路徑', () async {
    // 損毀或竄改的偏好設定檔可能解析出 NaN 分量的 Color；_floatToInt8 對 NaN
    // 呼叫 round() 會拋 UnsupportedError，驗證此例外落在既有 catch-log 路徑
    // 而非未捕捉例外（1.4.0-W1-001.5 B 項）。
    const Color corruptTint = Color.from(
      alpha: double.nan,
      red: 0,
      green: 0,
      blue: 0,
    );

    await expectLater(
      locator.play(
        duration: const Duration(seconds: 1),
        tint: corruptTint,
      ),
      completes,
    );
    expect(calls, isEmpty);
  });
}

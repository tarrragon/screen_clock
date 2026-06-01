// FullscreenDetector 單元測試（ticket 1.2.1-W2-001）。
//
// 驗證原生 → Dart 的覆蓋狀態橋接邏輯：方法名比對、參數解析、callback 觸發。
// 原生 CGWindowList 覆蓋判定屬 macOS 環境行為，須實機 runtime 驗收（acceptance #3）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/platform/fullscreen_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late FullscreenDetector detector;
  late List<bool> received;

  setUp(() {
    channel = const MethodChannel(AppFullscreenDetect.channelName);
    detector = FullscreenDetector(channel: channel);
    received = <bool>[];
  });

  tearDown(() {
    detector.stop();
  });

  /// 模擬原生端 invokeMethod 推送到 Dart handler。
  Future<void> sendNativeCall(String method, Object? arguments) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, message, (_) {});
  }

  test('被假全螢幕覆蓋時回報 true', () async {
    detector.start(onCoverageChanged: received.add);

    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      <String, Object?>{AppFullscreenDetect.coveredArgKey: true},
    );

    expect(received, <bool>[true]);
  });

  test('退出假全螢幕時回報 false', () async {
    detector.start(onCoverageChanged: received.add);

    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      <String, Object?>{AppFullscreenDetect.coveredArgKey: false},
    );

    expect(received, <bool>[false]);
  });

  test('覆蓋狀態連續變化依序回報', () async {
    detector.start(onCoverageChanged: received.add);

    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      <String, Object?>{AppFullscreenDetect.coveredArgKey: true},
    );
    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      <String, Object?>{AppFullscreenDetect.coveredArgKey: false},
    );

    expect(received, <bool>[true, false]);
  });

  test('未知方法不觸發 callback', () async {
    detector.start(onCoverageChanged: received.add);

    await sendNativeCall('someOtherMethod', null);

    expect(received, isEmpty);
  });

  test('參數格式異常保守視為未覆蓋', () async {
    detector.start(onCoverageChanged: received.add);

    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      'not-a-map',
    );

    expect(received, <bool>[false]);
  });

  test('stop 後不再觸發 callback', () async {
    detector.start(onCoverageChanged: received.add);
    detector.stop();

    await sendNativeCall(
      AppFullscreenDetect.onCoverageChangedMethod,
      <String, Object?>{AppFullscreenDetect.coveredArgKey: true},
    );

    expect(received, isEmpty);
  });
}

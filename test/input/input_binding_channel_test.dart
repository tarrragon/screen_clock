// InputBindingChannel 單元測試（ticket 1.3.0-W2-001，SPEC-007 FR-07）。
//
// 驗證 Dart ↔ 原生橋接邏輯：授權查詢 / 請求的 invokeMethod 呼叫與回傳處理、
// 綁定下傳的序列化 payload、原生 → Dart 授權狀態變化的 callback 觸發。
// 原生 AXIsProcessTrusted / CGEventTap 屬 macOS 環境行為，須實機 runtime 驗收。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/input_binding_channel.dart';
import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late InputBindingChannel bridge;
  late List<MethodCall> nativeCalls;
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    channel = const MethodChannel(AppInputBinding.channelName);
    bridge = InputBindingChannel(channel: channel);
    nativeCalls = <MethodCall>[];
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    bridge.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 以指定回傳值掛上 mock 原生 handler，並記錄收到的呼叫。
  void mockNative(Object? Function(MethodCall call) respond) {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      nativeCalls.add(call);
      return respond(call);
    });
  }

  /// 模擬原生端 invokeMethod 推送到 Dart handler。
  Future<void> sendNativeCall(String method, Object? arguments) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});
  }

  group('queryPermission', () {
    test('呼叫 queryPermission 並回傳原生 true', () async {
      mockNative((_) => true);

      final bool granted = await bridge.queryPermission();

      expect(granted, isTrue);
      expect(nativeCalls.single.method,
          AppInputBinding.queryPermissionMethod);
    });

    test('原生回傳 false 視為未授權', () async {
      mockNative((_) => false);

      expect(await bridge.queryPermission(), isFalse);
    });

    test('原生回傳非 bool 保守視為未授權', () async {
      mockNative((_) => null);

      expect(await bridge.queryPermission(), isFalse);
    });

    test('PlatformException 保守視為未授權不拋出', () async {
      mockNative((_) => throw PlatformException(code: 'boom'));

      expect(await bridge.queryPermission(), isFalse);
    });
  });

  group('requestPermission', () {
    test('呼叫 requestPermission 並回傳原生狀態', () async {
      mockNative((_) => true);

      final bool granted = await bridge.requestPermission();

      expect(granted, isTrue);
      expect(nativeCalls.single.method,
          AppInputBinding.requestPermissionMethod);
    });
  });

  group('updateBindings', () {
    test('下傳綁定序列化為 JSON map 清單', () async {
      mockNative((_) => null);
      final List<MouseBinding> bindings = <MouseBinding>[
        const MouseBinding(
          buttonNumber: 3,
          action: DragScrollAction(),
        ),
        MouseBinding(
          buttonNumber: 4,
          action: HotkeyAction(keyCode: 123, modifiers: const <int>[256]),
        ),
      ];

      await bridge.updateBindings(bindings);

      expect(nativeCalls.single.method,
          AppInputBinding.updateBindingsMethod);
      final Map<Object?, Object?> args =
          nativeCalls.single.arguments as Map<Object?, Object?>;
      final List<Object?> payload =
          args[AppInputBinding.bindingsArgKey] as List<Object?>;
      expect(payload, hasLength(2));
      final Map<Object?, Object?> first =
          payload.first as Map<Object?, Object?>;
      expect(first[AppInputBinding.buttonNumberKey], 3);
    });

    test('空綁定清單下傳空 payload', () async {
      mockNative((_) => null);

      await bridge.updateBindings(const <MouseBinding>[]);

      final Map<Object?, Object?> args =
          nativeCalls.single.arguments as Map<Object?, Object?>;
      expect(args[AppInputBinding.bindingsArgKey], isEmpty);
    });
  });

  group('onPermissionChanged', () {
    test('原生回報授權變化觸發 callback', () async {
      final List<bool> received = <bool>[];
      bridge.start(onPermissionChanged: received.add);

      await sendNativeCall(
        AppInputBinding.onPermissionChangedMethod,
        <String, Object?>{AppInputBinding.grantedArgKey: true},
      );

      expect(received, <bool>[true]);
    });

    test('授權狀態連續變化依序回報', () async {
      final List<bool> received = <bool>[];
      bridge.start(onPermissionChanged: received.add);

      await sendNativeCall(
        AppInputBinding.onPermissionChangedMethod,
        <String, Object?>{AppInputBinding.grantedArgKey: false},
      );
      await sendNativeCall(
        AppInputBinding.onPermissionChangedMethod,
        <String, Object?>{AppInputBinding.grantedArgKey: true},
      );

      expect(received, <bool>[false, true]);
    });

    test('未知方法不觸發 callback', () async {
      final List<bool> received = <bool>[];
      bridge.start(onPermissionChanged: received.add);

      await sendNativeCall('someOtherMethod', null);

      expect(received, isEmpty);
    });

    test('參數格式異常保守視為未授權', () async {
      final List<bool> received = <bool>[];
      bridge.start(onPermissionChanged: received.add);

      await sendNativeCall(
        AppInputBinding.onPermissionChangedMethod,
        'not-a-map',
      );

      expect(received, <bool>[false]);
    });

    test('stop 後不再觸發 callback', () async {
      final List<bool> received = <bool>[];
      bridge.start(onPermissionChanged: received.add);
      bridge.stop();

      await sendNativeCall(
        AppInputBinding.onPermissionChangedMethod,
        <String, Object?>{AppInputBinding.grantedArgKey: true},
      );

      expect(received, isEmpty);
    });
  });

  group('beginCaptureButton / endCaptureButton', () {
    test('beginCaptureButton 發出對應原生方法', () async {
      mockNative((_) => null);

      await bridge.beginCaptureButton();

      expect(nativeCalls.single.method,
          AppInputBinding.beginCaptureButtonMethod);
    });

    test('endCaptureButton 發出對應原生方法', () async {
      mockNative((_) => null);

      await bridge.endCaptureButton();

      expect(nativeCalls.single.method,
          AppInputBinding.endCaptureButtonMethod);
    });

    test('beginCaptureButton 遇 PlatformException 不拋出', () async {
      mockNative((_) => throw PlatformException(code: 'boom'));

      await expectLater(bridge.beginCaptureButton(), completes);
    });
  });

  group('onButtonCaptured', () {
    test('原生回報捕捉到的按鍵觸發 callback', () async {
      final List<int> received = <int>[];
      bridge.start(
        onPermissionChanged: (_) {},
        onButtonCaptured: received.add,
      );

      await sendNativeCall(
        AppInputBinding.onButtonCapturedMethod,
        <String, Object?>{AppInputBinding.capturedButtonNumberArgKey: 4},
      );

      expect(received, <int>[4]);
    });

    test('參數型別不符時忽略不拋出且不觸發 callback', () async {
      final List<int> received = <int>[];
      bridge.start(
        onPermissionChanged: (_) {},
        onButtonCaptured: received.add,
      );

      await sendNativeCall(
        AppInputBinding.onButtonCapturedMethod,
        <String, Object?>{
          AppInputBinding.capturedButtonNumberArgKey: 'not-an-int',
        },
      );

      expect(received, isEmpty);
    });

    test('未提供 onButtonCaptured 時收到回報不拋出', () async {
      bridge.start(onPermissionChanged: (_) {});

      await expectLater(
        sendNativeCall(
          AppInputBinding.onButtonCapturedMethod,
          <String, Object?>{AppInputBinding.capturedButtonNumberArgKey: 4},
        ),
        completes,
      );
    });
  });
}

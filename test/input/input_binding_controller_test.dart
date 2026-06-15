// InputBindingController 單元測試（ticket 1.3.0-W2-003，SPEC-007 FR-03/FR-07）。
//
// 驗證控制器與原生橋接的協作：啟動時下傳初始綁定、未授權時請求授權、
// 設定變更時重新下傳、停止時釋放 handler。原生 CGEventTap 合成滾輪 /
// 系統授權提示屬 macOS 環境行為，須實機 runtime 驗收。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/input_binding_channel.dart';
import 'package:screen_clock/input/input_binding_controller.dart';
import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late InputBindingController controller;
  late List<MethodCall> nativeCalls;
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    channel = const MethodChannel(AppInputBinding.channelName);
    controller = InputBindingController(
      channel: InputBindingChannel(channel: channel),
    );
    nativeCalls = <MethodCall>[];
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    controller.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// mock 原生 handler：queryPermission 回傳指定授權狀態，其餘回 null。
  void mockNative({required bool granted}) {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      nativeCalls.add(call);
      if (call.method == AppInputBinding.queryPermissionMethod ||
          call.method == AppInputBinding.requestPermissionMethod) {
        return granted;
      }
      return null;
    });
  }

  List<MethodCall> callsOf(String method) =>
      nativeCalls.where((MethodCall c) => c.method == method).toList();

  final List<MouseBinding> sampleBindings = <MouseBinding>[
    const MouseBinding(buttonNumber: 4, action: DragScrollAction()),
  ];

  group('start', () {
    test('下傳初始綁定到原生', () async {
      mockNative(granted: true);

      await controller.start(sampleBindings);

      final List<MethodCall> updates =
          callsOf(AppInputBinding.updateBindingsMethod);
      expect(updates, hasLength(1));
      final Map<Object?, Object?> args =
          updates.single.arguments as Map<Object?, Object?>;
      final List<Object?> payload =
          args[AppInputBinding.bindingsArgKey] as List<Object?>;
      expect(payload, hasLength(1));
    });

    test('有綁定但未授權時觸發系統授權提示', () async {
      mockNative(granted: false);

      await controller.start(sampleBindings);

      expect(callsOf(AppInputBinding.queryPermissionMethod), hasLength(1));
      expect(callsOf(AppInputBinding.requestPermissionMethod), hasLength(1));
    });

    test('已授權時不再請求授權', () async {
      mockNative(granted: true);

      await controller.start(sampleBindings);

      expect(callsOf(AppInputBinding.requestPermissionMethod), isEmpty);
    });

    test('空綁定清單不請求授權但仍下傳空清單', () async {
      mockNative(granted: false);

      await controller.start(const <MouseBinding>[]);

      expect(callsOf(AppInputBinding.updateBindingsMethod), hasLength(1));
      expect(callsOf(AppInputBinding.queryPermissionMethod), isEmpty);
      expect(callsOf(AppInputBinding.requestPermissionMethod), isEmpty);
    });

    test('重複 start 不重複初始化', () async {
      mockNative(granted: true);

      await controller.start(sampleBindings);
      await controller.start(sampleBindings);

      expect(callsOf(AppInputBinding.updateBindingsMethod), hasLength(1));
    });
  });

  group('syncBindings', () {
    test('設定變更時重新下傳綁定', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      await controller.syncBindings(<MouseBinding>[
        const MouseBinding(buttonNumber: 5, action: DragScrollAction()),
      ]);

      final List<MethodCall> updates =
          callsOf(AppInputBinding.updateBindingsMethod);
      expect(updates, hasLength(2));
      final Map<Object?, Object?> args =
          updates.last.arguments as Map<Object?, Object?>;
      final List<Object?> payload =
          args[AppInputBinding.bindingsArgKey] as List<Object?>;
      final Map<Object?, Object?> first = payload.single as Map<Object?, Object?>;
      expect(first[AppInputBinding.buttonNumberKey], 5);
    });
  });

  /// 模擬原生端 onButtonCaptured 推送到 Dart handler。
  Future<void> sendButtonCaptured(int buttonNumber) async {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        AppInputBinding.onButtonCapturedMethod,
        <String, Object?>{
          AppInputBinding.capturedButtonNumberArgKey: buttonNumber,
        },
      ),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});
  }

  group('permissionGranted', () {
    test('start 時以查詢結果初始化授權狀態', () async {
      mockNative(granted: true);

      await controller.start(sampleBindings);

      expect(controller.permissionGranted.value, isTrue);
    });

    test('原生回報授權變化時更新 ValueListenable', () async {
      mockNative(granted: false);
      await controller.start(sampleBindings);
      expect(controller.permissionGranted.value, isFalse);

      final ByteData message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall(
          AppInputBinding.onPermissionChangedMethod,
          <String, Object?>{AppInputBinding.grantedArgKey: true},
        ),
      );
      await messenger.handlePlatformMessage(channel.name, message, (_) {});

      expect(controller.permissionGranted.value, isTrue);
    });
  });

  group('startButtonCapture', () {
    test('發出 beginCaptureButton', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      await controller.startButtonCapture(onCaptured: (_) {});

      expect(callsOf(AppInputBinding.beginCaptureButtonMethod), hasLength(1));
    });

    test('收到捕捉回報時呼叫 onCaptured 並自動結束捕捉', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      await controller.startButtonCapture(onCaptured: captured.add);

      await sendButtonCaptured(4);

      expect(captured, <int>[4]);
      expect(callsOf(AppInputBinding.endCaptureButtonMethod), hasLength(1));
    });

    test('捕捉結束後再次回報不再呼叫 onCaptured', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      await controller.startButtonCapture(onCaptured: captured.add);
      await sendButtonCaptured(4);
      await sendButtonCaptured(5);

      expect(captured, <int>[4]);
    });

    test('逾時自動結束捕捉', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      await controller.startButtonCapture(
        onCaptured: captured.add,
        timeout: const Duration(milliseconds: 10),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(captured, isEmpty);
      expect(callsOf(AppInputBinding.endCaptureButtonMethod), hasLength(1));
    });
  });

  group('cancelButtonCapture', () {
    test('發出 endCaptureButton 並停止後續回報', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      await controller.startButtonCapture(onCaptured: captured.add);
      await controller.cancelButtonCapture();

      expect(callsOf(AppInputBinding.endCaptureButtonMethod), hasLength(1));

      await sendButtonCaptured(4);
      expect(captured, isEmpty);
    });
  });

  group('onCancelled 回呼（W4-004：通知 UI 捕捉無結果）', () {
    test('逾時觸發 onCancelled，不觸發 onCaptured', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      int cancelled = 0;
      await controller.startButtonCapture(
        onCaptured: captured.add,
        onCancelled: () => cancelled++,
        timeout: const Duration(milliseconds: 10),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(captured, isEmpty);
      expect(cancelled, 1);
    });

    test('外部 cancelButtonCapture 觸發 onCancelled', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      int cancelled = 0;
      await controller.startButtonCapture(
        onCaptured: (_) {},
        onCancelled: () => cancelled++,
      );
      await controller.cancelButtonCapture();

      expect(cancelled, 1);
    });

    test('成功捕捉時不觸發 onCancelled', () async {
      mockNative(granted: true);
      await controller.start(sampleBindings);

      final List<int> captured = <int>[];
      int cancelled = 0;
      await controller.startButtonCapture(
        onCaptured: captured.add,
        onCancelled: () => cancelled++,
      );

      await sendButtonCaptured(4);

      expect(captured, <int>[4]);
      expect(cancelled, 0);
    });
  });
}

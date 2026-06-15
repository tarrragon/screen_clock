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
}

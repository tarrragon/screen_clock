// CursorLocatorHotkeyController 單元測試（ticket 1.4.0-W2-005，SPEC-008
// FR-01，UC-06 主成功場景步驟 1 / 替代場景 06c / 例外場景 EX-06-01）。
//
// 驗證熱鍵註冊 / 解除生命週期綁定 SettingsModel.cursorLocatorEnabled 的
// 翻轉、觸發時讀取當下最新設定值換算播放參數、熱鍵定義引用
// AppCursorLocatorHotkey 常數無硬編碼、註冊 / 解除失敗皆不外洩例外且維持
// 可重試的內部狀態。
//
// 依 test-assertion-design-rules D 規則：全程以 HotKeyRegistrar 替身記錄
// 呼叫序列斷言，不使用 Stopwatch 計時門檻；`pumpEventQueue()` 排空整個
// 事件佇列（非固定推進一個 microtask turn），對替身未來加入 await 延遲
// 仍具穩健性。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/platform/cursor_locator.dart';
import 'package:screen_clock/platform/cursor_locator_hotkey_controller.dart';

class _FakeHotKeyRegistrar implements HotKeyRegistrar {
  final List<String> calls = <String>[];
  HotKey? lastRegisteredHotKey;
  HotKeyHandler? lastKeyDownHandler;
  bool throwOnRegister = false;
  bool throwOnUnregister = false;

  @override
  Future<void> register(
    HotKey hotKey, {
    required HotKeyHandler keyDownHandler,
  }) async {
    calls.add('register');
    if (throwOnRegister) {
      throw PlatformException(code: 'ERROR', message: 'boom');
    }
    lastRegisteredHotKey = hotKey;
    lastKeyDownHandler = keyDownHandler;
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    calls.add('unregister');
    if (throwOnUnregister) {
      throw PlatformException(code: 'ERROR', message: 'boom');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late CursorLocator locator;
  late List<MethodCall> playCalls;
  late _FakeHotKeyRegistrar registrar;
  // ValueNotifier<SettingsModel>（非 SettingsController）：本測試只需
  // ValueListenable 介面（.value/.addListener/.removeListener），與受測
  // CursorLocatorHotkeyController 的窄化依賴一致，不需要 SettingsController
  // 額外的持久化 / 開機啟動服務依賴。
  late ValueNotifier<SettingsModel> settings;

  // 9 個測試共用的建構樣板；讀取當下的 settings/locator/registrar 閉包變數，
  // 故「停用狀態下 start() 不註冊熱鍵」等先替換 settings 的測試不受影響。
  CursorLocatorHotkeyController buildController() {
    return CursorLocatorHotkeyController(
      settings: settings,
      locator: locator,
      registrar: registrar,
    );
  }

  setUp(() {
    channel = const MethodChannel(AppCursorLocatorChannel.channelName);
    locator = CursorLocator(channel: channel);
    playCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          playCalls.add(call);
          return null;
        });
    registrar = _FakeHotKeyRegistrar();
    settings = ValueNotifier<SettingsModel>(SettingsModel.defaults());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('啟用狀態下 start() 註冊熱鍵，鍵值引用 AppCursorLocatorHotkey 常數', () async {
    final CursorLocatorHotkeyController controller = buildController();

    await controller.start();

    expect(registrar.calls, <String>['register']);
    expect(controller.isRegistered, isTrue);
    final HotKey? registered = registrar.lastRegisteredHotKey;
    expect(registered, isNotNull);
    expect(registered!.key, AppCursorLocatorHotkey.physicalKey);
    expect(registered.modifiers, AppCursorLocatorHotkey.modifiers);
    expect(registered.scope, HotKeyScope.system);
  });

  test('停用狀態下 start() 不註冊熱鍵', () async {
    settings = ValueNotifier<SettingsModel>(
      SettingsModel.defaults().copyWith(cursorLocatorEnabled: false),
    );
    final CursorLocatorHotkeyController controller = buildController();

    await controller.start();

    expect(registrar.calls, isEmpty);
    expect(controller.isRegistered, isFalse);
  });

  test('熱鍵觸發呼叫 CursorLocator.play，帶入當下設定值換算後參數（AC1）', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    registrar.lastKeyDownHandler!(registrar.lastRegisteredHotKey!);
    await pumpEventQueue();

    expect(playCalls, hasLength(1));
    expect(playCalls.single.method, AppCursorLocatorChannel.playMethod);
    expect(playCalls.single.arguments, <String, Object?>{
      AppCursorLocatorChannel.durationMsArgKey: 1500,
      AppCursorLocatorChannel.tintArgbArgKey:
          AppCursorLocatorSettings.defaultTint.toARGB32(),
    });
  });

  test('觸發時讀取當下最新設定值，非註冊當下快照', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    settings.value = settings.value.copyWith(
      cursorLocatorEffectDurationSeconds: 2.5,
      cursorLocatorPrimaryColor: const Color(0xFFFF0000),
    );
    registrar.lastKeyDownHandler!(registrar.lastRegisteredHotKey!);
    await pumpEventQueue();

    expect(playCalls, hasLength(1));
    expect(playCalls.single.arguments, <String, Object?>{
      AppCursorLocatorChannel.durationMsArgKey: 2500,
      AppCursorLocatorChannel.tintArgbArgKey: 0xFFFF0000,
    });
  });

  test('設定停用時解除熱鍵註冊，非僅忽略觸發（AC2）', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    settings.value = settings.value.copyWith(cursorLocatorEnabled: false);
    await pumpEventQueue();

    expect(registrar.calls, <String>['register', 'unregister']);
    expect(controller.isRegistered, isFalse);
  });

  test('非啟用開關的設定變更不觸發重複註冊', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    settings.value = settings.value.copyWith(
      cursorLocatorEffectDurationSeconds: 2.0,
    );
    settings.value = settings.value.copyWith(
      cursorLocatorPrimaryColor: const Color(0xFF000000),
    );
    await pumpEventQueue();

    expect(registrar.calls, <String>['register']);
  });

  test(
    'enabled → disabled → enabled 依序 register/unregister/register',
    () async {
      final CursorLocatorHotkeyController controller = buildController();
      await controller.start();

      settings.value = settings.value.copyWith(cursorLocatorEnabled: false);
      await pumpEventQueue();
      settings.value = settings.value.copyWith(cursorLocatorEnabled: true);
      await pumpEventQueue();

      expect(registrar.calls, <String>['register', 'unregister', 'register']);
      expect(controller.isRegistered, isTrue);
    },
  );

  test('熱鍵註冊失敗時定位器維持停用，不拋例外（AC3 / EX-06-01）', () async {
    registrar.throwOnRegister = true;
    final CursorLocatorHotkeyController controller = buildController();

    await expectLater(controller.start(), completes);

    expect(controller.isRegistered, isFalse);
  });

  test('熱鍵解除失敗時維持已註冊狀態，可於下次翻轉重試', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    registrar.throwOnUnregister = true;
    settings.value = settings.value.copyWith(cursorLocatorEnabled: false);
    await pumpEventQueue();

    // 解除失敗：內部狀態維持「已註冊」，不因清空 handle 而失去重試機會。
    expect(registrar.calls, <String>['register', 'unregister']);
    expect(controller.isRegistered, isTrue);

    // 使用者再次翻轉（enabled 目前仍是 false，先切回 true 才能製造一次真正
    // 的翻轉；ValueNotifier 對相等的值不會通知監聽者）。翻回 true 時內部
    // 狀態仍記得「已註冊」，判斷已是目標狀態故不重複 register——這正是
    // retry 機制的體現：不會補一個多餘的 register 呼叫。
    registrar.throwOnUnregister = false;
    settings.value = settings.value.copyWith(cursorLocatorEnabled: true);
    await pumpEventQueue();
    expect(registrar.calls, <String>['register', 'unregister']);

    settings.value = settings.value.copyWith(cursorLocatorEnabled: false);
    await pumpEventQueue();

    expect(registrar.calls, <String>['register', 'unregister', 'unregister']);
    expect(controller.isRegistered, isFalse);
  });

  test('stop() 解除已註冊熱鍵並停止監聽後續啟用開關變化', () async {
    final CursorLocatorHotkeyController controller = buildController();
    await controller.start();

    await controller.stop();
    expect(registrar.calls, <String>['register', 'unregister']);
    expect(controller.isRegistered, isFalse);

    settings.value = settings.value.copyWith(cursorLocatorEnabled: true);
    await pumpEventQueue();

    // stop() 後已移除監聽，enabled 再次翻轉不應觸發新的 register。
    expect(registrar.calls, <String>['register', 'unregister']);
  });
}

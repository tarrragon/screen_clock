// CursorLocatorHotkeyController 單元測試（ticket 1.4.0-W2-005，SPEC-008
// FR-01，UC-06 主成功場景步驟 1 / 替代場景 06c / 例外場景 EX-06-01）。
//
// 驗證熱鍵註冊 / 解除生命週期綁定 SettingsModel.cursorLocatorEnabled 的
// 翻轉（D2 去重）、觸發時讀取當下最新設定值換算播放參數（D3）、熱鍵定義
// 引用 AppCursorLocator 常數無硬編碼（D5）、註冊失敗不外洩例外（EX-06-01）。
//
// 依 test-assertion-design-rules D 規則：全程以 HotKeyRegistrar 替身記錄
// 呼叫序列斷言，不使用 Stopwatch 計時門檻。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/platform/cursor_locator.dart';
import 'package:screen_clock/platform/cursor_locator_hotkey_controller.dart';
import 'package:screen_clock/services/auto_launch_service.dart';
import 'package:screen_clock/services/settings_service.dart';
import 'package:screen_clock/state/settings_controller.dart';

class _FakeHotKeyRegistrar implements HotKeyRegistrar {
  final List<String> calls = <String>[];
  HotKey? lastRegisteredHotKey;
  HotKeyHandler? lastKeyDownHandler;
  bool throwOnRegister = false;

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
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late CursorLocator locator;
  late List<MethodCall> playCalls;
  late _FakeHotKeyRegistrar registrar;
  late SettingsController settings;

  SettingsController buildController(SettingsModel initial) {
    return SettingsController(
      initial: initial,
      service: InMemorySettingsService(),
      autoLaunchService: InMemoryAutoLaunchService(),
    );
  }

  setUp(() {
    channel = const MethodChannel(AppCursorLocator.channelName);
    locator = CursorLocator(channel: channel);
    playCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          playCalls.add(call);
          return null;
        });
    registrar = _FakeHotKeyRegistrar();
    settings = buildController(SettingsModel.defaults());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('啟用狀態下 start() 註冊熱鍵，鍵值引用 AppCursorLocator 常數（D5）', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );

    await controller.start();

    expect(registrar.calls, <String>['register']);
    expect(controller.isRegistered, isTrue);
    final HotKey? registered = registrar.lastRegisteredHotKey;
    expect(registered, isNotNull);
    expect(registered!.key, AppCursorLocator.hotkeyPhysicalKey);
    expect(registered.modifiers, AppCursorLocator.hotkeyModifiers);
    expect(registered.scope, HotKeyScope.system);
  });

  test('停用狀態下 start() 不註冊熱鍵', () async {
    settings = buildController(
      SettingsModel.defaults().copyWith(cursorLocatorEnabled: false),
    );
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );

    await controller.start();

    expect(registrar.calls, isEmpty);
    expect(controller.isRegistered, isFalse);
  });

  test('熱鍵觸發呼叫 CursorLocator.play，帶入當下設定值換算後參數（AC1）', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );
    await controller.start();

    registrar.lastKeyDownHandler!(registrar.lastRegisteredHotKey!);
    await Future<void>.delayed(Duration.zero);

    expect(playCalls, hasLength(1));
    expect(playCalls.single.method, AppCursorLocator.playMethod);
    expect(playCalls.single.arguments, <String, Object?>{
      AppCursorLocator.durationMsArgKey: 1500,
      AppCursorLocator.tintArgbArgKey: AppCursorLocator.defaultTint.toARGB32(),
    });
  });

  test('觸發時讀取當下最新設定值，非註冊當下快照（D3）', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );
    await controller.start();

    settings.update(
      (s) => s.copyWith(
        cursorLocatorEffectDurationSeconds: 2.5,
        cursorLocatorPrimaryColor: const Color(0xFFFF0000),
      ),
    );
    registrar.lastKeyDownHandler!(registrar.lastRegisteredHotKey!);
    await Future<void>.delayed(Duration.zero);

    expect(playCalls, hasLength(1));
    expect(playCalls.single.arguments, <String, Object?>{
      AppCursorLocator.durationMsArgKey: 2500,
      AppCursorLocator.tintArgbArgKey: 0xFFFF0000,
    });
  });

  test('設定停用時解除熱鍵註冊，非僅忽略觸發（AC2 / D2）', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );
    await controller.start();

    settings.update((s) => s.copyWith(cursorLocatorEnabled: false));
    await Future<void>.delayed(Duration.zero);

    expect(registrar.calls, <String>['register', 'unregister']);
    expect(controller.isRegistered, isFalse);
  });

  test('非啟用開關的設定變更不觸發重複註冊（D2 去重）', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );
    await controller.start();

    settings.update((s) => s.copyWith(cursorLocatorEffectDurationSeconds: 2.0));
    settings.update(
      (s) => s.copyWith(cursorLocatorPrimaryColor: const Color(0xFF000000)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(registrar.calls, <String>['register']);
  });

  test(
    'enabled → disabled → enabled 依序 register/unregister/register',
    () async {
      final CursorLocatorHotkeyController controller =
          CursorLocatorHotkeyController(
            settings: settings,
            locator: locator,
            registrar: registrar,
          );
      await controller.start();

      settings.update((s) => s.copyWith(cursorLocatorEnabled: false));
      await Future<void>.delayed(Duration.zero);
      settings.update((s) => s.copyWith(cursorLocatorEnabled: true));
      await Future<void>.delayed(Duration.zero);

      expect(registrar.calls, <String>['register', 'unregister', 'register']);
      expect(controller.isRegistered, isTrue);
    },
  );

  test('熱鍵註冊失敗時定位器維持停用，不拋例外（AC3 / EX-06-01）', () async {
    registrar.throwOnRegister = true;
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );

    await expectLater(controller.start(), completes);

    expect(controller.isRegistered, isFalse);
  });

  test('stop() 解除已註冊熱鍵並停止監聽後續啟用開關變化', () async {
    final CursorLocatorHotkeyController controller =
        CursorLocatorHotkeyController(
          settings: settings,
          locator: locator,
          registrar: registrar,
        );
    await controller.start();

    await controller.stop();
    expect(registrar.calls, <String>['register', 'unregister']);
    expect(controller.isRegistered, isFalse);

    settings.update((s) => s.copyWith(cursorLocatorEnabled: true));
    await Future<void>.delayed(Duration.zero);

    // stop() 後已移除監聽，enabled 再次翻轉不應觸發新的 register。
    expect(registrar.calls, <String>['register', 'unregister']);
  });
}

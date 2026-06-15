// SettingsPanel 綁定管理區 widget 測試（ticket 1.3.0-W4-003，SPEC-007 FR-07/FR-08）。
//
// 涵蓋（本票範圍：權限引導 + 清單顯示/刪除 + 接線；不含新增流程/偵測捕捉）：
// - FR-07 未授權：顯示引導文字 + 「開啟系統授權」按鈕，點擊觸發 requestPermission
// - FR-07 已授權：顯示「已授權」狀態
// - FR-07 權限狀態變化即時反映於面板
// - FR-08 清單渲染既有綁定（按鍵編號 + 動作摘要）
// - FR-08 刪除某筆綁定即時寫入 SettingsModel.bindings 且呼叫 persist
// - 面板開啟時主動呼叫 refreshPermission

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/input_binding_controller.dart';
import 'package:screen_clock/input/mouse_action.dart';
import 'package:screen_clock/input/mouse_binding.dart';
import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/services/auto_launch_service.dart';
import 'package:screen_clock/services/settings_service.dart';
import 'package:screen_clock/state/settings_controller.dart';
import 'package:screen_clock/state/settings_scope.dart';
import 'package:screen_clock/widgets/settings_panel.dart';

/// 可控授權狀態與呼叫記錄的假輸入綁定控制器。
class _FakeInputBindingController extends InputBindingController {
  _FakeInputBindingController({bool granted = false}) {
    permission.value = granted;
  }

  /// 對外可寫的授權 notifier；測試直接操作以模擬狀態變化。
  final ValueNotifier<bool> permission = ValueNotifier<bool>(false);

  int refreshCalls = 0;
  int requestCalls = 0;

  /// 進行中的捕捉回呼，測試以 [emitCaptured] / [emitCancelled] 觸發。
  ValueChanged<int>? _capturedCallback;
  VoidCallback? _cancelledCallback;
  int beginCaptureCalls = 0;
  int cancelCaptureCalls = 0;

  @override
  ValueListenable<bool> get permissionGranted => permission;

  @override
  Future<void> refreshPermission() async {
    refreshCalls++;
  }

  @override
  Future<void> requestPermission() async {
    requestCalls++;
  }

  @override
  Future<void> startButtonCapture({
    required ValueChanged<int> onCaptured,
    VoidCallback? onCancelled,
    Duration timeout = AppDurations.buttonCaptureTimeout,
  }) async {
    beginCaptureCalls++;
    _capturedCallback = onCaptured;
    _cancelledCallback = onCancelled;
  }

  @override
  Future<void> cancelButtonCapture() async {
    cancelCaptureCalls++;
    final VoidCallback? onCancelled = _cancelledCallback;
    _capturedCallback = null;
    _cancelledCallback = null;
    onCancelled?.call();
  }

  /// 模擬原生回報捕捉到側鍵。
  void emitCaptured(int buttonNumber) {
    final ValueChanged<int>? callback = _capturedCallback;
    _capturedCallback = null;
    _cancelledCallback = null;
    callback?.call(buttonNumber);
  }

  /// 模擬逾時/取消（無結果結束捕捉）。
  void emitCancelled() {
    final VoidCallback? callback = _cancelledCallback;
    _capturedCallback = null;
    _cancelledCallback = null;
    callback?.call();
  }
}

/// 記錄 persist 呼叫次數、不觸碰真實儲存的假服務。
class _FakeSettingsService implements SettingsService {
  int saveCalls = 0;

  @override
  Future<SettingsModel> load() async => SettingsModel.defaults();

  @override
  Future<void> save(SettingsModel settings) async {
    saveCalls++;
  }
}

/// 開機啟動切換成功的假服務（避免 persist 觸碰 OS）。
class _FakeAutoLaunchService implements AutoLaunchService {
  bool _enabled = false;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<bool> setEnabled(bool enabled) async {
    _enabled = enabled;
    return enabled;
  }
}

void main() {
  late _FakeInputBindingController inputController;
  late _FakeSettingsService settingsService;
  late SettingsController settingsController;

  SettingsModel modelWith(List<MouseBinding> bindings) {
    return SettingsModel.defaults().copyWith(bindings: bindings);
  }

  Widget panelUnder(SettingsModel model) {
    settingsController = SettingsController(
      initial: model,
      service: settingsService,
      autoLaunchService: _FakeAutoLaunchService(),
    );
    return MaterialApp(
      home: SettingsScope(
        controller: settingsController,
        child: Scaffold(
          body: SettingsPanel(
            availableScreenCount: 1,
            inputBindingController: inputController,
            onClose: () {},
          ),
        ),
      ),
    );
  }

  setUp(() {
    settingsService = _FakeSettingsService();
  });

  group('FR-07 權限引導', () {
    testWidgets('面板開啟時主動刷新權限狀態', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: false);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      expect(inputController.refreshCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('未授權顯示引導文字與開啟系統授權按鈕', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: false);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));

      expect(find.text(AppText.permissionDeniedGuide), findsOneWidget);
      expect(find.text(AppText.permissionGrantButton), findsOneWidget);
    });

    testWidgets('已授權顯示已授權狀態、不顯示引導', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));

      expect(find.text(AppText.permissionGrantedStatus), findsOneWidget);
      expect(find.text(AppText.permissionDeniedGuide), findsNothing);
    });

    testWidgets('點擊開啟系統授權按鈕觸發 requestPermission',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: false);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));

      await tester.ensureVisible(find.text(AppText.permissionGrantButton));
      await tester.tap(find.text(AppText.permissionGrantButton));
      await tester.pump();
      expect(inputController.requestCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('權限狀態變化即時反映於面板', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: false);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      expect(find.text(AppText.permissionDeniedGuide), findsOneWidget);

      inputController.permission.value = true;
      await tester.pump();

      expect(find.text(AppText.permissionGrantedStatus), findsOneWidget);
      expect(find.text(AppText.permissionDeniedGuide), findsNothing);
    });
  });

  group('FR-08 綁定清單顯示/刪除', () {
    final List<MouseBinding> twoBindings = <MouseBinding>[
      const MouseBinding(buttonNumber: 4, action: DragScrollAction()),
      MouseBinding(buttonNumber: 5, action: HotkeyAction(keyCode: 30)),
    ];

    testWidgets('渲染既有綁定的按鍵編號摘要', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(twoBindings)));

      expect(find.textContaining('4'), findsWidgets);
      expect(find.textContaining('5'), findsWidgets);
    });

    testWidgets('刪除一筆綁定後 model 不含該筆且呼叫 persist',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(twoBindings)));

      final Finder deleteButtons =
          find.byKey(const ValueKey<String>('delete-binding-4'));
      expect(deleteButtons, findsOneWidget);

      await tester.ensureVisible(deleteButtons);
      await tester.tap(deleteButtons);
      await tester.pump();

      final List<int> remaining = settingsController.value.bindings
          .map((MouseBinding b) => b.buttonNumber)
          .toList();
      expect(remaining, isNot(contains(4)));
      expect(remaining, contains(5));
      expect(settingsService.saveCalls, greaterThanOrEqualTo(1));
    });
  });

  group('FR-06/FR-08 新增綁定流程與偵測捕捉（W4-004）', () {
    Future<void> startAddFlow(WidgetTester tester) async {
      final Finder addButton = find.text(AppText.bindingAddButton);
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();
    }

    testWidgets('面板顯示新增綁定按鈕', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));

      expect(find.text(AppText.bindingAddButton), findsOneWidget);
    });

    testWidgets('點新增進入捕捉：呼叫 startButtonCapture 並顯示捕捉提示',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));

      await startAddFlow(tester);

      expect(inputController.beginCaptureCalls, greaterThanOrEqualTo(1));
      expect(find.text(AppText.bindingCapturePrompt), findsOneWidget);
    });

    testWidgets('捕捉到側鍵後顯示動作型別選擇', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);

      inputController.emitCaptured(6);
      await tester.pump();

      expect(find.text(AppText.bindingActionDragScroll), findsWidgets);
      expect(find.text(AppText.bindingActionHotkey), findsWidgets);
    });

    testWidgets('逾時/取消捕捉退出 capturing 視覺、不殘留提示',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);

      expect(find.text(AppText.bindingCapturePrompt), findsOneWidget);

      inputController.emitCancelled();
      await tester.pump();

      expect(find.text(AppText.bindingCapturePrompt), findsNothing);
    });

    testWidgets('取消按鈕呼叫 cancelButtonCapture', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);

      final Finder cancelButton =
          find.byKey(const ValueKey<String>('add-flow-cancel'));
      await tester.ensureVisible(cancelButton);
      await tester.tap(cancelButton);
      await tester.pump();

      expect(inputController.cancelCaptureCalls, greaterThanOrEqualTo(1));
      expect(find.text(AppText.bindingCapturePrompt), findsNothing);
    });

    testWidgets('DragScroll：確認後寫入綁定且呼叫 persist',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);
      inputController.emitCaptured(6);
      await tester.pump();

      // 預設動作型別為 DragScroll，直接確認。
      final Finder confirm =
          find.byKey(const ValueKey<String>('add-flow-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();

      final List<MouseBinding> bindings = settingsController.value.bindings;
      expect(bindings, hasLength(1));
      expect(bindings.single.buttonNumber, 6);
      expect(bindings.single.action, isA<DragScrollAction>());
      expect(settingsService.saveCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('DragScroll：可切換方向為反向並寫入', (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);
      inputController.emitCaptured(6);
      await tester.pump();

      final Finder invertedToggle =
          find.byKey(const ValueKey<String>('add-flow-direction-inverted'));
      await tester.ensureVisible(invertedToggle);
      await tester.tap(invertedToggle);
      await tester.pump();

      final Finder confirm =
          find.byKey(const ValueKey<String>('add-flow-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();

      final MouseAction action =
          settingsController.value.bindings.single.action;
      expect(action, isA<DragScrollAction>());
      expect((action as DragScrollAction).direction,
          ScrollDirection.inverted);
    });

    testWidgets('Hotkey：選型別後擷取鍵盤組合並寫入 keyCode+modifiers',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(const <MouseBinding>[])));
      await startAddFlow(tester);
      inputController.emitCaptured(6);
      await tester.pump();

      // 切換到 Hotkey 型別。
      final Finder hotkeyType =
          find.byKey(const ValueKey<String>('add-flow-type-hotkey'));
      await tester.ensureVisible(hotkeyType);
      await tester.tap(hotkeyType);
      await tester.pump();

      // 模擬鍵盤按下 Cmd + 4（送 keyDown 事件）。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
      await tester.pump();

      final Finder confirm =
          find.byKey(const ValueKey<String>('add-flow-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);

      final MouseAction action =
          settingsController.value.bindings.single.action;
      expect(action, isA<HotkeyAction>());
      final HotkeyAction hotkey = action as HotkeyAction;
      expect(hotkey.keyCode, isNot(0));
      expect(hotkey.modifiers, isNotEmpty);
    });

    testWidgets('重複 buttonNumber：新綁定覆蓋同編號舊綁定',
        (WidgetTester tester) async {
      inputController = _FakeInputBindingController(granted: true);
      await tester.pumpWidget(panelUnder(modelWith(<MouseBinding>[
        const MouseBinding(buttonNumber: 6, action: DragScrollAction()),
      ])));
      await startAddFlow(tester);
      inputController.emitCaptured(6);
      await tester.pump();

      final Finder hotkeyType =
          find.byKey(const ValueKey<String>('add-flow-type-hotkey'));
      await tester.ensureVisible(hotkeyType);
      await tester.tap(hotkeyType);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      final Finder confirm =
          find.byKey(const ValueKey<String>('add-flow-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

      final List<MouseBinding> bindings = settingsController.value.bindings;
      final Iterable<MouseBinding> button6 =
          bindings.where((MouseBinding b) => b.buttonNumber == 6);
      expect(button6, hasLength(1));
      expect(button6.single.action, isA<HotkeyAction>());
    });
  });
}

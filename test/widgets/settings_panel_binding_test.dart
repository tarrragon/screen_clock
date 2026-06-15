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
}

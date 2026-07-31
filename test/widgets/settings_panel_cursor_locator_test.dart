// SettingsPanel 滑鼠定位器區塊 widget 測試（ticket 1.4.0-W3-002，SPEC-008 FR-06）。
//
// 涵蓋：
// - 面板顯示啟用開關、特效時長滑桿、主色調選擇器三個控制項
// - 三者變更後寫入 SettingsModel 對應欄位
// - 特效時長滑桿 min/max 對應 AppCursorLocator 值域常數
// - 「儲存」持久化整個模型（含三個新欄位）
// - 既有設定面板區塊（滑鼠綁定）無回歸

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';
import 'package:screen_clock/input/input_binding_controller.dart';
import 'package:screen_clock/models/settings_model.dart';
import 'package:screen_clock/services/auto_launch_service.dart';
import 'package:screen_clock/services/settings_service.dart';
import 'package:screen_clock/state/settings_controller.dart';
import 'package:screen_clock/state/settings_scope.dart';
import 'package:screen_clock/widgets/settings_panel.dart';

/// 不觸碰真實 method channel 的假輸入綁定控制器（本檔只需面板可正常
/// initState，不測綁定行為）。
class _NoopInputBindingController extends InputBindingController {
  @override
  Future<void> refreshPermission() async {}
}

/// 記錄 persist 呼叫次數、不觸碰真實儲存的假服務。
class _FakeSettingsService implements SettingsService {
  int saveCalls = 0;
  SettingsModel? lastSaved;

  @override
  Future<SettingsModel> load() async => SettingsModel.defaults();

  @override
  Future<void> save(SettingsModel settings) async {
    saveCalls++;
    lastSaved = settings;
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
  late _FakeSettingsService settingsService;
  late SettingsController settingsController;

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
            inputBindingController: _NoopInputBindingController(),
            onClose: () {},
          ),
        ),
      ),
    );
  }

  setUp(() {
    settingsService = _FakeSettingsService();
  });

  group('FR-06 滑鼠定位器控制項顯示', () {
    testWidgets('面板顯示啟用開關、特效時長滑桿、主色調標籤', (WidgetTester tester) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));

      expect(find.text(AppText.cursorLocatorSectionTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('cursor-locator-enabled-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cursor-locator-duration-slider')),
        findsOneWidget,
      );
      expect(find.text(AppText.cursorLocatorColorLabel), findsOneWidget);
    });

    testWidgets('啟用開關反映 model 初始值', (WidgetTester tester) async {
      final SettingsModel model = SettingsModel.defaults().copyWith(
        cursorLocatorEnabled: false,
      );
      await tester.pumpWidget(panelUnder(model));

      final Switch toggle = tester.widget<Switch>(
        find.byKey(const ValueKey<String>('cursor-locator-enabled-switch')),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('特效時長滑桿 min/max 對應 AppCursorLocator 值域常數', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));

      final Slider slider = tester.widget<Slider>(
        find.byKey(const ValueKey<String>('cursor-locator-duration-slider')),
      );
      expect(slider.min, AppCursorLocator.minDurationSeconds);
      expect(slider.max, AppCursorLocator.maxDurationSeconds);
      expect(slider.value, AppCursorLocator.defaultDurationSeconds);
    });
  });

  group('FR-06 變更寫入 SettingsModel', () {
    testWidgets('切換啟用開關後 model.cursorLocatorEnabled 反轉', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));
      expect(settingsController.value.cursorLocatorEnabled, isTrue);

      final Finder toggle = find.byKey(
        const ValueKey<String>('cursor-locator-enabled-switch'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();

      expect(settingsController.value.cursorLocatorEnabled, isFalse);
    });

    testWidgets('拖動特效時長滑桿後 model 反映新值（於值域內）', (WidgetTester tester) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));

      final Finder sliderFinder = find.byKey(
        const ValueKey<String>('cursor-locator-duration-slider'),
      );
      await tester.ensureVisible(sliderFinder);
      await tester.drag(sliderFinder, const Offset(-200, 0));
      await tester.pump();

      final double updated =
          settingsController.value.cursorLocatorEffectDurationSeconds;
      expect(
        updated,
        greaterThanOrEqualTo(AppCursorLocator.minDurationSeconds),
      );
      expect(updated, lessThanOrEqualTo(AppCursorLocator.maxDurationSeconds));
      expect(updated, isNot(AppCursorLocator.defaultDurationSeconds));
    });

    testWidgets('選取色盤色票後 model.cursorLocatorPrimaryColor 更新', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));

      // 主色調色盤位於區塊內第一組 _ColorSwatch 清單；找到色盤標籤所在列
      // 後，直接點擊第一個色票（白色，非目前選中的系統藍）。
      final Finder colorLabel = find.text(AppText.cursorLocatorColorLabel);
      expect(colorLabel, findsOneWidget);

      final Finder swatches = find.descendant(
        of: find.ancestor(of: colorLabel, matching: find.byType(Column)).first,
        matching: find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == '_ColorSwatch',
        ),
      );
      expect(swatches, findsWidgets);

      final Color before = settingsController.value.cursorLocatorPrimaryColor;
      await tester.ensureVisible(swatches.first);
      await tester.tap(swatches.first);
      await tester.pump();

      expect(settingsController.value.cursorLocatorPrimaryColor, isNot(before));
    });
  });

  group('FR-06 持久化', () {
    testWidgets('點擊儲存呼叫 persist 且寫入三個新欄位', (WidgetTester tester) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));

      final Finder toggle = find.byKey(
        const ValueKey<String>('cursor-locator-enabled-switch'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();

      await tester.ensureVisible(find.text('儲存'));
      await tester.tap(find.text('儲存'));
      await tester.pump();

      expect(settingsService.saveCalls, greaterThanOrEqualTo(1));
      expect(settingsService.lastSaved?.cursorLocatorEnabled, isFalse);
    });
  });

  group('無回歸：既有設定面板區塊', () {
    testWidgets('滑鼠綁定區塊標題仍存在', (WidgetTester tester) async {
      await tester.pumpWidget(panelUnder(SettingsModel.defaults()));
      expect(find.text(AppText.bindingSectionTitle), findsOneWidget);
    });
  });
}

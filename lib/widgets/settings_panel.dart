import 'package:flutter/material.dart';

import '../input/input_binding_controller.dart';
import '../models/settings_model.dart';
import '../state/settings_controller.dart';
import '../state/settings_scope.dart';
import 'settings/settings_binding_section.dart';
import 'settings/settings_cursor_locator_section.dart';
import 'settings/settings_screen_section.dart';
import 'settings/settings_style_section.dart';
import 'settings/settings_system_section.dart';

/// 設定面板（SPEC-005 FR-03 / FR-04 + SPEC-007 FR-07 / FR-08）。
///
/// 九個樣式欄位對應 [SettingsModel]；變更走 [SettingsController.update]
/// → InheritedNotifier rebuild → CenterClock 即時預覽。
///
/// 綁定管理區（FR-07/FR-08）：監聽 [InputBindingController.permissionGranted]
/// 顯示授權狀態與引導；列出現有綁定並可即時刪除。樣式欄位走 Save/Cancel
/// 暫存模型，綁定刪除走即時持久化（FR-08）與 Save/Cancel 解耦。
///
/// 「儲存」呼叫 [SettingsController.persist] 後關閉；
/// 「取消」呼叫 [SettingsController.resetToStartup] 後關閉。
///
/// 依設定 domain 邊界拆分為獨立區塊 widget（1.4.0-W3-003）：樣式
/// [SettingsStyleSection]、螢幕 [SettingsScreenSection]、系統整合
/// [SettingsSystemSection]、滑鼠綁定 [SettingsBindingSection]、滑鼠定位器
/// [SettingsCursorLocatorSection]。本檔僅保留組裝骨架與 Save/Cancel 動作列。
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.availableScreenCount,
    required this.inputBindingController,
    required this.onClose,
  });

  /// 目前可選擇的螢幕數，用於 dropdown 上限（SPEC-005 FR-03 + SPEC-003 FR-01）。
  final int availableScreenCount;

  /// 滑鼠綁定控制器，供權限引導（FR-07）與綁定清單刪除（FR-08）使用。
  final InputBindingController inputBindingController;

  /// 關閉面板的回呼。
  ///
  /// 面板是 Stack overlay（非 Navigator route），不能用 `Navigator.pop` 關閉；
  /// 由上層 `_PanelHost` 注入，內部設 `_panelOpen = false` 並還原 click-through。
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  @override
  void initState() {
    super.initState();
    // SPEC-007 FR-07：面板開啟主動刷新授權狀態（空綁定時 notifier 可能仍為 false）。
    widget.inputBindingController.refreshPermission();
  }

  int get availableScreenCount => widget.availableScreenCount;

  VoidCallback get onClose => widget.onClose;

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = SettingsScope.controllerOf(context);
    final SettingsModel current = SettingsScope.of(context);

    return Center(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16), // magic-exempt: 沿用既有面板圓角慣例，純結構搬移
        child: SizedBox(
          width: 480, // magic-exempt: 沿用既有面板寬度慣例，純結構搬移
          // 綁定區使面板變高，外層 app 視窗高度有限，包可滾動容器避免 overflow。
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560), // magic-exempt: 沿用既有面板高度上限，純結構搬移
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24), // magic-exempt: 沿用既有面板 padding 慣例，純結構搬移
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '設定', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16), // magic-exempt: 沿用既有面板區塊間距慣例，純結構搬移
                    SettingsStyleSection(controller: controller, current: current),
                    const SizedBox(height: 12), // magic-exempt: 沿用既有面板區塊間距慣例，純結構搬移
                    SettingsScreenSection(
                      availableScreenCount: availableScreenCount,
                      controller: controller,
                      current: current,
                    ),
                    const SizedBox(height: 12), // magic-exempt: 沿用既有面板區塊間距慣例，純結構搬移
                    SettingsSystemSection(
                      controller: controller,
                      current: current,
                    ),
                    const SizedBox(height: 24), // magic-exempt: 沿用既有面板區塊間距慣例，純結構搬移
                    SettingsBindingSection(
                      controller: controller,
                      current: current,
                      inputBindingController: widget.inputBindingController,
                    ),
                    const SizedBox(height: 24), // magic-exempt: 既有區塊間距沿用值，非本次新增
                    SettingsCursorLocatorSection(
                      controller: controller,
                      current: current,
                    ),
                    const SizedBox(height: 24), // magic-exempt: 既有區塊間距沿用值，非本次新增
                    _buildActions(context, controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, SettingsController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: () {
            controller.resetToStartup();
            onClose();
          },
          child: const Text('取消'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        const SizedBox(width: 8), // magic-exempt: 沿用既有面板欄位間距慣例，純結構搬移
        FilledButton(
          onPressed: () async {
            await controller.persist();
            onClose();
          },
          child: const Text('儲存'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
      ],
    );
  }
}

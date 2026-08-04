import 'package:flutter/material.dart';

import '../../app_constants.dart';
import '../../input/input_binding_controller.dart';
import '../../input/mouse_action.dart';
import '../../input/mouse_binding.dart';
import '../../models/settings_model.dart';
import '../../state/settings_controller.dart';
import 'settings_add_binding_flow.dart';

/// 滑鼠綁定管理區（SPEC-007 FR-07 權限引導 + FR-08 清單/刪除）。純結構搬移自
/// settings_panel.dart（1.4.0-W3-003），行為不變；`_addingBinding` 狀態改由本
/// widget 自身持有（原屬 `_SettingsPanelState`），為區塊拆分後的自然邊界。
/// 新增綁定流程（`_AddBindingFlow` 等）另拆至 settings_add_binding_flow.dart
/// 以控制單檔行數（拆分後仍逾 300 行閾值）。
///
/// 檔內數值字面（fontSize / padding / spacing 等）皆沿用原
/// settings_panel.dart 既有值，純結構搬移不變更視覺表現，故標 exempt。
class SettingsBindingSection extends StatefulWidget {
  const SettingsBindingSection({
    super.key,
    required this.controller,
    required this.current,
    required this.inputBindingController,
  });

  final SettingsController controller;
  final SettingsModel current;
  final InputBindingController inputBindingController;

  @override
  State<SettingsBindingSection> createState() =>
      _SettingsBindingSectionState();
}

class _SettingsBindingSectionState extends State<SettingsBindingSection> {
  /// 是否處於新增綁定流程（true 時以 [AddBindingFlow] 取代「新增綁定」按鈕）。
  bool _addingBinding = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          AppText.bindingSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
        _buildPermissionRow(),
        const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
        _buildBindingList(widget.controller, widget.current),
        const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
        _buildAddBinding(widget.controller),
      ],
    );
  }

  /// FR-06/FR-08：新增綁定流程。未在新增時顯示「新增綁定」按鈕；
  /// 點擊後 inline 展開 [AddBindingFlow]（不依賴 Navigator，與面板 overlay 一致）。
  /// 完成確認後 update + persist 即時寫入並下傳原生；取消則丟棄。
  Widget _buildAddBinding(SettingsController controller) {
    if (!_addingBinding) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('add-binding-button'),
          onPressed: () => setState(() => _addingBinding = true),
          icon: const Icon(Icons.add),
          label: const Text(AppText.bindingAddButton),
        ),
      );
    }
    return AddBindingFlow(
      inputBindingController: widget.inputBindingController,
      onCancel: () => setState(() => _addingBinding = false),
      onConfirm: (MouseBinding binding) async {
        await _addBinding(controller, binding);
        if (mounted) setState(() => _addingBinding = false);
      },
    );
  }

  /// 新增綁定：附加新綁定後即時持久化。copyWith 內 dedupeBindingsByButton
  /// 會以新綁定覆蓋同 buttonNumber 舊綁定（SPEC-007 FR-01）。
  Future<void> _addBinding(
    SettingsController controller,
    MouseBinding binding,
  ) async {
    controller.update(
      (SettingsModel s) =>
          s.copyWith(bindings: <MouseBinding>[...s.bindings, binding]),
    );
    await controller.persist();
  }

  /// FR-07：監聽授權狀態，已授權顯示狀態文字，未授權顯示引導 + 開啟系統授權按鈕。
  Widget _buildPermissionRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.inputBindingController.permissionGranted,
      builder: (BuildContext context, bool granted, Widget? _) {
        if (granted) {
          return Text(
            AppText.permissionGrantedStatus,
            style: const TextStyle(fontSize: 13), // magic-exempt: 沿用既有面板字級慣例
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              AppText.permissionDeniedGuide,
              style: TextStyle(fontSize: 12), // magic-exempt: 沿用既有面板字級慣例
            ),
            const SizedBox(height: 4), // magic-exempt: 沿用既有面板區塊間距慣例
            OutlinedButton(
              onPressed: widget.inputBindingController.requestPermission,
              child: const Text(AppText.permissionGrantButton),
            ),
          ],
        );
      },
    );
  }

  /// FR-08：列出現有綁定，每筆顯示按鍵編號 + 動作摘要與刪除鈕。
  Widget _buildBindingList(
    SettingsController controller,
    SettingsModel current,
  ) {
    if (current.bindings.isEmpty) {
      return const Text(
        AppText.bindingListEmpty,
        style: TextStyle(fontSize: 12), // magic-exempt: 沿用既有面板字級慣例
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final MouseBinding binding in current.bindings)
          _buildBindingRow(controller, binding),
      ],
    );
  }

  Widget _buildBindingRow(SettingsController controller, MouseBinding binding) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${AppText.bindingButtonPrefix} ${binding.buttonNumber}'
            '・${_actionSummary(binding.action)}',
            style: const TextStyle(fontSize: 13), // magic-exempt: 沿用既有面板字級慣例
          ),
        ),
        IconButton(
          key: ValueKey<String>('delete-binding-${binding.buttonNumber}'),
          tooltip: AppText.bindingDeleteTooltip,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteBinding(controller, binding.buttonNumber),
        ),
      ],
    );
  }

  /// FR-08：刪除指定按鍵綁定後即時持久化（與 Save/Cancel 暫存模型解耦）。
  /// persist 後 main.dart 的 _onSettingsChanged 會自動 syncBindings 下傳原生。
  Future<void> _deleteBinding(
    SettingsController controller,
    int buttonNumber,
  ) async {
    controller.update(
      (SettingsModel s) => s.copyWith(
        bindings: s.bindings
            .where((MouseBinding b) => b.buttonNumber != buttonNumber)
            .toList(),
      ),
    );
    await controller.persist();
  }

  /// 動作摘要文案（集中字面於 AppText，禁硬編中文於 widget）。
  String _actionSummary(MouseAction action) {
    return switch (action) {
      DragScrollAction(
        :final ScrollDirection direction,
        :final double sensitivity,
      ) =>
        '${AppText.bindingActionDragScroll}'
            '・${_directionLabel(direction)}'
            '・${AppText.bindingSensitivityPrefix} '
            '${sensitivity.toStringAsFixed(1)}',
      HotkeyAction(:final int keyCode, :final List<int> modifiers) =>
        '${AppText.bindingActionHotkey}'
            '・${AppText.bindingKeyCodePrefix} $keyCode'
            '・${AppText.bindingModifierPrefix} ${modifiers.length}',
    };
  }

  String _directionLabel(ScrollDirection direction) {
    return switch (direction) {
      ScrollDirection.natural => AppText.bindingDirectionNatural,
      ScrollDirection.inverted => AppText.bindingDirectionInverted,
    };
  }
}

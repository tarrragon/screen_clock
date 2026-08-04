import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_constants.dart';
import '../../input/input_binding_controller.dart';
import '../../input/mouse_action.dart';
import '../../input/mouse_binding.dart';
import 'settings_add_binding_flow_fields.dart';

/// 新增綁定流程的本地階段（SPEC-007 FR-06/FR-08）。
enum AddBindingStage { capturing, configuring }

/// 新增綁定動作型別（流程內部選擇用，對應 [MouseActionType]）。
enum AddBindingActionType { dragScroll, hotkey }

/// 新增綁定的 inline 流程子 widget（SPEC-007 FR-06 偵測捕捉 + FR-08 新增）。
/// 純結構搬移自 settings_panel.dart 的 `_AddBindingFlow`（1.4.0-W3-003），
/// 拆自 settings_binding_section.dart 以控制單檔行數（W3-003 acceptance）。
///
/// 階段：(1) capturing 偵測按鍵——透過 [InputBindingController.startButtonCapture]
/// 等待側鍵，逾時/取消由 onCancelled 退出；(2) configuring 設定動作型別與參數
/// （DragScroll 方向/靈敏度，或 Hotkey 鍵盤組合），確認後回呼 [onConfirm]。
///
/// 採獨立 stateful widget 隔離流程狀態（避免膨脹上層區塊 state，
/// 對齊 W4-003 Phase 4 抽子 widget 提示）。
class AddBindingFlow extends StatefulWidget {
  const AddBindingFlow({
    super.key,
    required this.inputBindingController,
    required this.onCancel,
    required this.onConfirm,
  });

  final InputBindingController inputBindingController;
  final VoidCallback onCancel;
  final ValueChanged<MouseBinding> onConfirm;

  @override
  State<AddBindingFlow> createState() => _AddBindingFlowState();
}

class _AddBindingFlowState extends State<AddBindingFlow> {
  AddBindingStage _stage = AddBindingStage.capturing;
  int? _capturedButton;

  AddBindingActionType _actionType = AddBindingActionType.dragScroll;

  ScrollDirection _direction = ScrollDirection.natural;
  double _sensitivity = AppInputBinding.defaultDragScrollSensitivity;

  /// Hotkey 擷取結果：實體鍵碼（W5 對齊原生 virtual keycode，本票僅存）。
  int? _hotkeyCode;
  List<int> _hotkeyModifiers = const <int>[];

  final FocusNode _hotkeyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _beginCapture();
  }

  @override
  void dispose() {
    _hotkeyFocus.dispose();
    super.dispose();
  }

  /// 進入偵測捕捉：請 controller 等待側鍵，捕捉到→進設定階段，逾時/取消→退出流程。
  void _beginCapture() {
    widget.inputBindingController.startButtonCapture(
      onCaptured: (int buttonNumber) {
        if (!mounted) return;
        setState(() {
          _capturedButton = buttonNumber;
          _stage = AddBindingStage.configuring;
        });
      },
      onCancelled: () {
        // 逾時/取消（無結果結束）：退出整個新增流程，不卡在捕捉視覺（FR-06）。
        if (!mounted) return;
        widget.onCancel();
      },
    );
  }

  void _cancelFlow() {
    widget.inputBindingController.cancelButtonCapture();
    widget.onCancel();
  }

  /// 擷取鍵盤組合：記錄 keyDown 的實體鍵碼與當下修飾鍵集合（HardwareKeyboard）。
  KeyEventResult _onHotkeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final int code = event.physicalKey.usbHidUsage;
    final List<int> modifiers =
        HardwareKeyboard.instance.physicalKeysPressed
            .map((PhysicalKeyboardKey k) => k.usbHidUsage)
            .where((int usage) => usage != code)
            .toList()
          ..sort();
    setState(() {
      _hotkeyCode = code;
      _hotkeyModifiers = modifiers;
    });
    return KeyEventResult.handled;
  }

  /// 是否允許確認綁定：Hotkey 動作必須先擷取到按鍵；DragScroll 一律允許。
  bool get _canConfirm =>
      _actionType != AddBindingActionType.hotkey || _hotkeyCode != null;

  MouseBinding _buildBinding() {
    final MouseAction action = switch (_actionType) {
      AddBindingActionType.dragScroll => DragScrollAction(
        direction: _direction,
        sensitivity: _sensitivity,
      ),
      AddBindingActionType.hotkey => HotkeyAction(
        keyCode: _hotkeyCode ?? 0,
        modifiers: _hotkeyModifiers,
      ),
    };
    return MouseBinding(buttonNumber: _capturedButton ?? 0, action: action);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12), // magic-exempt: 沿用既有面板 padding 慣例
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26), // color-exempt: 沿用既有邊框色字面值
        borderRadius: BorderRadius.circular(8), // magic-exempt: 沿用既有面板圓角慣例
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _stage == AddBindingStage.capturing
            ? _buildCapturing()
            : _buildConfiguring(),
      ),
    );
  }

  List<Widget> _buildCapturing() {
    return <Widget>[
      const Text(
        AppText.bindingCapturePrompt,
        style: TextStyle(fontSize: 13), // magic-exempt: 沿用既有面板字級慣例
      ),
      const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey<String>('add-flow-cancel'),
          onPressed: _cancelFlow,
          child: const Text(AppText.bindingFlowCancel),
        ),
      ),
    ];
  }

  List<Widget> _buildConfiguring() {
    return <Widget>[
      Text(
        '${AppText.bindingCapturedPrefix} $_capturedButton',
        style: const TextStyle(fontSize: 13), // magic-exempt: 沿用既有面板字級慣例
      ),
      const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
      const Text(
        AppText.bindingActionTypeLabel,
        style: TextStyle(fontSize: 12), // magic-exempt: 沿用既有面板字級慣例
      ),
      const SizedBox(height: 4), // magic-exempt: 沿用既有面板區塊間距慣例
      AddBindingActionTypeSelector(
        selected: _actionType,
        onSelected: (AddBindingActionType t) =>
            setState(() => _actionType = t),
      ),
      const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
      if (_actionType == AddBindingActionType.dragScroll)
        AddBindingDragScrollFields(
          direction: _direction,
          sensitivity: _sensitivity,
          onDirectionChanged: (ScrollDirection d) =>
              setState(() => _direction = d),
          onSensitivityChanged: (double v) =>
              setState(() => _sensitivity = v),
        )
      else
        AddBindingHotkeyFields(
          focusNode: _hotkeyFocus,
          onKeyEvent: _onHotkeyEvent,
          capturedLabel: _hotkeyCode == null
              ? AppText.bindingHotkeyNotCaptured
              : '${AppText.bindingKeyCodePrefix} $_hotkeyCode'
                    '・${AppText.bindingModifierPrefix} ${_hotkeyModifiers.length}',
        ),
      const SizedBox(height: 12), // magic-exempt: 沿用既有面板區塊間距慣例
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            key: const ValueKey<String>('add-flow-cancel'),
            onPressed: _cancelFlow,
            child: const Text(AppText.bindingFlowCancel),
          ),
          const SizedBox(width: 8), // magic-exempt: 沿用既有面板欄位間距慣例
          FilledButton(
            key: const ValueKey<String>('add-flow-confirm'),
            // Hotkey 動作未擷取按鍵（keyCode 為 null）時禁用，避免建立 keyCode=0
            // 的無效綁定；DragScroll 或已擷取按鍵時啟用。
            onPressed: _canConfirm
                ? () => widget.onConfirm(_buildBinding())
                : null,
            child: const Text(AppText.bindingFlowConfirm),
          ),
        ],
      ),
    ];
  }

}

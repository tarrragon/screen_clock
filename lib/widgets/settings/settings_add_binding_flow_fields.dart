import 'package:flutter/material.dart';

import '../../app_constants.dart';
import '../../input/mouse_action.dart';
import 'settings_add_binding_flow.dart';

/// [AddBindingFlow] 設定階段的欄位子元件（動作型別選擇 / DragScroll 參數 /
/// Hotkey 擷取欄）。純結構搬移自 settings_panel.dart 的 `_AddBindingFlowState`
/// 私有方法（1.4.0-W3-003），拆出以控制 settings_add_binding_flow.dart 行數。
class AddBindingActionTypeSelector extends StatelessWidget {
  const AddBindingActionTypeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AddBindingActionType selected;
  final ValueChanged<AddBindingActionType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        ChoiceChip(
          key: const ValueKey<String>('add-flow-type-dragScroll'),
          label: const Text(AppText.bindingActionDragScroll),
          selected: selected == AddBindingActionType.dragScroll,
          onSelected: (_) => onSelected(AddBindingActionType.dragScroll),
        ),
        const SizedBox(width: 8), // magic-exempt: 沿用既有面板欄位間距慣例
        ChoiceChip(
          key: const ValueKey<String>('add-flow-type-hotkey'),
          label: const Text(AppText.bindingActionHotkey),
          selected: selected == AddBindingActionType.hotkey,
          onSelected: (_) => onSelected(AddBindingActionType.hotkey),
        ),
      ],
    );
  }
}

/// DragScroll 動作參數欄（方向選擇 + 靈敏度滑桿）。
class AddBindingDragScrollFields extends StatelessWidget {
  const AddBindingDragScrollFields({
    super.key,
    required this.direction,
    required this.sensitivity,
    required this.onDirectionChanged,
    required this.onSensitivityChanged,
  });

  final ScrollDirection direction;
  final double sensitivity;
  final ValueChanged<ScrollDirection> onDirectionChanged;
  final ValueChanged<double> onSensitivityChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ChoiceChip(
              key: const ValueKey<String>('add-flow-direction-natural'),
              label: const Text(AppText.bindingDirectionNatural),
              selected: direction == ScrollDirection.natural,
              onSelected: (_) => onDirectionChanged(ScrollDirection.natural),
            ),
            const SizedBox(width: 8), // magic-exempt: 沿用既有面板欄位間距慣例
            ChoiceChip(
              key: const ValueKey<String>('add-flow-direction-inverted'),
              label: const Text(AppText.bindingDirectionInverted),
              selected: direction == ScrollDirection.inverted,
              onSelected: (_) => onDirectionChanged(ScrollDirection.inverted),
            ),
          ],
        ),
        const SizedBox(height: 8), // magic-exempt: 沿用既有面板區塊間距慣例
        Row(
          children: <Widget>[
            Text(
              AppText.bindingSensitivityPrefix,
              style: const TextStyle(fontSize: 12), // magic-exempt: 沿用既有面板字級慣例
            ),
            Expanded(
              child: Slider(
                min: 0.1, // magic-exempt: 沿用既有滑桿值域慣例
                max: 5, // magic-exempt: 沿用既有滑桿值域慣例
                divisions: 49, // magic-exempt: 沿用既有滑桿精度慣例
                value: sensitivity,
                label: sensitivity.toStringAsFixed(1),
                onChanged: onSensitivityChanged,
              ),
            ),
            SizedBox(
              width: 32, // magic-exempt: 沿用既有面板數值顯示欄寬慣例
              child: Text(sensitivity.toStringAsFixed(1)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hotkey 動作參數欄（鍵盤組合擷取焦點區）。
class AddBindingHotkeyFields extends StatelessWidget {
  const AddBindingHotkeyFields({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.capturedLabel,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final String capturedLabel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: onKeyEvent,
      child: Container(
        padding: const EdgeInsets.all(8), // magic-exempt: 沿用既有面板 padding 慣例
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26), // color-exempt: 沿用既有邊框色字面值
          borderRadius: BorderRadius.circular(6), // magic-exempt: 沿用既有面板圓角慣例
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              AppText.bindingHotkeyCapturePrompt,
              style: TextStyle(fontSize: 12), // magic-exempt: 沿用既有面板字級慣例
            ),
            const SizedBox(height: 4), // magic-exempt: 沿用既有面板區塊間距慣例
            Text(
              capturedLabel,
              style: const TextStyle(fontSize: 13), // magic-exempt: 沿用既有面板字級慣例
            ),
          ],
        ),
      ),
    );
  }
}

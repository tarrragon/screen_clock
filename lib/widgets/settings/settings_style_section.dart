import 'package:flutter/material.dart';

import '../../models/settings_model.dart';
import '../../state/settings_controller.dart';
import 'settings_color_picker.dart';

/// 樣式設定區（SPEC-005 FR-03/FR-04）：字型大小、描邊寬度、填色、描邊色、
/// 時間格式。純結構搬移自 settings_panel.dart（1.4.0-W3-003），行為不變。
class SettingsStyleSection extends StatelessWidget {
  const SettingsStyleSection({
    super.key,
    required this.controller,
    required this.current,
  });

  final SettingsController controller;
  final SettingsModel current;

  static const List<String> timeFormats = <String>['HH:mm:ss', 'HH:mm'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildFontSize(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        _buildStrokeWidth(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        SettingsColorPicker(
          label: '填色', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
          current: current.fillColor,
          onPick: (Color c) =>
              controller.update((SettingsModel s) => s.copyWith(fillColor: c)),
        ),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        SettingsColorPicker(
          label: '描邊色', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
          current: current.strokeColor,
          onPick: (Color c) => controller.update(
            (SettingsModel s) => s.copyWith(strokeColor: c),
          ),
        ),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        _buildTimeFormat(controller, current),
      ],
    );
  }

  Widget _buildFontSize(SettingsController controller, SettingsModel current) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('字型大小'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        Expanded(
          child: Slider(
            min: 40,
            max: 240,
            value: current.fontSize,
            label: current.fontSize.round().toString(),
            divisions: 200,
            onChanged: (double v) =>
                controller.update((SettingsModel s) => s.copyWith(fontSize: v)),
          ),
        ),
        SizedBox(
          width: 40, // magic-exempt: 沿用既有面板數值顯示欄寬慣例
          child: Text(current.fontSize.round().toString()),
        ),
      ],
    );
  }

  Widget _buildStrokeWidth(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('描邊寬度'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 8,
            value: current.strokeWidth,
            label: current.strokeWidth.toStringAsFixed(1),
            divisions: 80,
            onChanged: (double v) => controller.update(
              (SettingsModel s) => s.copyWith(strokeWidth: v),
            ),
          ),
        ),
        SizedBox(
          width: 40, // magic-exempt: 沿用既有面板數值顯示欄寬慣例
          child: Text(current.strokeWidth.toStringAsFixed(1)),
        ),
      ],
    );
  }

  Widget _buildTimeFormat(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('時間格式'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        DropdownButton<String>(
          value: current.timeFormat,
          items: <DropdownMenuItem<String>>[
            for (final String f in timeFormats)
              DropdownMenuItem<String>(value: f, child: Text(f)),
          ],
          onChanged: (String? v) {
            if (v == null) return;
            controller.update((SettingsModel s) => s.copyWith(timeFormat: v));
          },
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../app_constants.dart';
import '../../models/settings_model.dart';
import '../../state/settings_controller.dart';
import 'settings_color_picker.dart';

/// 滑鼠定位器設定區（SPEC-008 FR-06）：啟用開關、特效時長、主色調。
/// 純結構搬移自 settings_panel.dart（1.4.0-W3-003），行為不變。
///
/// 值域夾制屬 1.4.0-W2-010（model 層 fromJson）；本區塊 Slider min/max
/// 僅引用 [AppCursorLocator] 常數，不重複實作夾制。啟用開關的熱鍵註冊/
/// 解除屬 1.4.0-W2-005，本區塊只負責寫回 [SettingsController]。
class SettingsCursorLocatorSection extends StatelessWidget {
  const SettingsCursorLocatorSection({
    super.key,
    required this.controller,
    required this.current,
  });

  final SettingsController controller;
  final SettingsModel current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          AppText.cursorLocatorSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(
          height: 8,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，無 spacing token 設施
        _buildEnabled(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，無 spacing token 設施
        _buildDuration(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，無 spacing token 設施
        SettingsColorPicker(
          label: AppText.cursorLocatorColorLabel,
          current: current.cursorLocatorPrimaryColor,
          onPick: (Color c) => controller.update(
            (SettingsModel s) => s.copyWith(cursorLocatorPrimaryColor: c),
          ),
        ),
      ],
    );
  }

  Widget _buildEnabled(SettingsController controller, SettingsModel current) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80, // magic-exempt: 沿用既有面板欄位標籤寬度慣例
          child: Text(AppText.cursorLocatorEnabledLabel),
        ),
        Switch(
          key: const ValueKey<String>('cursor-locator-enabled-switch'),
          value: current.cursorLocatorEnabled,
          onChanged: (bool v) => controller.update(
            (SettingsModel s) => s.copyWith(cursorLocatorEnabled: v),
          ),
        ),
      ],
    );
  }

  Widget _buildDuration(SettingsController controller, SettingsModel current) {
    final double seconds = current.cursorLocatorEffectDurationSeconds;
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80, // magic-exempt: 沿用既有面板欄位標籤寬度慣例
          child: Text(AppText.cursorLocatorDurationLabel),
        ),
        Expanded(
          child: Slider(
            key: const ValueKey<String>('cursor-locator-duration-slider'),
            min: AppCursorLocator.minDurationSeconds,
            max: AppCursorLocator.maxDurationSeconds,
            value: seconds,
            label: seconds.toStringAsFixed(1),
            // (3.0 - 0.5) 秒值域 / 0.1 秒單格 = 25 格，對齊既有滑桿 0.1 精度慣例。
            divisions: 25, // magic-exempt: 由值域/精度推導，見上行註解
            onChanged: (double v) => controller.update(
              (SettingsModel s) =>
                  s.copyWith(cursorLocatorEffectDurationSeconds: v),
            ),
          ),
        ),
        SizedBox(
          width: 40, // magic-exempt: 沿用既有面板數值顯示欄寬慣例
          child: Text('${seconds.toStringAsFixed(1)}s'),
        ),
      ],
    );
  }
}

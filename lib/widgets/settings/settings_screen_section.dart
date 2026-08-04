import 'package:flutter/material.dart';

import '../../models/settings_model.dart';
import '../../state/settings_controller.dart';

/// 目標螢幕設定區（SPEC-005 FR-03 + SPEC-003 FR-01）。純結構搬移自
/// settings_panel.dart（1.4.0-W3-003），行為不變。
class SettingsScreenSection extends StatelessWidget {
  const SettingsScreenSection({
    super.key,
    required this.availableScreenCount,
    required this.controller,
    required this.current,
  });

  /// 目前可選擇的螢幕數，用於 dropdown 上限。
  final int availableScreenCount;
  final SettingsController controller;
  final SettingsModel current;

  @override
  Widget build(BuildContext context) {
    final int max = availableScreenCount > 0 ? availableScreenCount : 1;
    final int safeValue = current.targetScreenIndex < max
        ? current.targetScreenIndex
        : 0;
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('目標螢幕'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        DropdownButton<int>(
          value: safeValue,
          items: <DropdownMenuItem<int>>[
            for (int i = 0; i < max; i++)
              DropdownMenuItem<int>(
                value: i,
                // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
                child: Text(i == 0 ? '主螢幕' : '螢幕 $i'),
              ),
          ],
          onChanged: (int? v) {
            if (v == null) return;
            controller.update(
              (SettingsModel s) => s.copyWith(targetScreenIndex: v),
            );
          },
        ),
        const SizedBox(
          width: 8,
        ), // magic-exempt: 沿用既有面板欄位間距慣例，非本次新增
        const Text(
          '（套用需重啟 app）', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}

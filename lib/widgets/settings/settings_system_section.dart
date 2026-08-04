import 'package:flutter/material.dart';

import '../../models/settings_model.dart';
import '../../state/settings_controller.dart';

/// 系統整合設定區：開機啟動、生命計時、出生日期。純結構搬移自
/// settings_panel.dart（1.4.0-W3-003），行為不變。
class SettingsSystemSection extends StatelessWidget {
  const SettingsSystemSection({
    super.key,
    required this.controller,
    required this.current,
  });

  final SettingsController controller;
  final SettingsModel current;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildAutoLaunch(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        _buildLifeTimer(controller, current),
        const SizedBox(
          height: 12,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        _buildBirthDate(context, controller, current),
      ],
    );
  }

  Widget _buildAutoLaunch(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('開機啟動'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        Switch(
          value: current.autoLaunch,
          onChanged: (bool v) =>
              controller.update((SettingsModel s) => s.copyWith(autoLaunch: v)),
        ),
      ],
    );
  }

  Widget _buildLifeTimer(SettingsController controller, SettingsModel current) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('生命計時'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        Switch(
          value: current.lifeTimerMode,
          onChanged: (bool v) => controller.update(
            (SettingsModel s) => s.copyWith(lifeTimerMode: v),
          ),
        ),
        const SizedBox(
          width: 8,
        ), // magic-exempt: 沿用既有面板欄位間距慣例，非本次新增
        const Expanded(
          child: Text(
            '顯示即時年齡取代時間', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthDate(
    BuildContext context,
    SettingsController controller,
    SettingsModel current,
  ) {
    final DateTime? birth = current.birthDate;
    final String label = birth == null
        ? '未設定' // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        : '${birth.year}-${_pad2(birth.month)}-${_pad2(birth.day)}';
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text('出生日期'), // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
        ),
        OutlinedButton(
          onPressed: () => _pickBirthDate(context, controller, birth),
          child: Text(label),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate(
    BuildContext context,
    SettingsController controller,
    DateTime? current,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime initial =
        current ?? DateTime(today.year - 20, today.month, today.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked != null) {
      controller.update((SettingsModel s) => s.copyWith(birthDate: picked));
    }
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');
}

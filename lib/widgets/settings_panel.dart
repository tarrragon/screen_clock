import 'package:flutter/material.dart';

import '../models/settings_model.dart';
import '../state/settings_controller.dart';
import '../state/settings_scope.dart';

/// 設定面板（SPEC-005 FR-03 / FR-04）。
///
/// 七個欄位對應 [SettingsModel]；變更走 [SettingsController.update]
/// → InheritedNotifier rebuild → CenterClock 即時預覽。
///
/// 「儲存」呼叫 [SettingsController.persist] 後關閉；
/// 「取消」呼叫 [SettingsController.resetToStartup] 後關閉。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.availableScreenCount,
    required this.onClose,
  });

  /// 目前可選擇的螢幕數，用於 dropdown 上限（SPEC-005 FR-03 + SPEC-003 FR-01）。
  final int availableScreenCount;

  /// 關閉面板的回呼。
  ///
  /// 面板是 Stack overlay（非 Navigator route），不能用 `Navigator.pop` 關閉；
  /// 由上層 `_PanelHost` 注入，內部設 `_panelOpen = false` 並還原 click-through。
  final VoidCallback onClose;

  static const List<String> timeFormats = <String>['HH:mm:ss', 'HH:mm'];

  /// 預設色盤（不透明 RGB 基色，色碼即 Material 對應色）。
  /// 實際套用的透明度由各欄位現有 alpha + 不透明度滑桿決定，不寫死於此。
  static const List<Color> presetColors = <Color>[
    Color(0xFFFFFFFF), // 白
    Color(0xFF000000), // 黑
    Color(0xFFF44336), // 紅
    Color(0xFFFF9800), // 橙
    Color(0xFFFFEB3B), // 黃
    Color(0xFF4CAF50), // 綠
    Color(0xFF2196F3), // 藍
    Color(0xFF9C27B0), // 紫
  ];

  @override
  Widget build(BuildContext context) {
    final SettingsController controller =
        SettingsScope.controllerOf(context);
    final SettingsModel current = SettingsScope.of(context);

    return Center(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '設定',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _buildFontSize(controller, current),
                const SizedBox(height: 12),
                _buildStrokeWidth(controller, current),
                const SizedBox(height: 12),
                _buildColorPicker(
                  label: '填色',
                  current: current.fillColor,
                  onPick: (Color c) => controller
                      .update((SettingsModel s) => s.copyWith(fillColor: c)),
                ),
                const SizedBox(height: 12),
                _buildColorPicker(
                  label: '描邊色',
                  current: current.strokeColor,
                  onPick: (Color c) => controller
                      .update((SettingsModel s) => s.copyWith(strokeColor: c)),
                ),
                const SizedBox(height: 12),
                _buildTimeFormat(controller, current),
                const SizedBox(height: 12),
                _buildTargetScreen(controller, current),
                const SizedBox(height: 12),
                _buildAutoLaunch(controller, current),
                const SizedBox(height: 12),
                _buildLifeTimer(controller, current),
                const SizedBox(height: 12),
                _buildBirthDate(context, controller, current),
                const SizedBox(height: 24),
                _buildActions(context, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontSize(SettingsController controller, SettingsModel current) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('字型大小')),
        Expanded(
          child: Slider(
            min: 40,
            max: 240,
            value: current.fontSize,
            label: current.fontSize.round().toString(),
            divisions: 200,
            onChanged: (double v) => controller
                .update((SettingsModel s) => s.copyWith(fontSize: v)),
          ),
        ),
        SizedBox(
          width: 40,
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
        const SizedBox(width: 80, child: Text('描邊寬度')),
        Expanded(
          child: Slider(
            min: 0,
            max: 8,
            value: current.strokeWidth,
            label: current.strokeWidth.toStringAsFixed(1),
            divisions: 80,
            onChanged: (double v) => controller
                .update((SettingsModel s) => s.copyWith(strokeWidth: v)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(current.strokeWidth.toStringAsFixed(1)),
        ),
      ],
    );
  }

  Widget _buildColorPicker({
    required String label,
    required Color current,
    required ValueChanged<Color> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(width: 80, child: Text(label)),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final Color preset in presetColors)
                    _ColorSwatch(
                      color: preset,
                      selected: _sameRgb(preset, current),
                      // 只換 RGB，保留目前 alpha（填色 0C / 描邊 0A 不被覆蓋）。
                      onTap: () => onPick(preset.withValues(alpha: current.a)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            const SizedBox(width: 80, child: Text('不透明度', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                min: 0,
                max: 1,
                value: current.a,
                label: '${(current.a * 100).round()}%',
                divisions: 100,
                // 只換 alpha，保留目前 RGB。
                onChanged: (double v) => onPick(current.withValues(alpha: v)),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${(current.a * 100).round()}%'),
            ),
          ],
        ),
      ],
    );
  }

  /// 比較兩色 RGB 是否相同（忽略 alpha），用於色盤選中標記。
  static bool _sameRgb(Color a, Color b) {
    return a.r == b.r && a.g == b.g && a.b == b.b;
  }

  Widget _buildTimeFormat(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('時間格式')),
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

  Widget _buildTargetScreen(
    SettingsController controller,
    SettingsModel current,
  ) {
    final int max = availableScreenCount > 0 ? availableScreenCount : 1;
    final int safeValue =
        current.targetScreenIndex < max ? current.targetScreenIndex : 0;
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('目標螢幕')),
        DropdownButton<int>(
          value: safeValue,
          items: <DropdownMenuItem<int>>[
            for (int i = 0; i < max; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Text(i == 0 ? '主螢幕' : '螢幕 $i'),
              ),
          ],
          onChanged: (int? v) {
            if (v == null) return;
            controller
                .update((SettingsModel s) => s.copyWith(targetScreenIndex: v));
          },
        ),
        const SizedBox(width: 8),
        const Text('（套用需重啟 app）', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildAutoLaunch(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('開機啟動')),
        Switch(
          value: current.autoLaunch,
          onChanged: (bool v) => controller
              .update((SettingsModel s) => s.copyWith(autoLaunch: v)),
        ),
      ],
    );
  }

  Widget _buildLifeTimer(
    SettingsController controller,
    SettingsModel current,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('生命計時')),
        Switch(
          value: current.lifeTimerMode,
          onChanged: (bool v) => controller
              .update((SettingsModel s) => s.copyWith(lifeTimerMode: v)),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '顯示即時年齡取代時間',
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
        ? '未設定'
        : '${birth.year}-${_pad2(birth.month)}-${_pad2(birth.day)}';
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('出生日期')),
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

  Widget _buildActions(BuildContext context, SettingsController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: () {
            controller.resetToStartup();
            onClose();
          },
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            await controller.persist();
            onClose();
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

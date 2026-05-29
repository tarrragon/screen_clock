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

  static const List<Color> presetColors = <Color>[
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
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
    return Row(
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
                  selected: preset == current,
                  onTap: () => onPick(preset),
                ),
            ],
          ),
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

import 'package:flutter/material.dart';

/// 共用色彩選取列（樣式區與滑鼠定位器區共用，1.4.0-W3-003 自 settings_panel
/// 抽出）：色盤 + 不透明度滑桿。純結構搬移，行為與原 `_buildColorPicker` 相同。
class SettingsColorPicker extends StatelessWidget {
  const SettingsColorPicker({
    super.key,
    required this.label,
    required this.current,
    required this.onPick,
  });

  final String label;
  final Color current;
  final ValueChanged<Color> onPick;

  /// 預設色盤（不透明 RGB 基色，色碼即 Material 對應色）。
  /// 實際套用的透明度由各欄位現有 alpha + 不透明度滑桿決定，不寫死於此。
  static const List<Color> presetColors = <Color>[
    Color(0xFFFFFFFF), // 白 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFF000000), // 黑 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFFF44336), // 紅 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFFFF9800), // 橙 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFFFFEB3B), // 黃 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFF4CAF50), // 綠 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFF2196F3), // 藍 // color-exempt: 沿用既有色盤字面值，純結構搬移
    Color(0xFF9C27B0), // 紫 // color-exempt: 沿用既有色盤字面值，純結構搬移
  ];

  /// 比較兩色 RGB 是否相同（忽略 alpha），用於色盤選中標記。
  static bool _sameRgb(Color a, Color b) {
    return a.r == b.r && a.g == b.g && a.b == b.b;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 80, // magic-exempt: 沿用既有面板欄位標籤寬度慣例
              child: Text(label),
            ),
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
        const SizedBox(
          height: 4,
        ), // magic-exempt: 沿用既有面板區塊間距慣例，非本次新增
        Row(
          children: <Widget>[
            const SizedBox(
              width: 80, // magic-exempt: 沿用既有面板欄位標籤寬度慣例
              child: Text(
                '不透明度', // i18n-exempt: 沿用既有硬編碼字串，純結構搬移，非本票範圍
                style: TextStyle(fontSize: 12),
              ),
            ),
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
              width: 40, // magic-exempt: 沿用既有面板數值顯示欄寬慣例
              child: Text('${(current.a * 100).round()}%'),
            ),
          ],
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
        width: 28, // magic-exempt: 沿用既有色盤色塊尺寸慣例
        height: 28, // magic-exempt: 沿用既有色盤色塊尺寸慣例
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26, // color-exempt: 沿用既有未選中邊框色字面值，純結構搬移
            width: selected ? 3 : 1, // magic-exempt: 沿用既有選中框線寬度慣例
          ),
        ),
      ),
    );
  }
}

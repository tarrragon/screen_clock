import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../models/settings_model.dart';
import '../state/settings_scope.dart';

/// 螢幕中央時鐘 widget（SPEC-002 + SPEC-005 FR-04 即時預覽）。
///
/// 樣式從 [SettingsScope] 注入（v1.0.0 前後相容）：
/// - 若上層提供 SettingsScope → 從中讀取 [SettingsModel]
/// - 否則 fallback 到 [SettingsModel.defaults] 重現 v0.x 寫死值
///
/// 時間更新仍走 [Timer.periodic]；setState 只觸發本子樹重繪。
class CenterClock extends StatefulWidget {
  const CenterClock({super.key});

  /// 把 [DateTime] 格式化為指定 [pattern]。
  ///
  /// MVP 階段只接受 `HH:mm:ss` / `HH:mm` 兩種；其他 pattern 視同 `HH:mm:ss`
  /// 避免引入 intl 套件（SPEC-002 設計約束 / SPEC-005 FR-03 dropdown 限制）。
  static String formatTime(
    DateTime time, [
    String pattern = AppText.timeFormat,
  ]) {
    final String hh = time.hour.toString().padLeft(2, '0');
    final String mm = time.minute.toString().padLeft(2, '0');
    final String ss = time.second.toString().padLeft(2, '0');
    if (pattern == 'HH:mm') {
      return '$hh:$mm';
    }
    return '$hh:$mm:$ss';
  }

  @override
  State<CenterClock> createState() => _CenterClockState();
}

class _CenterClockState extends State<CenterClock> {
  late DateTime _current;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _current = DateTime.now();
    _ticker = Timer.periodic(AppDurations.clockTick, _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _onTick(Timer _) {
    if (!mounted) {
      return;
    }
    setState(() {
      _current = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsModel settings = _resolveSettings(context);
    final String label = CenterClock.formatTime(_current, settings.timeFormat);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 描邊層：用 foreground stroke 畫黑邊（SPEC-002 FR-04）。
          Text(
            label,
            style: TextStyle(
              fontFamily: AppText.clockFontFamily,
              fontSize: settings.fontSize,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                // 圓角接合 + 圓端點：避免字形銳角（如「2」）的 miter 尖角
                // 互相穿越造成線條交錯重疊（預設 StrokeJoin.miter 的問題）。
                ..strokeJoin = StrokeJoin.round
                ..strokeCap = StrokeCap.round
                ..strokeWidth = settings.strokeWidth
                ..color = settings.strokeColor,
            ),
          ),
          // 填色層（SPEC-002 FR-04）。
          Text(
            label,
            style: TextStyle(
              fontFamily: AppText.clockFontFamily,
              fontSize: settings.fontSize,
              fontWeight: FontWeight.w700,
              color: settings.fillColor,
            ),
          ),
        ],
      ),
    );
  }

  SettingsModel _resolveSettings(BuildContext context) {
    final SettingsScope? scope = context
        .dependOnInheritedWidgetOfExactType<SettingsScope>();
    return scope?.notifier?.value ?? SettingsModel.defaults();
  }
}

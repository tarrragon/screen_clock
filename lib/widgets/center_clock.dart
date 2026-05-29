import 'dart:async';

import 'package:flutter/material.dart';

import '../age_formatter.dart';
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

  /// 目前 ticker 的更新間隔；模式切換時用來判斷是否需要重建 ticker。
  Duration? _activeInterval;

  @override
  void initState() {
    super.initState();
    _current = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 生命計時模式需要高頻跑數；一般時鐘每秒更新即可。
    // 依設定挑選間隔，僅在間隔改變時重建 ticker（避免每次 rebuild 重啟）。
    final SettingsModel settings = _resolveSettings(context);
    final Duration interval = settings.lifeTimerMode
        ? AppDurations.lifeTimerTick
        : AppDurations.clockTick;
    if (interval != _activeInterval) {
      _restartTicker(interval);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _restartTicker(Duration interval) {
    _ticker?.cancel();
    _activeInterval = interval;
    _ticker = Timer.periodic(interval, _onTick);
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
    final String label = _resolveLabel(settings);
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
              fontWeight: FontWeight.w900,
              color: settings.fillColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 決定要顯示的字串：生命計時模式（且已設出生日）顯示即時年齡，否則顯示時間。
  String _resolveLabel(SettingsModel settings) {
    final DateTime? birthDate = settings.birthDate;
    if (settings.lifeTimerMode && birthDate != null) {
      return AgeFormatter.format(birthDate, _current);
    }
    return CenterClock.formatTime(_current, settings.timeFormat);
  }

  SettingsModel _resolveSettings(BuildContext context) {
    final SettingsScope? scope = context
        .dependOnInheritedWidgetOfExactType<SettingsScope>();
    return scope?.notifier?.value ?? SettingsModel.defaults();
  }
}

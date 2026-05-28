import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';

/// 螢幕中央時鐘 widget。
///
/// 覆蓋 SPEC-002 全部 FR：
/// - FR-01 顯示當前本機時間（24 小時制 HH:mm:ss）
/// - FR-02 每秒自動更新；dispose 取消 timer 避免洩漏
/// - FR-03 中央定位（外層 [Center]）
/// - FR-04 預設樣式（120sp 粗體 白色 + 黑邊 stroke）
///
/// MVP 階段樣式寫死於 [AppSizes] / [AppColors]；
/// v1.0.0 設定面板上線後改由 SettingsModel 注入。
class CenterClock extends StatefulWidget {
  const CenterClock({super.key});

  /// 把 [DateTime] 格式化為 SPEC-002 FR-01 預設格式 `HH:mm:ss`。
  ///
  /// 用 `padLeft(2, '0')` 手寫補零，避免引入 intl 套件依賴
  /// （SPEC-002 設計約束）。
  static String formatTime(DateTime time) {
    final String hh = time.hour.toString().padLeft(2, '0');
    final String mm = time.minute.toString().padLeft(2, '0');
    final String ss = time.second.toString().padLeft(2, '0');
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
    final String label = CenterClock.formatTime(_current);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 描邊層：用 foreground stroke 畫黑邊（SPEC-002 FR-04）。
          Text(
            label,
            style: TextStyle(
              fontSize: AppSizes.clockFontSize,
              fontWeight: FontWeight.w700,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = AppSizes.clockStrokeWidth
                ..color = AppColors.clockStroke,
            ),
          ),
          // 填色層：白色字（SPEC-002 FR-04）。
          Text(
            label,
            style: const TextStyle(
              fontSize: AppSizes.clockFontSize,
              fontWeight: FontWeight.w700,
              color: AppColors.clockFill,
            ),
          ),
        ],
      ),
    );
  }
}

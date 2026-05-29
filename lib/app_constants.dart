import 'package:flutter/material.dart';

/// 全專案集中常數定義。
///
/// MVP（v0.x）階段所有 UI / 視窗 / 時間設定皆寫死於此。
/// v1.0.0 設定面板上線後，可由使用者調整的項目改由 SettingsModel 注入；
/// 此檔案保留純框架常數（不應由使用者修改的部分）。
///
/// 對應規格：
/// - SPEC-001（透明全螢幕遮罩視窗）：AppWindow / AppColors.overlayBackground / AppSizes.windowOrigin
/// - SPEC-002（螢幕中央時鐘顯示）：AppText.timeFormat / AppSizes.clock* / AppColors.clock* / AppDurations.clockTick
class AppText {
  AppText._();

  static const String appTitle = 'Screen Clock';

  /// 24 小時制；SPEC-002 FR-01 預設格式。
  static const String timeFormat = 'HH:mm:ss';

  /// 時鐘字型（Google Fonts 家族名稱）。
  ///
  /// 測試可用的字體，不會有邊框重疊或這銳角重疊的狀況
  /// Oswald
  /// Roboto Mono
  /// Orbitron
  /// Share Tech Mono
  /// Fredoka
  static const String clockFontFamily = 'Oswald';
}

class AppSizes {
  AppSizes._();

  /// SPEC-002 FR-04：120 sp 對應 1920x1080 螢幕約 2m 距離可讀。
  static const double clockFontSize = 120;

  /// SPEC-002 FR-04：黑邊描邊寬度，避免白底桌布看不見。
  static const double clockStrokeWidth = 2;

  /// SPEC-001 FR-01：視窗原點為主螢幕左上角。
  static const Offset windowOrigin = Offset.zero;

  /// SPEC-001 FR-01 替代場景 01a：主螢幕尺寸偵測失敗時的 fallback。
  /// 1920x1080 是常見桌面解析度，能涵蓋大多數情境，避免視窗 0x0 不可見。
  static const Size fallbackWindowSize = Size(1920, 1080);
}

class AppColors {
  AppColors._();

  /// SPEC-002 FR-04 預設樣式：白底。
  static const Color clockFill = Color(0x0Cffffff);

  /// SPEC-002 FR-04 預設樣式：黑邊。
  static const Color clockStroke = Color(0x0A0A0A0A);

  /// SPEC-001 FR-02：視窗背景真透明（alpha=0）。
  static const Color overlayBackground = Colors.transparent;
}

class AppDurations {
  AppDurations._();

  /// SPEC-002 FR-02：時鐘每秒更新一次。
  static const Duration clockTick = Duration(seconds: 1);

  /// 生命計時模式的跑數更新間隔。
  ///
  /// 年齡小數第 8 位 ≈ 0.32 秒跳動一次；以 50ms 更新可平順呈現跑數，
  /// 又不會像逐幀更新那樣過度重繪。
  static const Duration lifeTimerTick = Duration(milliseconds: 50);
}

/// 生命計時（即時年齡）相關常數。
class AppAge {
  AppAge._();

  /// 平均西曆年天數（每 400 年 97 個閏日 → 365 + 97/400 = 365.2425）。
  /// 作為「一年」長度基準，使年齡換算不受個別閏年跳動影響。
  static const double daysPerYear = 365.2425;

  /// 年齡小數位數（8 位 → 剛好 4 組兩位數，配對無餘數）。
  static const int decimalPlaces = 8;
}

class AppWindow {
  AppWindow._();

  /// SPEC-001 FR-03：無邊框。
  static const bool isFrameless = true;

  /// SPEC-001 FR-04：永遠置頂。
  static const bool isAlwaysOnTop = true;

  /// SPEC-001 FR-03：無陰影（避免透明視窗外緣灰邊）。
  static const bool hasShadow = false;

  /// SPEC-001 FR-05：滑鼠 click-through。
  static const bool ignoreMouseEvents = true;
}

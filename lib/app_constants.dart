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

  /// 狀態列（選單列）顯示文字。
  static const String trayTitle = 'timer';

  /// 狀態列佔位透明圖示路徑（macOS 需先 setIcon 才會建立 status item）。
  static const String trayIconAsset = 'assets/tray/transparent.png';

  /// 狀態列選單標籤。
  static const String trayMenuSettings = '設定…';
  static const String trayMenuShowClock = '顯示時鐘';
  static const String trayMenuHideClock = '隱藏時鐘';
  static const String trayMenuQuit = '離開';

  /// 時鐘字型（Google Fonts 家族名稱）。
  ///
  /// 測試可用的字體，不會有邊框重疊或這銳角重疊的狀況
  /// 但是非等寬字體會讓字的寬度跳動，使用 monospace 的字體才能避免
  /// Oswald
  /// Roboto Mono
  /// Orbitron
  /// Share Tech Mono
  /// Fredoka
  static const String clockFontFamily = 'Roboto Mono';
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

  /// 生命計時模式的跑數更新間隔（約 60fps）。
  ///
  /// 16ms 逐幀更新讓跑數最平順；年齡小數末位 ≈ 0.3 秒跳動，此頻率足以
  /// 平滑呈現且不漏更新。
  static const Duration lifeTimerTick = Duration(milliseconds: 16);
}

/// 生命計時（即時年齡）相關常數。
class AppAge {
  AppAge._();

  /// 平均西曆年天數（每 400 年 97 個閏日 → 365 + 97/400 = 365.2425）。
  /// 作為「一年」長度基準，使年齡換算不受個別閏年跳動影響。
  static const double daysPerYear = 365.2425;

  /// 年齡小數位數（8 位 → 剛好 4 組兩位數，配對無餘數）。
  /// 須為偶數以維持兩位數配對。8 位末位 ≈ 0.3 秒跳動，肉眼可辨；
  /// 更高位數（如 10 位）末位過快難以辨識，反失意義。
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

  /// 顯示於所有桌面（macOS Spaces）。
  /// 設 canJoinAllSpaces，使遮罩時鐘出現在每個桌面、切換桌面時跟隨，
  /// 而非綁定在啟動時的單一桌面。
  static const bool visibleOnAllWorkspaces = true;

  /// 是否在全螢幕 app 之上仍可見（fullScreenAuxiliary）。
  /// 設 false：全螢幕 app 佔據獨立 Space 時，遮罩時鐘不侵入、不遮蓋全螢幕視窗。
  static const bool visibleOnFullScreen = false;
}

/// 假全螢幕（影片 / 簡報 / 遊戲）覆蓋偵測相關常數。
///
/// 對應 ticket 1.2.1-W2-001：native fullscreen（綠燈鈕、獨立 Space）由
/// [AppWindow.visibleOnFullScreen] 處理；假全螢幕是鋪滿螢幕的「普通視窗」，
/// 不建獨立 Space，須由原生 CGWindowList 覆蓋判定偵測，經此 channel 回報
/// Dart 端切換時鐘顯示。
class AppFullscreenDetect {
  AppFullscreenDetect._();

  /// 原生端回報假全螢幕覆蓋狀態的 method channel 名稱。
  /// 須與 macos/Runner/MainFlutterWindow.swift 內字面一致。
  static const String channelName = 'screen_clock/fullscreen_detect';

  /// 原生 → Dart：覆蓋狀態變化通知方法名。
  /// 參數 `covered`（bool）：目標螢幕是否被假全螢幕視窗鋪滿。
  static const String onCoverageChangedMethod = 'onCoverageChanged';

  /// 原生 → Dart 參數鍵：是否被覆蓋。
  static const String coveredArgKey = 'covered';
}

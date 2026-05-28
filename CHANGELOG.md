# Changelog

All notable changes to **screen_clock** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-29

第一個 macOS 正式版。

### Added

- **v0.1.0 透明遮罩視窗**：window_manager 整合 + macOS 平台原生 Swift 透明背景（`isOpaque = false; backgroundColor = .clear`）+ frameless / always-on-top / no-shadow / setIgnoreMouseEvents 全套啟動序列；視窗貼合主螢幕含 fallback。
- **v0.2.0 中央時鐘 widget**：CenterClock StatefulWidget；HH:mm:ss 格式化（無 intl 依賴）；Timer.periodic 每秒更新 + dispose 清理；120sp 粗體白底 + 黑邊 stroke 樣式；Center 定位。
- **v0.3.0 多螢幕選擇**：DisplayDetector module（listDisplays / resolveTargetDisplay / startWatching）；CLI `--screen=N` 引數解析；螢幕熱插拔 → fallback 主螢幕。
- **v1.0.0 W1 設定持久化**：SettingsModel（7 欄位 + schemaVersion + ARGB 顏色序列化 + 容錯 fromJson）；SettingsService 介面（PreferencesSettingsService backed by shared_preferences、InMemorySettingsService 測試替身）；啟動時讀取設定並套用 targetScreenIndex（CLI 優先）。
- **v1.0.0 W2 設定面板**：全域熱鍵 Cmd+Opt+,（hotkey_manager）；動態 click-through 切換（setIgnoreMouseEvents(false/true)）；SettingsPanel UI（字型 / 描邊 / 顏色 / 時間格式 / 目標螢幕 / 開機啟動）；SettingsController + SettingsScope InheritedNotifier 即時預覽。
- **v1.0.0 W3 開機啟動**：AutoLaunchService（launch_at_startup 套件包裝）；啟動時 OS 狀態優先 reconcile。
- **v1.0.0 W4 收尾發布**：scripts/build-release.sh + scripts/sign-and-notarize.sh；README 全面改寫；CHANGELOG 建立。

### Architecture

- `lib/app_constants.dart` 為全專案常數單一來源（AppText / AppSizes / AppColors / AppDurations / AppWindow）。
- 所有依賴注入透過建構子或 InheritedNotifier；不使用第三方 DI / 狀態管理套件。
- 測試覆蓋：35+ tests cover format helpers, SettingsModel round-trip, SettingsService 損壞 JSON 處理, AutoLaunchService in-memory double, ScreenClockApp scaffold smoke test。

### Known Limitations

- App icon 仍為 Flutter scaffold 預設；替換流程見 `macos/Runner/Assets.xcassets/AppIcon.appiconset/README.md`。
- Code signing 與 notarize 需 Apple Developer 帳號才能執行；scripts 已準備好。
- 全螢幕 app（Keynote 播放等）會位於遮罩之上（macOS z-order 系統限制）。
- 多螢幕情境下非主螢幕的 menu bar 區域可能不被覆蓋（`Display.visiblePosition` 限制）。

### Roadmap

- v1.1.x：Windows 平台支援（layered window `WS_EX_LAYERED | WS_EX_TRANSPARENT`）。

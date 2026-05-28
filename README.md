# screen_clock

桌面螢幕透明遮罩時鐘 — 在 macOS 上以全螢幕透明覆蓋層顯示中央時鐘，視窗點擊穿透，不阻擋底下程式的任何操作。

## 功能

- 全螢幕透明遮罩，覆蓋整個目標螢幕
- 螢幕中央顯示當前本機時間（HH:mm:ss / HH:mm）
- 滑鼠 / 鍵盤事件完全穿透（click-through）
- 永遠置頂
- 多螢幕選擇（`--screen=N` CLI 引數 / 設定面板）
- 設定面板（Cmd + Option + ,）：字型大小、描邊寬度、填色 / 描邊色、時間格式、目標螢幕、開機啟動
- 設定持久化（shared_preferences）
- macOS 開機自動啟動（SMAppService / launchd）

## 系統需求

- macOS 12+ Monterey 以上
- Flutter 3.41+ stable
- Dart SDK 3.11.1+

> Windows / Linux 暫不支援。Windows 計畫於 v1.1.x 加入。

## 安裝

### 從原始碼建置

```bash
git clone https://github.com/tarrragon/screen_clock.git
cd screen_clock
flutter pub get
flutter build macos --release
open build/macos/Build/Products/Release/screen_clock.app
```

### 從 .dmg 安裝（v1.0.0 發布後）

1. 下載 `screen_clock-1.0.0.dmg`
2. 拖曳 `screen_clock.app` 到 `Applications`
3. 首次啟動時系統可能要求允許輔助功能權限

## 使用方式

### 啟動

```bash
open /Applications/screen_clock.app          # 預設主螢幕
open /Applications/screen_clock.app --args --screen=1  # 指定第二螢幕
```

### 快捷鍵

| 按鍵 | 行為 |
|------|------|
| `Cmd + Option + ,` | 開啟 / 關閉設定面板 |
| `Cmd + Q` | 退出 app |

### 設定面板

按 `Cmd + Option + ,` 開啟。可調整：

| 欄位 | 範圍 |
|------|------|
| 字型大小 | 40 ~ 240 |
| 描邊寬度 | 0 ~ 8 |
| 填色 | 8 預設色 |
| 描邊色 | 8 預設色 |
| 時間格式 | `HH:mm:ss` / `HH:mm` |
| 目標螢幕 | 主螢幕 / 螢幕 1, 2, ... |
| 開機啟動 | On / Off |

按「儲存」套用並關閉；「取消」捨棄變更。目標螢幕變更需重啟 app 生效。

### CLI 引數

| 引數 | 說明 |
|------|------|
| `--screen=N` | 在第 N 個螢幕（0-indexed）顯示遮罩，覆寫儲存的設定 |

## 開發

### 跑測試

```bash
flutter test
flutter analyze    # 必須 0 issue
```

### 文件結構

| 路徑 | 用途 |
|------|------|
| `docs/proposals/PROP-001-*.md` | 提案：桌面螢幕透明時鐘遮罩 |
| `docs/spec/platform/transparent-overlay-window.md` | SPEC-001 透明全螢幕遮罩視窗 |
| `docs/spec/display/center-clock.md` | SPEC-002 中央時鐘 |
| `docs/spec/platform/multi-screen-selection.md` | SPEC-003 多螢幕選擇 |
| `docs/spec/data-management/settings-storage.md` | SPEC-004 設定持久化 |
| `docs/spec/user-experience/settings-panel-entry.md` | SPEC-005 設定面板 |
| `docs/spec/platform/macos-auto-launch.md` | SPEC-006 開機啟動 |
| `docs/usecases/UC-*.md` | 用例 |
| `docs/work-logs/v0..1/` | 各版本工作日誌 |
| `CLAUDE.md` | Claude Code 開發指導規範 |

### 程式碼規範

- **不硬編碼**：所有可命名的字面值集中於 `lib/app_constants.dart`，由 `SettingsModel` 注入。詳見 CLAUDE.md Section 6「常數集中規範」。
- TDD 開發流程；Phase 0 ~ Phase 4 見 `.claude/pm-rules/tdd-flow.md`。

## 已知限制

- 多螢幕情境下，非主螢幕的 menu bar 區域可能不被遮罩覆蓋（`Display.visiblePosition` 限制）
- 全螢幕應用（Keynote 播放、瀏覽器全螢幕）會位於遮罩之上（macOS 預設 z-order）
- Mission Control / Stage Manager 切換時遮罩可能短暫變成可見視窗（macOS 對 always-on-top 透明視窗的處理）
- 系統匯入 / 變更時區後需重啟 app 才能反映

## 路線圖

| 版本 | 內容 |
|------|------|
| v0.0.x | Flutter scaffold |
| v0.1.x | macOS 透明遮罩視窗 |
| v0.2.x | 中央時鐘 widget |
| v0.3.x | 多螢幕選擇 |
| v1.0.0 | 設定面板 + 持久化 + 開機啟動 + 發布 |
| v1.1.x | Windows 平台支援（layered window） |

## 授權

MIT（待補 LICENSE 檔）

## 致謝

- [window_manager](https://pub.dev/packages/window_manager)
- [screen_retriever](https://pub.dev/packages/screen_retriever)
- [hotkey_manager](https://pub.dev/packages/hotkey_manager)
- [launch_at_startup](https://pub.dev/packages/launch_at_startup)
- [shared_preferences](https://pub.dev/packages/shared_preferences)

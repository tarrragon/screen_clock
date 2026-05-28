---
id: UC-01
title: "啟動透明時鐘遮罩"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"

primary_actor: "桌面使用者"
secondary_actors: []

platform: app
extension_status: not-applicable

related_specs:
  - SPEC-001
  - SPEC-002
related_usecases:
  - UC-02
  - UC-03
ticket_refs: []
---

# UC-01: 啟動透明時鐘遮罩

## 基本資訊

| 項目 | 值 |
|------|-----|
| 用例 ID | UC-01 |
| 用例名稱 | 啟動透明時鐘遮罩 |
| 主要行為者 | 桌面使用者（macOS） |
| 利益關係人 | 使用者：能即時看到時間；系統：app 不干擾其他應用 |
| 前置條件 | macOS 12+；已安裝並信任 app；目前無 screen_clock instance 在執行 |
| 成功保證 | 螢幕中央可見時鐘文字；遮罩涵蓋整個主螢幕；底下視窗操作完全不受影響 |

## 主要成功場景

1. **啟動 app**
   - 使用者於 Launchpad / Finder 雙擊 screen_clock app
   - 系統載入 Flutter runtime 並執行 `main.dart`

2. **初始化視窗**
   - app 呼叫 `windowManager.ensureInitialized()`
   - app 完成 frameless / transparent / always-on-top / shadow-off / ignore-mouse-events 屬性設定
   - app 設定視窗尺寸為主螢幕尺寸並定位至 `(0, 0)`

3. **顯示遮罩**
   - app 呼叫 `windowManager.show()`
   - 螢幕上出現透明全螢幕遮罩
   - 中央顯示當前時間（HH:mm:ss）

4. **背景持續更新**
   - 內部 timer 每秒觸發 `setState`，時鐘文字逐秒更新
   - 使用者可繼續操作底下的任何應用，遮罩不阻擋任何輸入

## 替代場景

### 01a: 螢幕解析度於啟動時為非預期值

**觸發條件**：主螢幕尺寸取得失敗或回傳異常值（如 0×0）

1. app 偵測尺寸 ≤ 0
2. fallback 套用 1920×1080
3. 記錄 stderr warning
4. 回到主要場景步驟 3

### 01b: 已有同 app instance 在執行

**觸發條件**：使用者重複啟動 app

1. macOS 對單 instance app 通常會帶回前一個 instance
2. 不建立新視窗
3. （MVP 不主動處理；依 macOS 預設行為）

## 例外場景

### EX-01-01: `window_manager` 初始化失敗

| 項目 | 值 |
|------|-----|
| 觸發條件 | `windowManager.ensureInitialized()` 拋出例外 |
| 錯誤碼 | E_WM_INIT |
| 處理方式 | log 例外訊息到 stderr 並 `exit(1)` |
| 使用者提示 | 無 GUI 提示；只 stderr（MVP 階段不做錯誤 UI） |
| 恢復策略 | 使用者需從 console 查看錯誤；重新啟動 |

### EX-01-02: macOS 原生 Swift 設定未生效

| 項目 | 值 |
|------|-----|
| 觸發條件 | `MainFlutterWindow.swift` 未設定 `isOpaque = false` 或被覆寫 |
| 錯誤碼 | — |
| 處理方式 | 視窗呈現白底；app 仍可運作但失去透明效果 |
| 使用者提示 | 無 |
| 恢復策略 | 開發者需檢查 Swift 設定；屬建置層問題 |

### EX-01-03: click-through 在當前 macOS 版本不支援

| 項目 | 值 |
|------|-----|
| 觸發條件 | `setIgnoreMouseEvents(true)` 在某 macOS 版本失效 |
| 錯誤碼 | E_CLICK_THROUGH |
| 處理方式 | log warning；app 繼續運作；遮罩變成會吃滑鼠事件 |
| 使用者提示 | 無 |
| 恢復策略 | 使用者 Cmd+Q 退出；屬框架相容性問題 |

## 驗收條件

### 功能驗收

- [ ] 啟動後 1.5 秒內遮罩可見
- [ ] 視窗背景完全透明
- [ ] 時鐘文字立即顯示當前時間
- [ ] 60 秒內時鐘逐秒更新
- [ ] 替代場景 01a 可正常 fallback
- [ ] 例外場景皆有對應的 log 訊息（即使無 GUI 提示）

### 邊界條件

- [ ] 多螢幕設定下，遮罩位於 macOS 預設主螢幕
- [ ] 切換螢幕解析度後 app 重啟可正確貼合新尺寸
- [ ] 啟動時系統時區為 UTC 或非預設時區時，時鐘仍顯示正確本機時間

### 效能要求

| 指標 | 目標值 |
|------|--------|
| 啟動到視窗可見 | < 1500 ms（release build） |
| 啟動到時鐘文字出現 | < 200 ms 之後 |
| 啟動後 CPU 平均使用率 | < 1%（M1+，閒置 5 分鐘） |

## UI 互動流程

```
[Launchpad 雙擊圖示]
          │
          ▼
[Flutter runtime 載入]
          │
          ▼
[window_manager 初始化]
          │
          ▼
[屬性設定: frameless/transparent/AOT/no-shadow/ignore-mouse]
          │
          ▼
[setSize + setPosition]
          │
          ▼
[show()] ────► [遮罩可見] ────► [Center Clock 立即顯示時間]
                                          │
                                          ▼
                                  [Timer 每秒更新]
```

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

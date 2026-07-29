---
id: SPEC-001
title: "透明全螢幕遮罩視窗"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: platform
subdomain: window

related_usecases:
  - UC-01
  - UC-02
  - UC-03
related_specs:
  - SPEC-002
implements_requirements:
  - PROP-001 In Scope（macOS 全螢幕透明 / click-through / always-on-top）
depends_on_domains: []
---

# SPEC-001: 透明全螢幕遮罩視窗

## 概述

定義 screen_clock 主視窗在 macOS 上的所有平台層屬性：全螢幕覆蓋主螢幕、背景真透明、無邊框、無陰影、永遠置頂、滑鼠/鍵盤事件完全穿透。Windows 平台行為列為 NFR-02 的後續版本目標，不在本規格的當前版本實作範圍內。

## 功能需求

### FR-01: 全螢幕覆蓋主螢幕

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：app 啟動後，遮罩視窗自動覆蓋整個主螢幕（包含 menu bar 範圍與 dock 範圍）。

**約束條件**：

- 視窗尺寸 = 主螢幕的 visibleFrame（包含 menu bar 與 dock）
- 視窗位置 = `(0, 0)`（螢幕左上角，macOS 座標）
- 螢幕解析度變更時，視窗應跟隨變更

**驗收標準**：

- [ ] 啟動後遮罩涵蓋整個主螢幕視覺範圍
- [ ] 切換螢幕解析度後，遮罩重新貼合新尺寸
- [ ] 多螢幕設定下，遮罩位於 macOS 預設的主螢幕

---

### FR-02: 真透明背景

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：視窗背景應為真透明（alpha=0），不是半透明、不是單色填充。

**約束條件**：

- Flutter 端：`MaterialApp` / `Scaffold` 的 `backgroundColor` 設 `Colors.transparent`
- Flutter 端：`windowManager.setBackgroundColor(Colors.transparent)`
- macOS 平台層：`MainFlutterWindow.swift` 需設定 `self.isOpaque = false; self.backgroundColor = .clear`
- 缺平台層設定時，視窗會呈現為白底；缺 Flutter 層設定時，視窗會呈現為單色

**驗收標準**：

- [ ] 啟動後肉眼看到桌布與所有底層視窗
- [ ] 截圖 app 視窗區域，pixel 透明度為 0
- [ ] 移除 Swift 設定可重現「白底」回歸測試

---

### FR-03: 無邊框、無陰影

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：視窗無 title bar、無視窗控制按鈕（紅黃綠燈）、無陰影。

**約束條件**：

- `windowManager.setAsFrameless()` 必須在 `show()` 之前呼叫
- `windowManager.setHasShadow(false)` 必須呼叫，預設陰影會在透明視窗外緣產生灰邊

**驗收標準**：

- [ ] 視窗無任何可見邊框或標題列
- [ ] 視窗邊緣無陰影殘留

---

### FR-04: 永遠置頂

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：遮罩視窗始終位於所有應用視窗之上，包含全螢幕應用。

**約束條件**：

- `windowManager.setAlwaysOnTop(true)` 啟動時呼叫
- 全螢幕應用（如 Keynote 播放）的 z-order 行為以 macOS 預設規則為準，本規格不要求覆蓋全螢幕應用

**驗收標準**：

- [ ] 開啟其他一般視窗後，時鐘仍可見
- [ ] 切換 desktop（Spaces）後，時鐘隨之顯示或隱藏（依 macOS 預設行為）

---

### FR-05: 滑鼠事件 click-through

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-02 |

**描述**：所有滑鼠事件（點擊、拖曳、捲動、hover）都應穿透遮罩到底下的視窗。

**約束條件**：

- `windowManager.setIgnoreMouseEvents(true)` 啟動後立即呼叫
- MVP 版本不支援部分區域可互動；全視窗統一穿透

**驗收標準**：

- [ ] 點擊遮罩任何位置可命中底下視窗
- [ ] 可拖曳檔案到底下視窗
- [ ] 可在底下視窗捲動內容
- [ ] hover 提示框正常顯示在底下視窗

---

### FR-06: 鍵盤焦點不被攔截

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-02 |

**描述**：app 啟動後不主動搶奪鍵盤焦點，使用者可繼續使用上一個 active 應用。

**約束條件**：

- 視窗不應為 key window（macOS 概念）
- 啟動時不主動呼叫 `activate()` / 不搶 focus

**驗收標準**：

- [ ] 啟動 app 時，前一個 active 應用仍保有鍵盤焦點
- [ ] 切換視窗時 Cmd+Tab 列表中 app 仍可見並可被選中（不強求，視 macOS 行為）

---

## 非功能需求

### NFR-01: 啟動時間

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | 啟動到視窗可見 < 1500ms（macOS） |

**描述**：從 app 啟動到遮罩出現在螢幕上的延遲應 < 1.5 秒（debug build < 3 秒）。

---

### NFR-02: 跨平台目標

| 項目 | 值 |
|------|-----|
| 類型 | 相容性 |
| 指標 | v1.0 前 macOS 唯一支援平台；Windows 為 v1.1.x 起始 |

**描述**：Windows 平台的等價實作（layered window `WS_EX_LAYERED | WS_EX_TRANSPARENT`）推遲到 v1.1.x，由獨立提案推進。v1.0 之前所有 spec 與決策不考慮 Windows 相容性。

---

## 介面規格

### 啟動流程介面

```dart
Future<void> initOverlayWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow();
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setHasShadow(false);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setIgnoreMouseEvents(true);
  await windowManager.setSize(primaryDisplaySize);
  await windowManager.setPosition(const Offset(0, 0));
  await windowManager.show();
}
```

呼叫順序約束：`ensureInitialized()` → `waitUntilReadyToShow()` → 屬性設定 → `show()`。

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| `window_manager` 初始化失敗 | E_WM_INIT | log 並 exit(1) | 無 GUI；只 stderr |
| 主螢幕尺寸取得失敗 | E_SCREEN_SIZE | fallback 1920×1080 | 無 GUI；只 stderr |
| `setIgnoreMouseEvents` 在當前 macOS 版本不支援 | E_CLICK_THROUGH | log warning 並繼續（遮罩變成可點擊但仍透明） | 無 GUI；只 stderr |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| 必須有 macOS 原生 Swift 修改 | `MainFlutterWindow.swift` 缺 `isOpaque = false` 時，所有 Flutter 層的透明設定都會被白底覆蓋 | 平台原生程式碼是必要組件，不可省略 |
| 必須在 `show()` 前完成所有屬性設定 | `window_manager` 的部分 setter 在 visible 視窗上行為不一致 | 啟動流程必須序列化 |
| MVP 不支援部分區域可互動 | 全視窗統一 click-through；動態切換策略列入未來版本 | UI 不能含可點擊元件 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

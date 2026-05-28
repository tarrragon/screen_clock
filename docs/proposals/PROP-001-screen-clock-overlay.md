---
id: PROP-001
title: "桌面螢幕透明時鐘遮罩"
status: draft
source: development
proposed_by: tarrragon
proposed_date: "2026-05-29"
confirmed_date: null
target_version: v0.1.0
priority: P0
evaluation_level: standard

outputs:
  spec_refs:
    - spec/platform/transparent-overlay-window.md
    - spec/display/center-clock.md
  usecase_refs:
    - usecases/UC-01-launch-overlay-clock.md
    - usecases/UC-02-click-through-interaction.md
    - usecases/UC-03-exit-overlay.md
  ticket_refs: []

related_proposals: []
supersedes: null
---

# PROP-001: 桌面螢幕透明時鐘遮罩

## 需求來源

開發者個人需求：在桌面工作時希望螢幕角落或中央能持續顯示時間，但又不希望覆蓋層阻擋滑鼠點擊、鍵盤焦點、視窗操作等任何底層互動。市面上的時鐘 widget 多為小視窗，無法做到全螢幕透明 + click-through 並存。

## 問題描述

要做出「視覺上覆蓋整個螢幕、但行為上等於不存在」的視窗，需同時滿足三個條件：

1. 視窗背景必須是真正透明（非半透明、非單色）
2. 視窗不能接收任何滑鼠/鍵盤事件（穿透至下方視窗）
3. 視窗必須持續在最上層

Flutter 桌面框架本身不直接提供 click-through API，需透過 `window_manager` 套件 + 平台原生程式碼補足。macOS 路徑成熟，Windows 需處理 layered window 旗標，風險不等。

## 影響範圍

| 影響項目 | 說明 |
|---------|------|
| 模組 | `lib/main.dart`（啟動流程）、未來時鐘 widget 模組 |
| 檔案 | `pubspec.yaml`、`macos/Runner/MainFlutterWindow.swift`、`windows/runner/` |
| 用例 | UC-01/02/03（皆為本提案直接衍生） |
| 平台 | macOS（v1.0 唯一支援平台；Windows 推遲到 v1.1.x） |

## 範圍界定

### 本提案要做的（In Scope）

- macOS 平台的全螢幕透明、無邊框、無陰影、置頂視窗
- macOS 平台的 click-through（`setIgnoreMouseEvents(true)`）
- 螢幕中央顯示當前時間（HH:mm 或 HH:mm:ss）
- 時間每秒自動更新
- 啟動後直接進入遮罩狀態（無設定 UI）
- 透過 macOS 標準快捷鍵（Cmd+Q）退出

### 本提案不做的（Out of Scope）

- Windows 平台實作 → 留待 v1.1.x（屆時另立提案 PROP-XXX）。v1.0 之前不考慮 Windows，所有設計決策可暫不考慮 Windows 相容性
- 多螢幕選擇（指定要在哪一個螢幕顯示遮罩）→ MVP 預設使用主螢幕；多螢幕支援獨立提案
- 字型、顏色、位置、透明度的使用者設定 UI → MVP 寫死預設值；設定面板獨立提案
- 開機自動啟動 → 獨立提案
- 點擊穿透與互動區動態切換（部分區域可點、部分穿透）→ 目前全穿透；切換策略列在 CLAUDE.md 但非本版本需求
- 國際化、多時區、12 小時制切換 → MVP 跟隨系統時區與系統 locale

## 提案方案

採用 `window_manager` 套件統一跨平台視窗 API，配合 macOS 平台原生 Swift 程式碼補足真正的透明背景：

| 層級 | 工具 | 負責 |
|------|------|------|
| Flutter 層 | `window_manager` 套件 | frameless、always-on-top、ignore-mouse-events、background-color、has-shadow |
| macOS 平台層 | `MainFlutterWindow.swift` | `isOpaque = false; backgroundColor = .clear`（讓真正透明生效） |
| UI 層 | Flutter widget | 中央時鐘顯示（`Center` + `Text` + `Timer.periodic`） |

### 替代方案

| 面向 | 方案 A: 純 Flutter 視窗 | 方案 B: window_manager + 原生補強 |
|------|----------------|--------------------------|
| 優點 | 不需平台原生程式碼 | 真正透明、跨平台 API 一致 |
| 缺點 | 無法 click-through、無法真透明 | 需碰 Swift（macOS）、未來碰 Win32（Windows） |
| 工時 | — | macOS 約 0.5 天 |
| 備選方案 C | 用 macOS 原生 Cocoa app + 嵌入 Web View 顯示時鐘 | 完全跳離 Flutter，但放棄跨平台路徑 |

### 失敗防護

當任一假設不成立時的退路：

- 假設 1 不成立（click-through 失效）：改用螢幕角落小視窗 + 不阻擋（縮回 menu bar 風格），放棄全螢幕方案
- 假設 2 不成立（透明失效）：改採半透明（alpha 0.05）讓底下視覺仍可見，犧牲純粹透明
- 假設 3 不成立（CPU 過高）：把更新頻率降到每分鐘或改用系統時鐘 widget 而非 Flutter widget
- 假設 4 不成立（系統視窗管理異常）：放棄 always-on-top，改 Cmd+Tab 可呼出/隱藏

### 建議方案

採用方案 B（`window_manager` + macOS 原生補強）。Windows 留待後續提案處理。

## 驗收條件

- [ ] 啟動 app 後，macOS 主螢幕顯示一層覆蓋全螢幕的視窗
- [ ] 該視窗背景肉眼完全透明（看得到底下桌布與所有視窗）
- [ ] 螢幕中央顯示當前時間且每秒更新
- [ ] 滑鼠在遮罩任何位置點擊都會穿透到底下視窗（可拖曳檔案、可點 Dock、可點視窗）
- [ ] 鍵盤事件不被遮罩攔截（可正常打字、切換視窗）
- [ ] 遮罩始終在所有應用視窗之上
- [ ] Cmd+Q 可正常退出 app

## Reality Test / 觸發案例實證

### 觸發案例

開發者使用 macOS 時想在不切換桌面/spaces、不開啟額外視窗的情況下持續看到時間。Menu bar 的時鐘需要視線移到角落且字小；小型 widget 又會擋住下方視窗。

### 假設列舉

- 假設 1：`window_manager.setIgnoreMouseEvents(true)` 在 macOS 上能讓滑鼠事件完整穿透到下方視窗
- 假設 2：`MainFlutterWindow.swift` 設定 `isOpaque = false; backgroundColor = .clear` 後，Flutter 端 `Colors.transparent` 才會呈現為真透明
- 假設 3：每秒更新時間的 widget 對 CPU 與電池影響可忽略
- 假設 4：全螢幕透明視窗不會被 macOS 系統視為可疑（不會被 Mission Control / Stage Manager 異常處理）

### 實驗驗證

| 假設 | 驗證方式 | 執行的實驗/觀察 | 結果 |
|------|---------|----------------|------|
| 假設 1 | 撰寫最小範例執行於 macOS 並嘗試點擊底下視窗 | 待 v0.1.0 驗證 | pending |
| 假設 2 | 移除 Swift 設定觀察是否變回白底 | 待 v0.1.0 驗證 | pending |
| 假設 3 | 觀察 CPU usage 與 Activity Monitor | 待 v0.1.0 驗證 | pending |
| 假設 4 | 在 Mission Control / Stage Manager 切換中觀察視窗行為 | 待 v0.1.0 驗證 | pending |

### 已驗證 vs 未驗證

| 類別 | 內容 |
|------|------|
| 已驗證 | （暫無；MVP 開發過程中逐步驗證） |
| 未驗證 | 假設 1–4 均屬風險，需於 v0.1.0 實作中以最小範例驗證後再展開完整實作 |

---

## 風險與權衡

| 風險 | 影響 | 緩解措施 |
|------|------|---------|
| macOS 系統更新影響原生 API 行為 | 視窗可能不再透明或 click-through 失效 | 鎖定 `window_manager` 版本；每次 macOS 大版本更新後跑驗收清單 |
| 全螢幕透明視窗被系統 anti-screenshot 機制干擾 | 截圖或螢幕錄影可能顯示異常 | 屬未驗證假設；v0.1.0 中驗證 |
| 持續每秒重繪 widget 造成電力消耗 | 筆電耗電 | 採 `Timer.periodic` 配合 `setState` 只重繪時鐘子樹，避免整窗重繪 |

## 討論記錄

### 2026-05-29

- 跟 Claude 於 5/28 對話確認 `window_manager` + 原生 Swift 為可行路徑
- 確認 MVP 只做 macOS、單螢幕、預設樣式
- 同意 Windows 拆為獨立提案

## 轉化記錄

| 轉化類型 | 檔案 | 日期 | 狀態 |
|---------|------|------|------|
| 規格 | spec/platform/transparent-overlay-window.md | 2026-05-29 | created |
| 規格 | spec/display/center-clock.md | 2026-05-29 | created |
| 用例 | usecases/UC-01-launch-overlay-clock.md | 2026-05-29 | created |
| 用例 | usecases/UC-02-click-through-interaction.md | 2026-05-29 | created |
| 用例 | usecases/UC-03-exit-overlay.md | 2026-05-29 | created |
| Ticket | — | — | pending |

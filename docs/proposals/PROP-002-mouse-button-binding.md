---
id: PROP-002
title: "滑鼠按鍵綁定（拖曳滾動與快捷鍵）"
status: draft
source: development
proposed_by: tarrragon
proposed_date: "2026-06-15"
confirmed_date: null
target_version: v1.3.0
priority: P1
evaluation_level: standard

outputs:
  spec_refs:
    - spec/input/mouse-button-binding.md
  usecase_refs:
    - usecases/UC-04-bind-drag-to-scroll.md
    - usecases/UC-05-bind-mouse-button-hotkey.md
  ticket_refs: []

related_proposals: []
supersedes: null
---

# PROP-002: 滑鼠按鍵綁定（拖曳滾動與快捷鍵）

## 需求來源

開發者的滑鼠滾輪硬體損壞，捲動功能不可用。市面上有 macOS app 可把滑鼠按鍵映射為鍵盤快捷鍵，但開發者需要更特別的能力：**按住滑鼠側鍵後，以滑鼠的垂直位移模擬滾輪捲動**，等於用「拖動」取代「滾動」。

screen_clock 已是常駐選單列 app（LSUIElement，隨開機啟動），開發者希望把這個能力併入既有 app，而非再安裝一支獨立工具。

## 問題描述

要在不依賴實體滾輪的前提下提供捲動與按鍵映射，需同時滿足四個條件：

1. **全域攔截**特定滑鼠按鍵的按下 / 放開與滑鼠移動，且不限於本 app 視窗（本 app 視窗為 click-through 透明遮罩，不接收滑鼠事件）。
2. 在按住期間把**垂直位移轉換為滾輪事件**，注入到游標下方的目標 app。
3. 同一套機制也要能把按鍵映射為**鍵盤快捷鍵**（合成鍵盤事件）。
4. 讓使用者在**設定面板自訂**哪一顆實體鍵綁哪個動作，且綁定要能持久化。

Flutter 桌面框架本身不提供全域輸入攔截，也不提供系統層事件合成，必須以 macOS 原生 `CGEventTap` + `CGEvent` 合成補足。且全域監聽與事件合成需要「輔助使用（Accessibility）」權限，此權限與 **App Sandbox 互斥**——目前專案 entitlements 為 `app-sandbox = true`，必須關閉。

## 影響範圍

| 影響項目 | 說明 |
|---------|------|
| 模組 | 新增 Dart `lib/input/` domain（綁定模型、動作型別、控制器）；新增原生 event tap 模組 |
| 檔案 | `macos/Runner/*.entitlements`（移除 sandbox）、`Info.plist`、`MainFlutterWindow.swift`、`models/settings_model.dart`（schema 升版）、`services/settings_service.dart`、`widgets/settings_panel.dart` |
| 用例 | UC-04（綁定拖曳滾動）、UC-05（綁定按鍵快捷鍵），皆本提案直接衍生 |
| 平台 | macOS（v1.0 後唯一支援平台；Windows 推遲到 v1.1.x 之後另立提案） |

## 範圍界定

### 本提案要做的（In Scope）

- **滑鼠按鍵綁定 domain**：一筆綁定 = `實體滑鼠按鍵 → 動作`；架構支援任意數量綁定，動作型別可擴充。
- **動作①拖曳滾動**：按住綁定鍵 → 以垂直位移合成滾輪事件 → 一律吃掉該鍵原本的上一頁 / 下一頁動作。方向預設「往下拖 = 頁面往下捲」，垂直 only。
- **動作②綁定快捷鍵**：按一下綁定鍵 → 合成對應的鍵盤組合鍵（如 Cmd+C）。
- **設定面板整合**：綁定動態清單（新增 / 刪除）、偵測捕捉模式（實際按下滑鼠鍵 / 鍵盤組合鍵自動填入）、動作參數（滾動方向、靈敏度）。
- **持久化**：綁定設定寫入既有 `SettingsModel`（schema 升版，向後相容）。
- **macOS「輔助使用」權限**檢查與引導；未授權時功能安全停用。
- **關閉 App Sandbox**，調整 entitlements。

### 本提案不做的（Out of Scope）

- Windows 平台 → v1.1.x 之後另立提案；本版所有設計可暫不考慮 Windows。
- **水平拖曳滾動** → 本版只做垂直；水平軸屬未來擴充項。
- **進階動作類型**（巨集、連發、應用程式特定設定檔）→ domain 預留擴充點，不在本版實作範圍。
- **動量 / 慣性滾動曲線** → 本版採線性位移對應；動量曲線屬未來擴充項。
- **設定面板以外的綁定設定方式**（CLI 引數、設定檔手編）→ 不做。

## 提案方案

以 macOS 原生 `CGEventTap` 為核心，攔截滑鼠側鍵與移動、合成滾輪與鍵盤事件，並沿用專案既有的 `FlutterMethodChannel` 模式橋接原生與 Dart：

| 層級 | 工具 | 負責 |
|------|------|------|
| macOS 平台層 | `CGEventTap` + `CGEvent`（scroll / keyboard） | 全域攔截側鍵 / 移動 / 放開、合成滾輪與鍵盤事件、吃掉被綁定鍵的原動作 |
| 權限層 | `AXIsProcessTrusted()` + 移除 `app-sandbox` | 取得並檢查「輔助使用」授權 |
| 橋接層 | `FlutterMethodChannel` | 原生 ↔ Dart：傳遞綁定設定、回報捕捉到的按鍵、回報權限狀態、進入 / 離開捕捉模式 |
| Dart domain 層 | `lib/input/` | 綁定模型、動作型別、綁定控制器、與 SettingsModel 整合 |
| UI 層 | `SettingsPanel` | 綁定清單、偵測捕捉互動、動作參數調整 |

### 替代方案

| 面向 | 方案 A：純 Flutter（RawKeyboard / Listener） | 方案 B：原生 CGEventTap + 事件合成 |
|------|----------------------------------------------|------------------------------------|
| 全域攔截 | 只在 app 聚焦時收得到事件，無法全域 | 系統層攔截，與聚焦無關 |
| 合成滾輪 | 無法合成系統滾輪事件 | `CGEventCreateScrollWheelEvent` 可注入 |
| 吃掉原動作 | 做不到 | event tap 回呼回傳 `nil` 即消費事件 |
| 權限 / sandbox | 不需特殊權限 | 需輔助使用 + 關閉 sandbox |
| 結論 | 不可行（無法滿足核心需求） | 採用 |

備選方案 C：直接用既有第三方工具（Mac Mouse Fix / BetterMouse 等）。放棄自建，但與「併入既有常駐 app、自訂拖曳滾動」的需求不符，故不採。

### 失敗防護

當任一假設不成立時的退路：

- 假設 1 不成立（`CGEventTap` 無法攔截 `otherMouseDown` 側鍵）：退路改用 `NSEvent` 全域監聽（只能觀察、不能吃掉原動作），並在面板提示此限制。
- 假設 2 不成立（合成滾輪事件不被目標 app 接受）：退路改用 line-based 滾輪單位，或以鍵盤 Page Up / Down 模擬。
- 假設 3 不成立（移除 sandbox + 輔助使用授權不可行）：退路提供清楚的手動授權引導；授權被拒時功能停用，**不影響 app 其餘既有功能**。
- 假設 4 不成立（吃掉原動作造成系統輸入異常）：退路改為不消費原事件 + 在面板建議使用者選擇不常用的鍵當觸發鍵。

### 建議方案

採方案 B（原生 `CGEventTap` + 事件合成）。Windows 留待後續提案處理。

## 驗收條件

- [ ] 設定面板可新增 / 刪除綁定；偵測捕捉模式能正確抓到滑鼠側鍵與鍵盤組合鍵
- [ ] 綁定「拖曳滾動」的鍵：按住並垂直拖動時，游標下方視窗內容隨之捲動（往下拖 = 往下捲）
- [ ] 按住拖曳期間，該鍵原本的上一頁 / 下一頁動作不觸發
- [ ] 綁定「快捷鍵」的鍵：按一下能送出對應組合鍵（如綁 Cmd+C 可複製選取內容）
- [ ] 重啟 app 後綁定設定完整保留
- [ ] 未授予「輔助使用」權限時，面板顯示授權引導，且功能安全停用、app 不崩潰
- [ ] 移除 App Sandbox 後，既有功能（透明遮罩、開機啟動、選單列、假全螢幕讓位）全部正常

## Reality Test / 觸發案例實證

### 觸發案例

開發者滑鼠滾輪硬體損壞，網頁與文件無法捲動。既有 screen_clock 為常駐選單列 app，開發者希望直接在此 app 內以「按住側鍵拖動」取代滾輪，並順帶把其他側鍵映射為常用快捷鍵。

### 假設列舉

- 假設 1：`CGEventTap` 能攔截滑鼠側鍵（`otherMouseDown` / `otherMouseUp`，buttonNumber ≥ 3）與 `mouseMoved` / `otherMouseDragged`。
- 假設 2：`CGEventCreateScrollWheelEvent` 合成的滾輪事件能被一般 app（瀏覽器、文件）正確接收並捲動。
- 假設 3：移除 `app-sandbox` 後，app 能被加入系統「輔助使用」清單並取得授權，`CGEventTap` 得以建立。
- 假設 4：event tap 回呼回傳 `nil` 消費被綁定鍵的事件，不會造成系統滑鼠輸入異常或卡住。

### 實驗驗證

| 假設 | 驗證方式 | 執行的實驗 / 觀察 | 結果 |
|------|---------|------------------|------|
| 假設 1 | 最小 spike：建立 event tap 印出側鍵與移動事件 | 待 v1.3.0 W1 spike | pending |
| 假設 2 | spike 中合成滾輪事件，觀察瀏覽器是否捲動 | 待 v1.3.0 W1 spike | pending |
| 假設 3 | 移除 sandbox，於系統設定授權後測 tap 建立 | 待 v1.3.0 W1 spike | pending |
| 假設 4 | 消費側鍵事件後實機操作，確認無輸入異常 | 待 v1.3.0 W1 spike | pending |

### 已驗證 vs 未驗證

| 類別 | 內容 |
|------|------|
| 已驗證 | （暫無；需於 v1.3.0 W1 spike 逐項驗證後再展開完整實作） |
| 未驗證 | 假設 1–4 均屬風險，需先以最小 spike 驗證可行性，再進入 TDD 實作 |

## 風險與權衡

| 風險 | 影響 | 緩解措施 |
|------|------|---------|
| 移除 App Sandbox | 無法上架 Mac App Store | 屬個人常駐工具，自簽散佈可接受 |
| 輔助使用授權於重新簽章 / 改路徑後失效 | 開發期需重複授權；使用者升級後可能要重授 | 使用穩定簽章；面板提供授權狀態與引導；文件記錄 |
| 全域事件攔截效能 | event tap 回呼阻塞 HID 會拖慢全系統滑鼠 | 回呼內只算 delta + post event，重邏輯移出回呼；不取 window title 等高成本資訊 |
| 合成滾輪相容性 | 少數 app 對合成事件反應不一致 | 預留 line / pixel 滾輪單位切換（未來擴充）；spike 先驗證主流瀏覽器 |
| 吃掉原動作影響既有操作 | 綁定常用鍵可能誤傷原功能 | 一律吃掉為使用者明確選擇；面板提示挑選不常用鍵 |

## 討論記錄

### 2026-06-15

- 與 Claude 對話確認需求範圍：
  - 做成獨立的「滑鼠按鍵綁定」domain，架構支援任意數量綁定，本版先支援設定兩組。
  - 本版實作兩種動作類型：拖曳滾動 + 綁定快捷鍵。
  - 按住拖曳期間一律吃掉原本的上一頁 / 下一頁動作。
  - 設定面板採偵測捕捉模式指定按鍵；參數一開始就可調。
  - 拖曳滾動方向預設「往下拖 = 頁面往下捲」，垂直 only。
  - 目標版本 v1.3.0，macOS only。

## 轉化記錄

| 轉化類型 | 檔案 | 日期 | 狀態 |
|---------|------|------|------|
| 規格 | spec/input/mouse-button-binding.md | 2026-06-15 | created |
| 用例 | usecases/UC-04-bind-drag-to-scroll.md | — | pending |
| 用例 | usecases/UC-05-bind-mouse-button-hotkey.md | — | pending |
| Ticket | — | — | pending |

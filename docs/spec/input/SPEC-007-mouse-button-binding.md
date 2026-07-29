---
id: SPEC-007
title: "滑鼠按鍵綁定 domain"
status: draft
source_proposal: PROP-002
created: "2026-06-15"
updated: "2026-06-15"
version: "1.0"
owner: tarrragon

domain: input
subdomain: mouse-binding

related_usecases:
  - UC-04
  - UC-05
related_specs:
  - SPEC-004
  - SPEC-005
implements_requirements:
  - PROP-002
depends_on_domains:
  - data-management
  - user-experience
---

# SPEC-007: 滑鼠按鍵綁定 domain

## 概述

定義 screen_clock v1.3.0 的「滑鼠按鍵綁定」能力：把實體滑鼠按鍵綁定為一個動作（拖曳滾動 / 快捷鍵），由原生 `CGEventTap` 全域攔截並合成系統事件。本規格涵蓋綁定資料模型、事件攔截基礎建設、兩種動作、偵測捕捉、權限處理與設定面板整合。

底層原生機制屬 macOS 平台；本規格只定義行為契約與資料模型，Swift 實作細節於 Phase 3 規劃。

## 架構決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 攔截 / 合成機制 | macOS 原生 `CGEventTap` + `CGEvent` | Flutter 無法全域攔截或合成系統事件 |
| App Sandbox | **關閉**（`app-sandbox` 移除） | 輔助使用權限與 sandbox 互斥；event tap 需此權限 |
| 權限模型 | 「輔助使用（Accessibility）」 | `CGEventTap` 監聽 / 消費全域事件的前提 |
| 原生 ↔ Dart 橋接 | `FlutterMethodChannel` | 沿用專案既有模式（launch_at_startup / fullscreen_detect） |
| 綁定持久化 | 併入既有 `SettingsModel` + `shared_preferences` | 與 SPEC-004 一致，避免新增儲存層 |
| 動作型別 | 可擴充（actionType 標籤 + 參數） | PROP-002 要求 domain 預留擴充 |

> method channel 名稱、方法名、參數鍵等固定字串依 CLAUDE.md 常數集中規範，集中於 `lib/app_constants.dart`（新增 `AppInputBinding` 類），且須與 Swift 端字面一致。

## 功能需求

### FR-01: 綁定資料模型

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：定義一筆綁定與其動作的資料模型。

**模型**：

- `MouseBinding`：`buttonNumber`（int，實體滑鼠按鍵編號，如 3 / 4）+ `action`（`MouseAction`）。
- `MouseAction`：可擴充型別，以 `actionType` 區分：
  - `DragScrollAction`：`direction`（`ScrollDirection`：`natural` = 往下拖往下捲 / `inverted`）、`sensitivity`（double，位移到滾輪量的倍率）。
  - `HotkeyAction`：`keyCode`（int，實體鍵碼）+ `modifiers`（修飾鍵集合，如 cmd / shift / alt / ctrl）。

**約束條件**：

- 同一 `buttonNumber` 在綁定清單中唯一（後設覆蓋前設，或面板層阻擋重複）。
- 所有欄位 non-null；動作參數有預設值。
- 不可變（immutable）；變更透過 `copyWith`。

**驗收標準**：

- [ ] `DragScrollAction` 預設 `direction = natural`、`sensitivity` 為中等預設值
- [ ] `HotkeyAction` 能表達含多個修飾鍵的組合（如 Cmd+Shift+4）
- [ ] 綁定清單對重複 `buttonNumber` 有明確去重規則

---

### FR-02: 綁定序列化與持久化

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：綁定清單併入 `SettingsModel`，沿用 SPEC-004 的 `toJson` / `fromJson` 容錯往返與 `shared_preferences` 儲存。

**約束條件**：

- `SettingsModel` 新增 `bindings`（`List<MouseBinding>`），`schemaVersion` 由 2 升為 **3**。
- `toJson()`：`bindings` 序列化為 `List<Map<String, Object>>`，僅含原生型別。
- `fromJson()`：缺 `bindings` 欄（舊版 v2 資料）→ 空清單；單筆綁定型別錯誤 → 略過該筆，不拋例外。
- 向後相容：v2 資料能被 v3 讀取，缺欄補預設。

**驗收標準**：

- [ ] `fromJson(model.toJson()) == model`（含 bindings round-trip）
- [ ] 舊版（無 bindings）資料解析為空綁定清單，app 不崩潰
- [ ] 單筆綁定 JSON 損毀時只略過該筆，其餘綁定與設定不受影響

---

### FR-03: 全域事件攔截（CGEventTap）

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：原生端建立 `CGEventTap`，攔截滑鼠側鍵按下 / 放開、滑鼠移動 / 拖曳事件，依目前綁定清單分派到對應動作。

**約束條件**：

- 攔截事件型別至少含：`otherMouseDown`、`otherMouseUp`、`mouseMoved`、`otherMouseDragged`、`leftMouseDragged`（拖曳期間滑鼠移動可能以 dragged 形式送達）。
- 被綁定鍵的 `otherMouseDown` / `otherMouseUp`：**回呼回傳 `nil` 消費事件**，使原本的上一頁 / 下一頁不觸發（PROP-002：一律吃掉原動作）。
- 未綁定的按鍵與事件：原樣放行，不影響系統。
- 綁定清單由 Dart 經 method channel 下傳；原生端持有當前快照，變更即更新。
- event tap 生命週期：app 啟動且已授權時建立；授權缺失時不建立並回報 Dart。

**驗收標準**：

- [ ] 綁定鍵被按下 / 放開時，原上一頁 / 下一頁不觸發
- [ ] 未綁定按鍵行為與未安裝本功能時完全相同
- [ ] Dart 更新綁定後，原生端即時套用新綁定（無須重啟）

---

### FR-04: 動作 — 拖曳滾動

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：綁定鍵按住期間，把滑鼠垂直位移轉換為滾輪事件注入游標下方目標 app。

**約束條件**：

- 按下綁定鍵：記錄起始游標 Y、進入拖曳狀態。
- 移動期間：以 `Δy = 當前Y − 上次Y` 乘上 `sensitivity` 合成 `CGEventCreateScrollWheelEvent`（垂直軸）。
- 方向：`natural`（預設）= 往下拖、頁面往下捲（等同一般滾輪往下）；`inverted` 反向。
- 放開綁定鍵：離開拖曳狀態，停止合成。
- 只處理垂直軸；水平位移忽略（本版範圍）。
- 合成事件不得再被本 tap 重複攔截造成迴圈（以事件來源 / 標記排除）。

**驗收標準**：

- [ ] 按住綁定鍵垂直拖動，瀏覽器 / 文件內容捲動，方向符合設定
- [ ] 放開後捲動停止
- [ ] 靈敏度調整能改變單位位移的捲動量
- [ ] 合成滾輪事件不造成攔截迴圈

---

### FR-05: 動作 — 綁定快捷鍵

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：綁定鍵按一下時，合成對應的鍵盤組合鍵事件送往前景 app。

**約束條件**：

- 按下綁定鍵：依 `HotkeyAction` 合成 keyDown（含修飾鍵 flags）+ keyUp。
- 一次按下送一次組合鍵（不連發）。
- 原按鍵動作被消費（FR-03）。

**驗收標準**：

- [ ] 綁 Cmd+C 的鍵按一下，前景 app 收到複製
- [ ] 含多修飾鍵的組合（如 Cmd+Shift+4）能正確送出
- [ ] 按一下只送一次，不重複

---

### FR-06: 偵測捕捉模式

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：設定面板提供「偵測」互動，讓使用者實際按下滑鼠鍵 / 鍵盤組合鍵，由系統自動抓取編號填入，避免使用者手記 button 編號。

**約束條件**：

- 滑鼠鍵捕捉：面板進入捕捉模式 → 原生 event tap 把下一個側鍵 `otherMouseDown` 的 buttonNumber 經 channel 回報 Dart，並消費該次事件（不觸發原動作）。
- 快捷鍵捕捉：面板開啟時已關閉 click-through（見 SPEC-005），可用 Flutter `HardwareKeyboard` / `KeyboardListener` 於聚焦狀態擷取組合鍵，不需原生協助。
- 捕捉有逾時 / 取消機制，逾時回到一般狀態。

**驗收標準**：

- [ ] 進入滑鼠捕捉後按側鍵，面板顯示抓到的按鍵，且該次不觸發原動作
- [ ] 進入快捷鍵捕捉後按組合鍵，面板正確顯示組合
- [ ] 捕捉可取消 / 逾時退出

---

### FR-07: 輔助使用權限檢查與引導

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：功能依賴「輔助使用」權限；未授權時面板顯示狀態與引導，功能安全停用。

**約束條件**：

- 原生端以 `AXIsProcessTrusted()` 查詢授權狀態，經 channel 回報 Dart。
- 未授權：不建立 event tap；面板顯示「需於系統設定 → 隱私權與安全性 → 輔助使用 開啟」引導，並提供開啟系統設定的捷徑（`AXIsProcessTrustedWithOptions` 觸發系統提示）。
- 授權後：建立 event tap，無須重啟 app（或以明確提示要求重啟，二擇一於 Phase 1 定案）。

**驗收標準**：

- [ ] 未授權時面板顯示引導、功能停用、app 不崩潰
- [ ] 授權後功能生效
- [ ] 權限狀態變化能反映於面板

---

### FR-08: 設定面板整合

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-002 |

**描述**：在既有 `SettingsPanel` 新增綁定管理區。

**約束條件**：

- 綁定清單：列出現有綁定（按鍵 + 動作摘要），可新增 / 刪除。本版確保至少 2 筆可正常設定。
- 新增綁定流程：偵測按鍵（FR-06）→ 選動作型別 → 設動作參數（拖曳滾動：方向 / 靈敏度；快捷鍵：捕捉組合鍵）。
- 儲存：寫入 `SettingsModel.bindings`，經 `SettingsController` 持久化並下傳原生端。

**驗收標準**：

- [ ] 可新增、刪除綁定，變更即時持久化
- [ ] 拖曳滾動的方向 / 靈敏度可在面板調整並生效
- [ ] 儲存後綁定下傳原生端，立即生效

---

## 非功能需求

### NFR-01: 事件回呼效能

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | event tap 回呼處理 < 1 ms，不阻塞 HID 事件流 |

**描述**：回呼內僅做按鍵判定、delta 計算與 post event，禁止取 window title、檔案 I/O、同步 channel 等高成本操作。

---

### NFR-02: 權限缺失安全停用

| 項目 | 值 |
|------|-----|
| 類型 | 穩定性 |
| 指標 | 未授權 / event tap 建立失敗時，app 其餘功能（透明遮罩、選單列、開機啟動）完全不受影響 |

---

### NFR-03: 向後相容

| 項目 | 值 |
|------|-----|
| 類型 | 相容性 |
| 指標 | v2 schema（無 bindings）資料能被 v3 正常讀取，缺欄補預設 |

---

## 資料模型（草案，Phase 1 細化）

```dart
enum ScrollDirection { natural, inverted }
enum MouseActionType { dragScroll, hotkey }

@immutable
sealed class MouseAction {
  MouseActionType get type;
  Map<String, Object> toJson();
}

class DragScrollAction extends MouseAction { /* direction, sensitivity */ }
class HotkeyAction extends MouseAction { /* keyCode, modifiers */ }

@immutable
class MouseBinding {
  final int buttonNumber;
  final MouseAction action;
}
```

## 介面規格（method channel 草案）

| 方向 | 方法 | 參數 | 用途 |
|------|------|------|------|
| Dart → 原生 | `updateBindings` | `bindings`（List<Map>） | 下傳當前綁定清單 |
| Dart → 原生 | `queryPermission` | — | 查詢輔助使用授權狀態 |
| Dart → 原生 | `requestPermission` | — | 觸發系統授權提示 |
| Dart → 原生 | `beginCaptureButton` / `endCaptureButton` | — | 進入 / 離開滑鼠鍵捕捉模式 |
| 原生 → Dart | `onButtonCaptured` | `buttonNumber`（int） | 回報捕捉到的側鍵 |
| 原生 → Dart | `onPermissionChanged` | `granted`（bool） | 回報授權狀態 |

> 實際字串常數集中於 `lib/app_constants.dart`，Swift 端字面對齊。

## 錯誤處理

| 錯誤場景 | 處理方式 | 使用者提示 |
|---------|---------|-----------|
| 輔助使用未授權 | 不建立 event tap；面板顯示引導 | 授權引導 |
| event tap 建立失敗 | log + 功能停用，不影響其餘功能 | 面板顯示「功能無法啟用」 |
| 綁定 JSON 單筆損毀 | 略過該筆，其餘照常 | 無 |
| 合成事件被拒 / 無效 | log warning | 無 |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| 回呼輕量 | event tap 回呼在 HID 事件流上 | 重邏輯一律移出回呼 |
| 避免合成迴圈 | 合成事件可能再次進 tap | 以事件來源 / 自訂欄位標記排除 |
| sandbox 移除不可逆於本版 | 既有功能需在非 sandbox 下回歸測試 | 驗收須涵蓋全功能回歸 |
| 常數集中 | 固定字串 / 旗標集中 `app_constants.dart` | 禁硬編碼於 Dart |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-06-15 | 初始版本（PROP-002 衍生） |

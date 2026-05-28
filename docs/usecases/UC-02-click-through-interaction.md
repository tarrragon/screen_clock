---
id: UC-02
title: "在遮罩下繼續操作底下程式"
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
related_usecases:
  - UC-01
ticket_refs: []
---

# UC-02: 在遮罩下繼續操作底下程式

## 基本資訊

| 項目 | 值 |
|------|-----|
| 用例 ID | UC-02 |
| 用例名稱 | 在遮罩下繼續操作底下程式 |
| 主要行為者 | 桌面使用者 |
| 利益關係人 | 使用者：完全不感知遮罩存在；底層應用：照常接收所有輸入 |
| 前置條件 | UC-01 已完成；遮罩可見且 `setIgnoreMouseEvents(true)` 已生效 |
| 成功保證 | 滑鼠、鍵盤、拖曳、捲動全部到達底下應用，無事件被遮罩攔截 |

## 主要成功場景

1. **點擊底下視窗**
   - 使用者在遮罩任意位置點擊
   - macOS 將事件路由到底下視窗（因 `IgnoreMouseEvents` 將遮罩標為非命中目標）
   - 底下視窗 active 並接收 click 事件

2. **拖曳檔案**
   - 使用者從 Finder 拖曳檔案
   - 拖曳軌跡可穿過遮罩
   - 放到底下視窗時被該視窗接收

3. **使用鍵盤輸入**
   - 使用者在底下應用打字
   - 因遮罩 app 不持有 key window 狀態，鍵盤事件直接到底下應用
   - 文字正確輸入到底下應用

4. **捲動內容**
   - 使用者於遮罩任意位置捲動 trackpad / 滑鼠滾輪
   - 捲動事件到達底下視窗
   - 底下視窗內容正確捲動

5. **Hover 操作**
   - 使用者將滑鼠停在底下視窗的可 hover 元素上
   - hover 提示框正常顯示

## 替代場景

### 02a: 同時使用 Mission Control / Spaces

**觸發條件**：使用者按下 F3 / Mission Control 手勢

1. macOS 進入 Mission Control 視圖
2. 遮罩可能變成可見的全螢幕視窗（依 macOS 對 always-on-top 透明視窗的處理）
3. 退出 Mission Control 後遮罩自動回到原狀態
4. （MVP 不主動處理；依 macOS 預設）

### 02b: 切換到全螢幕應用

**觸發條件**：使用者將其他 app 切到全螢幕模式

1. macOS 將全螢幕 app 置於遮罩之上（系統規則覆蓋 always-on-top）
2. 退出全螢幕後遮罩回到最上層
3. （MVP 接受此行為；不違反 SPEC-001 FR-04 的設計約束）

## 例外場景

### EX-02-01: setIgnoreMouseEvents 失效

| 項目 | 值 |
|------|-----|
| 觸發條件 | macOS 版本相容性問題或 `window_manager` 套件 bug 導致 click-through 不生效 |
| 錯誤碼 | E_CLICK_THROUGH |
| 處理方式 | log warning；遮罩變成會接收滑鼠事件並擋住底下視窗 |
| 使用者提示 | 無 GUI |
| 恢復策略 | 使用者 Cmd+Q 退出；本場景視為 MVP 不可接受的 regression |

### EX-02-02: 鍵盤焦點被遮罩搶走

| 項目 | 值 |
|------|-----|
| 觸發條件 | 視窗錯誤地成為 key window |
| 錯誤碼 | E_KEY_WINDOW |
| 處理方式 | log warning；使用者輸入會被遮罩 app 接收（但 app 無輸入處理邏輯，等同丟失） |
| 使用者提示 | 無 |
| 恢復策略 | 使用者切換到目標 app（Cmd+Tab）；本場景視為 MVP 不可接受的 regression |

## 驗收條件

### 功能驗收

- [ ] 點擊遮罩任何位置都能命中底下視窗
- [ ] 可從 Finder 拖曳檔案穿過遮罩到目的 app
- [ ] 在底下 app 打字時鍵盤完全不被遮罩干擾
- [ ] 滾輪 / trackpad 捲動穿透到底下 app
- [ ] hover 提示框於底下 app 正常顯示
- [ ] 60 秒互動測試後遮罩仍維持透明且 click-through

### 邊界條件

- [ ] Mission Control / Stage Manager 切換後遮罩不卡住
- [ ] 全螢幕應用切換後遮罩行為符合 macOS 預設規則
- [ ] 多 desktop 切換時遮罩跟隨主 desktop（依 macOS 預設）

### 效能要求

| 指標 | 目標值 |
|------|--------|
| 滑鼠事件穿透延遲 | 不可感知（< 16 ms） |
| 鍵盤事件延遲 | 與不開 app 時相同（< 1 ms 差異） |

## UI 互動流程

```
[使用者操作 (click/drag/key/scroll)]
              │
              ▼
        [事件抵達 macOS]
              │
              ▼
  ┌───────────┴───────────┐
  │ 遮罩視窗：IgnoreMouseEvents = true │
  │ → 不被視為命中目標            │
  └───────────┬───────────┘
              │
              ▼
        [事件路由到底下視窗]
              │
              ▼
        [底下 app 正常處理]
```

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

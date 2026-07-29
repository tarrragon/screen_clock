---
id: SPEC-003
title: "多螢幕選擇與目標螢幕貼合"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: platform
subdomain: display

related_usecases:
  - UC-01
related_specs:
  - SPEC-001
implements_requirements:
  - PROP-001 後續延伸（v0.3.0 加入多螢幕，原 Out of Scope 第 2 項落地）
depends_on_domains: []
---

# SPEC-003: 多螢幕選擇與目標螢幕貼合

## 概述

定義 screen_clock 在多螢幕環境下的「目標螢幕指定 + 視窗貼合 + 熱插拔處理」行為。MVP 階段透過 CLI 引數 `--screen=N` 指定螢幕索引；設定 UI 在 v1.0.0 再做。本規格延伸 SPEC-001 FR-01 從「主螢幕」到「指定螢幕」。

## 功能需求

### FR-01: 偵測可用螢幕清單

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v0.3.0 延伸 |
| 對應用例 | UC-01 邊界 |

**描述**：app 啟動時可列出所有 macOS 識別的螢幕，含 index、size、position、是否為主螢幕。

**約束條件**：

- 使用 `screen_retriever.getAllDisplays()`
- index 0 為主螢幕（與 macOS Display order 對齊）
- 偵測失敗時清單為空，等同只看到主螢幕（FR-04 fallback）

**驗收標準**：

- [ ] 雙螢幕情境下 `getAllDisplays()` 回傳 2 個元素
- [ ] 主螢幕的 `position` 通常為 `(0, 0)`，第二螢幕視配置而定

---

### FR-02: 透過 CLI 引數指定目標螢幕

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v0.3.0 延伸 |
| 對應用例 | UC-01 |

**描述**：啟動時若帶 `--screen=N`，將遮罩視窗顯示在第 N 個螢幕（0-indexed）。

**約束條件**：

- 引數格式：`--screen=N`（=與數字相連）
- N 必須為非負整數
- 無引數時 → 預設主螢幕（index 0）
- N 超出範圍 → fallback 主螢幕並 log warning（FR-04）

**驗收標準**：

- [ ] `--screen=0` 顯示在主螢幕
- [ ] `--screen=1` 在雙螢幕設定下顯示在第二螢幕
- [ ] `--screen=99` 顯示在主螢幕並 stderr 印出 warning
- [ ] `--screen=abc` 顯示在主螢幕並 stderr 印出 warning（解析失敗）

---

### FR-03: 視窗在指定螢幕的尺寸與位置貼合

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | SPEC-001 FR-01 延伸 |
| 對應用例 | UC-01 |

**描述**：視窗 size 設為目標螢幕的 size；position 設為目標螢幕的 visible position。

**約束條件**：

- 多螢幕座標系於 macOS 可為負數（次要螢幕在主螢幕左側時）
- `windowManager.setPosition` 與 `setSize` 在多螢幕下接受 global 座標

**驗收標準**：

- [ ] 在第二螢幕顯示時，視窗左上角貼合該螢幕原點
- [ ] 視窗尺寸與目標螢幕完全一致

---

### FR-04: 偵測失敗 / 引數錯誤的 fallback

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | SPEC-001 FR-01 替代場景 01a 延伸 |
| 對應用例 | UC-01 替代場景 |

**描述**：當螢幕偵測失敗、目標 index 超範圍、或解析 `--screen=` 失敗時，自動 fallback 到主螢幕並 stderr log warning。app 仍正常啟動。

**約束條件**：

- 不可因 fallback 而 crash
- log 必須包含原因（"display index 99 out of range, fallback to primary"）

**驗收標準**：

- [ ] FR-02 所有錯誤情境皆能 fallback 主螢幕
- [ ] stderr 有 warning 訊息

---

### FR-05: 螢幕熱插拔處理

| 項目 | 值 |
|------|-----|
| 優先級 | P1 |
| 來源 | PROP-001 v0.3.0 延伸 |
| 對應用例 | UC-01 邊界 |

**描述**：app 執行期間若目標螢幕被拔除，視窗自動回到主螢幕；若新增螢幕，不主動切換。

**約束條件**：

- 訂閱 `screenRetriever` 的螢幕變更事件
- 拔除目標螢幕時呼叫 `_coverPrimaryScreen()`
- 新增螢幕只 log，不切換目標

**驗收標準**：

- [ ] 拔除目標螢幕後 1 秒內視窗出現在主螢幕
- [ ] 重新插回原螢幕後不自動切回（使用者需重啟 app）

---

## 非功能需求

### NFR-01: 切換延遲

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | 拔除目標螢幕到視窗轉移主螢幕 < 1000ms |

---

## 介面規格

### DisplayDetector 介面

```dart
class DisplayDetector {
  Future<List<Display>> listDisplays();
  Future<Display> resolveTargetDisplay(int? requestedIndex);
  void startWatching(VoidCallback onTargetLost);
  void stopWatching();
}
```

### CLI 引數解析

```dart
int? parseScreenArg(List<String> args) {
  // 接受 `--screen=N` 格式；無效或缺失回 null
}
```

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| `getAllDisplays` 拋例外 | E_DISPLAY_LIST | 回主螢幕、log | stderr |
| 目標 index 越界 | E_DISPLAY_INDEX | 回主螢幕、log | stderr |
| `--screen=` 解析失敗 | E_DISPLAY_ARG | 回主螢幕、log | stderr |
| 螢幕變更事件處理拋例外 | E_DISPLAY_EVENT | 忽略事件、log | stderr |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| 不引入額外螢幕偵測套件 | 採用 v0.1.0 已加入的 `screen_retriever` | 減少依賴 |
| MVP 不支援即時切換目標螢幕 | 切換目標螢幕需重啟 app | 設定 UI 在 v1.0.0 才做動態切換 |
| 新增螢幕不主動切換 | 避免插入新螢幕時時鐘消失到使用者預期外的位置 | 一致性優於便利性 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

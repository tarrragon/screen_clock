---
id: SPEC-004
title: "使用者設定持久化"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: data-management
subdomain: settings

related_usecases: []
related_specs:
  - SPEC-002
  - SPEC-003
implements_requirements:
  - PROP-001 後續延伸（v1.0.0 設定面板的持久化層）
depends_on_domains:
  - display
---

# SPEC-004: 使用者設定持久化

## 概述

定義 screen_clock v1.0.0 的使用者設定資料模型、儲存方式、讀取/寫入流程、首次啟動與資料損毀的 fallback。本規格只負責資料層；UI 在 SPEC-005、開機啟動在 SPEC-006。

## 儲存方案決策

| 候選方案 | 優點 | 缺點 | 結論 |
|---------|------|------|------|
| `shared_preferences` | Flutter 官方套件、macOS sandbox 相容、輕量 | 只能存原生型別（int / double / String / bool / List<String>） | 採用 |
| JSON 檔案 | 結構彈性大、可手動編輯 | 需處理路徑（`getApplicationSupportDirectory`）、權限、I/O 例外 | 不採用，過度設計 |
| SQLite | 適合大量結構化資料 | 對 < 20 欄位設定過重 | 不採用 |

> Color 在 shared_preferences 中以 ARGB32 int 儲存；其他 enum 用 String name 儲存。

## 功能需求

### FR-01: SettingsModel 資料模型

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 延伸 |

**描述**：定義使用者可設定項目的資料模型。

**欄位**：

| 欄位 | 型別 | 預設值（重現 MVP） | 對應 SPEC |
|------|------|--------------------|-----------|
| `fontSize` | `double` | `AppSizes.clockFontSize` (120) | SPEC-002 FR-04 |
| `fillColor` | `Color` | `AppColors.clockFill` (white) | SPEC-002 FR-04 |
| `strokeColor` | `Color` | `AppColors.clockStroke` (black) | SPEC-002 FR-04 |
| `strokeWidth` | `double` | `AppSizes.clockStrokeWidth` (2) | SPEC-002 FR-04 |
| `timeFormat` | `String` | `AppText.timeFormat` ("HH:mm:ss") | SPEC-002 FR-01 |
| `targetScreenIndex` | `int` | `0` | SPEC-003 FR-02 |
| `autoLaunch` | `bool` | `false` | SPEC-006 |

**約束條件**：

- 不變式：所有欄位 non-null
- 工廠：`SettingsModel.defaults()` 重現 MVP 樣式
- 不可變（immutable）；變更透過 `copyWith`

**驗收標準**：

- [ ] `SettingsModel.defaults()` 對應 v0.x 寫死預設值
- [ ] `copyWith` 不影響原物件

---

### FR-02: 序列化 / 反序列化

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 延伸 |

**描述**：SettingsModel 必須能在 shared_preferences 的原生型別空間中往返。

**約束條件**：

- `toJson()` 回 `Map<String, Object>`，僅含原生型別
- `Color` 透過 `Color.toARGB32() / Color.fromARGB`
- `fromJson(Map)` 容錯：缺欄位用 default；型別錯誤回 default 該欄
- 版本欄位 `schemaVersion` 為 `int`，目前為 `1`，向後相容用

**驗收標準**：

- [ ] `fromJson(model.toJson()) == model`（round-trip）
- [ ] `fromJson({})` 等同 `SettingsModel.defaults()`
- [ ] `fromJson({invalid types})` 不拋例外，回 defaults

---

### FR-03: SettingsService 介面

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 延伸 |

**描述**：抽象的設定讀取/儲存介面，背後實作為 shared_preferences。

**介面**：

```dart
abstract class SettingsService {
  Future<SettingsModel> load();
  Future<void> save(SettingsModel settings);
}
```

**約束條件**：

- `load()` 首次啟動（無存檔）回 defaults
- `load()` 解析失敗回 defaults + log warning
- `save()` 例外被捕捉並 log；不拋給上層

**驗收標準**：

- [ ] 首次啟動讀到 defaults
- [ ] 儲存後重啟讀回相同 model
- [ ] 損毀資料 fallback defaults，app 不 crash

---

### FR-04: 啟動時讀取並套用

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 延伸 |

**描述**：app 啟動時於 `windowManager.show()` 之前讀取設定，把 `targetScreenIndex` 用於螢幕選擇、樣式相關欄位傳給 CenterClock。

**約束條件**：

- CLI `--screen=N` 優先於 SettingsModel.targetScreenIndex
- 樣式注入透過 InheritedWidget / Provider（W2 階段重構）

**驗收標準**：

- [ ] `--screen=` 缺省時用 SettingsModel.targetScreenIndex
- [ ] 重啟 app 後上次儲存的目標螢幕被套用

---

## 非功能需求

### NFR-01: 讀取延遲

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | 啟動時 load() < 100ms（macOS M1+） |

---

### NFR-02: 跨版本相容性

| 項目 | 值 |
|------|-----|
| 類型 | 相容性 |
| 指標 | `schemaVersion` 不同時的處理：未來版本應能讀舊版資料 |

**描述**：MVP 階段只實作 v1 schema。日後加欄位時，舊版資料缺欄補 default 即可；不需 migration。

---

## 資料模型

```dart
class SettingsModel {
  const SettingsModel({
    required this.fontSize,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
    required this.timeFormat,
    required this.targetScreenIndex,
    required this.autoLaunch,
  });

  factory SettingsModel.defaults();
  factory SettingsModel.fromJson(Map<String, dynamic> json);
  Map<String, Object> toJson();

  SettingsModel copyWith({...});
}
```

## 介面規格

詳見 FR-03。

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| shared_preferences 初始化失敗 | E_PREFS_INIT | log + 用記憶體 defaults | 無 |
| 反序列化型別錯誤 | E_PREFS_PARSE | 回 default、log | 無 |
| save() I/O 例外 | E_PREFS_SAVE | log + 維持記憶體狀態 | 無（UI 層可顯示「儲存失敗」） |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| shared_preferences 原生型別限制 | 必須序列化 Color/enum 為 int/String | 設計上以 toJson/fromJson 統一處理 |
| MVP 不做 migration | 加欄位用 default fallback | 設計上禁止刪除欄位、禁止改型別 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

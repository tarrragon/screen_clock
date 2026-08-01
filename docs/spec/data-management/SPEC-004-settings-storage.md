---
id: SPEC-004
title: "使用者設定持久化"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-08-01"
version: "1.1"
owner: tarrragon

domain: data-management
subdomain: settings

related_usecases: []
related_specs:
  - SPEC-002
  - SPEC-003
  - SPEC-009
implements_requirements:
  - PROP-001 後續延伸（v1.0.0 設定面板的持久化層）
depends_on_domains:
  - display
---

# SPEC-004: 使用者設定持久化

## 概述

定義 screen_clock v1.0.0 的使用者設定資料模型、儲存方式、讀取/寫入流程、首次啟動與資料損毀的 fallback。本規格只負責資料層；UI 在 SPEC-005、開機啟動在 SPEC-006。

**與 SPEC-009 分工**：本規格聚焦功能需求——設定面板需要哪些欄位、何時讀取/寫入、fallback 行為；欄位的格式、值域、schema 版本演進與不變式等資料契約細節由 SPEC-009 承載，不在本文件重複，兩份文件互相引用。

## 儲存方案決策

| 候選方案 | 優點 | 缺點 | 結論 |
|---------|------|------|------|
| `shared_preferences` | Flutter 官方套件、macOS sandbox 相容、輕量 | 只能存原生型別（int / double / String / bool / List<String>） | 採用 |
| JSON 檔案 | 結構彈性大、可手動編輯 | 需處理路徑（`getApplicationSupportDirectory`）、權限、I/O 例外 | 不採用，過度設計 |
| SQLite | 適合大量結構化資料 | 對 < 20 欄位設定過重 | 不採用 |

> Color 在 shared_preferences 中以 ARGB32 int 儲存；其他 enum 用 String name 儲存。

**實際儲存格式**：整份設定序列化為單一 JSON 字串（`jsonEncode(settings.toJson())`），寫入 `SharedPreferences` 的單一 key `screen_clock.settings.v1`。key 名稱中的 `v1` 為歷史命名，**與 `schemaVersion` 無關**，不隨 schema 升版變動（`schemaVersion` 現行為 4，key 名仍固定為 `v1`）。序列化編碼細節（欄位鍵名、`Color`/`DateTime` 編碼規則）見 SPEC-009 B.2。

## 功能需求

### FR-01: SettingsModel 資料模型

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 延伸 |

**描述**：定義使用者可設定項目的資料模型。

**欄位**（現況 schema v4，14 欄；格式/值域/版本演進細節見 SPEC-009 A.1）：

| 欄位 | 型別 | 預設值 | 對應 SPEC |
|------|------|--------|-----------|
| `fontSize` | `double` | `AppSizes.clockFontSize` (120) | SPEC-002 FR-04 |
| `fillColor` | `Color` | `AppColors.clockFill` (white) | SPEC-002 FR-04 |
| `strokeColor` | `Color` | `AppColors.clockStroke` (black) | SPEC-002 FR-04 |
| `strokeWidth` | `double` | `AppSizes.clockStrokeWidth` (2) | SPEC-002 FR-04 |
| `timeFormat` | `String` | `AppText.timeFormat` ("HH:mm:ss") | SPEC-002 FR-01 |
| `targetScreenIndex` | `int` | `0` | SPEC-003 FR-02 |
| `autoLaunch` | `bool` | `false` | SPEC-006 |
| `birthDate` | `DateTime?` | `null`（未設定；唯一可為 null 的欄位） | 無對應 SPEC（生命計時模式功能尚無規格文件，已知規格落差） |
| `lifeTimerMode` | `bool` | `false` | 無對應 SPEC（生命計時模式功能尚無規格文件，已知規格落差） |
| `bindings` | `List<MouseBinding>` | 含一筆預設側鍵拖曳滾動綁定 | SPEC-007 FR-02 |
| `bindingsSeeded` | `bool` | `true`（`defaults()`）；欄位級 migration 旗標，非使用者設定，語意見 SPEC-009 A.1/A.2 | SPEC-007（間接） |
| `cursorLocatorEnabled` | `bool` | `AppCursorLocator.defaultEnabled` (true) | SPEC-008 FR-06 |
| `cursorLocatorEffectDurationSeconds` | `double` | `AppCursorLocator.defaultDurationSeconds` (1.5 秒，值域 0.5–3.0) | SPEC-008 FR-06 |
| `cursorLocatorPrimaryColor` | `Color` | `AppCursorLocator.defaultTint` (`0xFF2196F3` 系統藍) | SPEC-008 FR-06 |

**約束條件**：

- 不變式：除 `birthDate` 外所有欄位 non-null（`birthDate` 未設定時為 `null`，見 SPEC-009 INV-01）
- 工廠：`SettingsModel.defaults()` 重現各欄位預設樣式
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
- 版本欄位 `schemaVersion` 為 `int`，現行值為 `4`（隨欄位新增遞增，寫出時恆等於 code 常數）；`fromJson()` 不讀取此欄位，向後相容完全由「缺欄取 default」達成，`schemaVersion` 僅為單向稽核標記，非解析分支依據。完整版本演進表與此設計的後果見 SPEC-009 A.1/A.3

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

**描述**：schema 已由 v1 演進至 v4（現行 code），沿用「加欄 + 預設值 fallback」策略，未導入版本分支 migration；`bindingsSeeded` 為目前唯一的命令式遷移（非 `schemaVersion` 分派）。此策略成立的前提、治理規則（何時須升級為版本分支解析）與已接受風險，見 SPEC-009 A.3「migration 治理規則」與「升級為版本分支解析（方案 B）的觸發條件」。

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
    this.birthDate,
    this.lifeTimerMode = false,
    this.bindings = const <MouseBinding>[],
    this.bindingsSeeded = false,
    this.cursorLocatorEnabled = AppCursorLocator.defaultEnabled,
    this.cursorLocatorEffectDurationSeconds =
        AppCursorLocator.defaultDurationSeconds,
    this.cursorLocatorPrimaryColor = AppCursorLocator.defaultTint,
  });

  factory SettingsModel.defaults();
  factory SettingsModel.fromJson(Map<String, dynamic> json);
  Map<String, Object> toJson();

  SettingsModel copyWith({...});
}
```

> 完整欄位型別/預設值見 FR-01 欄位表；`fromJson`/`toJson` 的容錯轉換規則與序列化編碼細節見 SPEC-009 A.3（INV-04）與 B.2（不在此重複列出，避免與資料契約重疊）。

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
| 不做版本分支 migration | 加欄位用 default fallback（`bindingsSeeded` 為唯一例外的欄位級旗標） | 設計上禁止刪除欄位、禁止改型別；治理規則見 SPEC-009 A.3 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |
| 1.1 | 2026-08-01 | 更新至 code 現況（schema v4）：FR-01 欄位表由 7 欄補齊至 14 欄；FR-02 `schemaVersion` 描述由「目前為 1」更新為「現行為 4」並補充其不參與解析的性質；NFR-02 移除「MVP 階段只實作 v1 schema」的過時描述，改為現行策略摘要；新增實際儲存格式段落（單一 key `screen_clock.settings.v1`，key 名與 schemaVersion 無關）；`## 資料模型` 建構子補齊現況欄位；新增與 SPEC-009 的職責分工聲明，細節事項改為引用 SPEC-009 避免重複 |

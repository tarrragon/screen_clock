---
id: DOMAIN-MAP-data-management
domain: "data-management"
source_specs: [SPEC-004]
related_usecases: []
created: "2026-07-29"
updated: "2026-07-29"
---

# Domain Map — data-management

> 產出來源：1.4.0-W1-006。本文件界定 DDD domain bundle 邊界，作為切層、派發與測試策略的權威依據。
> 與 SPEC-004（使用者設定持久化）交叉引用。SPEC-009（資料契約）為 SPEC-004 的補充契約文件，不含獨立 FR。

## 1. 目的與 UC / DDD 正交關係

本文件補上 data-management domain 的**水平視角**：按業務知識把 domain 切成 bundle。UC 是**垂直視角**（一條使用者劇本貫穿 UI → 邏輯 → 持久化），一個 UC 橫切多個 bundle。

**核心準則**：domain 層保持純——無 I/O、無 UI 形狀、對顯示偏好（如語系、格式化、單位換算）與框架一無所知。違反則 domain 被 I/O 與顯示偏好污染，測試被迫拖真實依賴、無法純函式驗證。

## 2. 分層與依賴方向

**單 aggregate 形態**（data-management 以模型與持久化為主）：
```
presentation (SettingsScope InheritedWidget)
        │ 依賴（單向）
        ▼
domain read-model / state（SettingsController 狀態管理）
        │ 依賴（單向）
        ▼
domain aggregate + VO（SettingsModel 值物件）
        ▲ 單向
        │ 依賴
data（SettingsService 持久化 via shared_preferences）
```

**依賴方向底線（不可違反）**：

- domain 不得 import data / presentation / UI 框架 / 外部服務。違反則喪失純函式可測性。
- data-management domain 不依賴其他 domain。SettingsModel 被 display、user-experience、input domain 消費（單向依賴）。
- SettingsModel 依賴 input domain 的 MouseAction 和 MouseBinding 型別（用於滑鼠綁定設定欄位）。此為 data-management → input 的單向依賴。

## 3. Bundle 界定表

| Bundle | 分類 | 納入概念 | 排除 | 目標路徑 | 測試層/方法 | 實作狀態 | 資料契約文件引用連結 |
|---|---|---|---|---|---|---|---|
| SettingsModel | aggregate + VO | 設定資料模型、序列化/反序列化、預設值、copyWith（SPEC-004 FR-01, FR-02） | 持久化邏輯、UI | `lib/models/settings_model.dart` | unit：序列化往返、預設值、copyWith | 已實作 | N/A |
| SettingsController | read-model / state | 設定狀態管理、載入/儲存協調（SPEC-004 FR-04） | 持久化細節、UI | `lib/state/settings_controller.dart` | unit：狀態轉換邏輯 | 已實作 | N/A |
| SettingsScope | 非 domain（presentation） | InheritedWidget 傳遞設定（SPEC-004 FR-04） | domain 計算 | `lib/state/settings_scope.dart` | widget test | 已實作 | N/A |
| SettingsService | 非 domain（infra） | shared_preferences 讀寫（SPEC-004 FR-03） | domain 計算 | `lib/services/settings_service.dart` | unit：讀寫邏輯 | 已實作 | docs/spec/data-management/SPEC-009-settings-storage-data-contract.md |

### Bundle 不變式清單（per-bundle）

| Bundle | 不變式（每條可轉一個 unit test） |
|---|---|
| SettingsModel | 序列化後反序列化回原值（round-trip）；copyWith 只改指定欄位；預設值合法 |
| SettingsController | 載入後狀態反映持久化值；儲存後持久化值反映當前狀態 |
| SettingsService | 讀取不存在的 key 回傳 null；寫入後讀取回原值 |

## 4. 邊界決策

### 4.1 SettingsModel 依賴 input domain 型別

SettingsModel 引用 `MouseAction` 和 `MouseBinding`（來自 `lib/input/`）作為滑鼠綁定設定欄位的型別。這造成 data-management → input 的依賴。此為設計取捨：將綁定設定集中於 SettingsModel 而非分散，簡化持久化邏輯。依賴方向為 data-management → input 單向，不成環。

## 5. 對實作票的切分指引

| 票 | 層 | domain map 對齊指引 |
|---|---|---|
| 設定模型票 | domain | SettingsModel 純值物件，依 §3 測試 |
| 設定持久化票 | data | SettingsService，持久化細節屬 data 層 |
| 設定狀態管理票 | domain + presentation | SettingsController（domain）+ SettingsScope（presentation） |

## 6. 觀察到的技術債（待追蹤）

- SettingsModel 直接引用 input domain 的型別（MouseAction、MouseBinding），若未來需解耦可提取介面。影響低，暫不追蹤。

## 7. FR → Bundle 覆蓋對照

### SPEC-004（使用者設定持久化）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | SettingsModel | 資料模型定義 |
| FR-02 | SettingsModel | 序列化/反序列化 |
| FR-03 | SettingsService（infra） | 持久化介面與實作 |
| FR-04 | SettingsController + SettingsScope（presentation） | 啟動時讀取並套用 |

---

**Last Updated**: 2026-07-29 | **Source**: 1.4.0-W1-006

---
id: DOMAIN-MAP-display
domain: "display"
source_specs: [SPEC-002]
related_usecases: []
created: "2026-07-29"
updated: "2026-07-29"
---

# Domain Map — display

> 產出來源：1.4.0-W1-006。本文件界定 DDD domain bundle 邊界，作為切層、派發與測試策略的權威依據。
> 與 SPEC-002（螢幕中央時鐘顯示）交叉引用。

## 1. 目的與 UC / DDD 正交關係

本文件補上 display domain 的**水平視角**：按業務知識把 domain 切成 bundle。UC 是**垂直視角**（一條使用者劇本貫穿 UI → 邏輯 → 持久化），一個 UC 橫切多個 bundle。

**核心準則**：domain 層保持純——無 I/O、無 UI 形狀、對顯示偏好（如語系、格式化、單位換算）與框架一無所知。違反則 domain 被 I/O 與顯示偏好污染，測試被迫拖真實依賴、無法純函式驗證。

## 2. 分層與依賴方向

**單 aggregate 形態**（display domain 以呈現為主）：
```
presentation (CenterClock widget + 狀態管理)
        │ 依賴（單向）
        ▼
domain read-model（AgeFormatter 時間格式化）
        │ 依賴（單向）
        ▼
domain aggregate + VO（無獨立 aggregate，時間來源為系統時鐘）
        ▲ 單向
        │ 依賴
data（無獨立 data 層，時間來自 dart:async Timer）
```

**依賴方向底線（不可違反）**：

- domain 不得 import data / presentation / UI 框架 / 外部服務。違反則喪失純函式可測性。
- display domain 依賴 data-management domain（讀取 SettingsModel 取得字型/顏色設定）。此為單向依賴，data-management 不反向依賴 display。
- CenterClock widget 屬 presentation 層，非 domain。

## 3. Bundle 界定表

| Bundle | 分類 | 納入概念 | 排除 | 目標路徑 | 測試層/方法 | 實作狀態 | 資料契約文件引用連結 |
|---|---|---|---|---|---|---|---|
| AgeFormatter | read-model | 時間格式化計算（SPEC-002 FR-01） | UI 渲染、定時器 | `lib/age_formatter.dart` | unit：格式化邊界值 | 已實作 | N/A |
| CenterClock | 非 domain（presentation） | 時鐘 Widget、每秒更新、中央定位、預設樣式（SPEC-002 FR-01~04） | domain 計算 | `lib/widgets/center_clock.dart` | widget test | 已實作 | N/A |

### Bundle 不變式清單（per-bundle）

| Bundle | 不變式（每條可轉一個 unit test） |
|---|---|
| AgeFormatter | 格式化輸出為 HH:MM:SS 格式；時分秒各補零至兩位 |
| CenterClock | 每秒更新時間顯示；Widget 居中對齊 |

## 4. 邊界決策

### 4.1 AgeFormatter 歸 display domain

AgeFormatter 是時間格式化的純函式計算，語意上屬於「如何顯示時間」，歸 display domain。它不依賴 UI 框架，可純函式測試。

## 5. 對實作票的切分指引

| 票 | 層 | domain map 對齊指引 |
|---|---|---|
| 時鐘顯示票 | presentation | CenterClock widget，依賴 AgeFormatter |
| 時間格式化票 | domain | AgeFormatter 純函式，依 §3 測試 |

## 6. 觀察到的技術債（待追蹤）

- 無已知技術債。

## 7. FR → Bundle 覆蓋對照

### SPEC-002（螢幕中央時鐘顯示）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | AgeFormatter + CenterClock（presentation） | 當前時間顯示 |
| FR-02 | CenterClock（presentation） | 每秒自動更新（Timer） |
| FR-03 | CenterClock（presentation） | 中央定位 |
| FR-04 | CenterClock（presentation） | 預設樣式（字型大小/顏色） |

---

**Last Updated**: 2026-07-29 | **Source**: 1.4.0-W1-006

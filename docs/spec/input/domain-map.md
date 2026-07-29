---
id: DOMAIN-MAP-input
domain: "input"
source_specs: [SPEC-007]
related_usecases: []
created: "2026-07-29"
updated: "2026-07-29"
---

# Domain Map — input

> 產出來源：1.4.0-W1-006。本文件界定 DDD domain bundle 邊界，作為切層、派發與測試策略的權威依據。
> 與 SPEC-007（滑鼠按鍵綁定）交叉引用。

## 1. 目的與 UC / DDD 正交關係

本文件補上 input domain 的**水平視角**：按業務知識把 domain 切成 bundle。UC 是**垂直視角**（一條使用者劇本貫穿 UI → 邏輯 → 持久化），一個 UC 橫切多個 bundle。

**核心準則**：domain 層保持純——無 I/O、無 UI 形狀、對顯示偏好（如語系、格式化、單位換算）與框架一無所知。違反則 domain 被 I/O 與顯示偏好污染，測試被迫拖真實依賴、無法純函式驗證。

## 2. 分層與依賴方向

**單 aggregate 形態**（input domain 以事件攔截與綁定為主）：
```
presentation (設定面板中的綁定 UI)
        │ 依賴（單向）
        ▼
domain read-model / controller（InputBindingController 綁定協調）
        │ 依賴（單向）
        ▼
domain aggregate + VO（MouseBinding + MouseAction 值物件）
        ▲ 單向
        │ 依賴
data（InputBindingChannel 平台通道 CGEventTap）
```

**依賴方向底線（不可違反）**：

- domain 不得 import data / presentation / UI 框架 / 外部服務。違反則喪失純函式可測性。
- input domain 不依賴其他 domain。input 的型別（MouseAction、MouseBinding）被 data-management domain 的 SettingsModel 消費，為 data-management → input 單向依賴。
- InputBindingChannel 屬 infra 層（平台通道），InputBindingController 屬 domain/state 層。

## 3. Bundle 界定表

| Bundle | 分類 | 納入概念 | 排除 | 目標路徑 | 測試層/方法 | 實作狀態 | 資料契約文件引用連結 |
|---|---|---|---|---|---|---|---|
| MouseBinding | aggregate + VO | 綁定資料模型、序列化（SPEC-007 FR-01, FR-02） | 平台事件攔截 | `lib/input/mouse_binding.dart` | unit：序列化往返、預設值 | 已實作 | N/A |
| MouseAction | supporting VO | 滑鼠動作列舉（拖曳滾動、快捷鍵等）（SPEC-007 FR-04, FR-05） | 綁定邏輯 | `lib/input/mouse_action.dart` | unit：列舉完整性 | 已實作 | N/A |
| InputBindingController | read-model / state | 綁定協調、偵測捕捉模式（SPEC-007 FR-06） | 平台 API | `lib/input/input_binding_controller.dart` | unit：狀態轉換、綁定邏輯 | 已實作 | N/A |
| InputBindingChannel | 非 domain（infra） | CGEventTap 全域事件攔截、平台通道（SPEC-007 FR-03） | domain 計算 | `lib/input/input_binding_channel.dart` | unit：通道訊息解析 | 已實作 | N/A |
| AccessibilityPermission | 非 domain（infra） | 輔助使用權限檢查與引導（SPEC-007 FR-07） | domain 計算 | 規劃中（目前內嵌於 InputBindingChannel） | integration：權限流程 | 規劃中 | N/A |
| SettingsPanelBinding | 非 domain（presentation） | 設定面板中的綁定 UI 整合（SPEC-007 FR-08） | domain 計算 | `lib/widgets/settings_panel.dart`（部分） | widget test | 已實作 | N/A |

### Bundle 不變式清單（per-bundle）

| Bundle | 不變式（每條可轉一個 unit test） |
|---|---|
| MouseBinding | 序列化後反序列化回原值；每個綁定關聯一個按鍵與一個動作 |
| MouseAction | 列舉值不重複；每個動作有對應顯示名稱 |
| InputBindingController | 偵測模式開啟時攔截下一次按鍵事件；非偵測模式正常轉發事件 |
| InputBindingChannel | 平台通道訊息格式正確解析；無效訊息靜默忽略（有日誌） |

## 4. 邊界決策

### 4.1 AccessibilityPermission 獨立為 bundle（規劃中）

SPEC-007 FR-07 的輔助使用權限檢查目前內嵌於 InputBindingChannel。語意上權限管理是獨立關注點，應提取為獨立 bundle。標記規劃中，待實作時提取。此為目標邊界，非現況。

### 4.2 input domain 被 data-management 依賴

SettingsModel 直接引用 MouseAction 和 MouseBinding 型別。依賴方向為 data-management → input，符合 DAG 無環要求。input 不依賴 data-management。

## 5. 對實作票的切分指引

| 票 | 層 | domain map 對齊指引 |
|---|---|---|
| 滑鼠綁定模型票 | domain | MouseBinding + MouseAction，依 §3 測試 |
| 全域事件攔截票 | infra | InputBindingChannel 平台通道 |
| 綁定控制器票 | domain | InputBindingController，依 §3 狀態轉換 |
| 權限引導票 | infra | AccessibilityPermission，待提取 |

## 6. 觀察到的技術債（待追蹤）

- FR-07 輔助使用權限檢查目前內嵌於 InputBindingChannel，未獨立為 bundle。影響中，待實作時提取。

## 7. FR → Bundle 覆蓋對照

### SPEC-007（滑鼠按鍵綁定）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | MouseBinding | 綁定資料模型 |
| FR-02 | MouseBinding | 綁定序列化與持久化 |
| FR-03 | InputBindingChannel（infra） | 全域事件攔截（CGEventTap） |
| FR-04 | MouseAction | 動作 — 拖曳滾動 |
| FR-05 | MouseAction | 動作 — 綁定快捷鍵 |
| FR-06 | InputBindingController | 偵測捕捉模式 |
| FR-07 | AccessibilityPermission（infra，規劃中） | 輔助使用權限檢查與引導 |
| FR-08 | SettingsPanelBinding（presentation） | 設定面板整合 |

---

**Last Updated**: 2026-07-29 | **Source**: 1.4.0-W1-006

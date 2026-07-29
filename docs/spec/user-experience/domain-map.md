---
id: DOMAIN-MAP-user-experience
domain: "user-experience"
source_specs: [SPEC-005, SPEC-008]
related_usecases: []
created: "2026-07-29"
updated: "2026-07-29"
---

# Domain Map — user-experience

> 產出來源：1.4.0-W1-006。本文件界定 DDD domain bundle 邊界，作為切層、派發與測試策略的權威依據。
> 與 SPEC-005（設定面板與呼出機制）、SPEC-008（滑鼠定位器）交叉引用。

## 1. 目的與 UC / DDD 正交關係

本文件補上 user-experience domain 的**水平視角**：按業務知識把 domain 切成 bundle。UC 是**垂直視角**（一條使用者劇本貫穿 UI → 邏輯 → 持久化），一個 UC 橫切多個 bundle。

**核心準則**：domain 層保持純——無 I/O、無 UI 形狀、對顯示偏好（如語系、格式化、單位換算）與框架一無所知。違反則 domain 被 I/O 與顯示偏好污染，測試被迫拖真實依賴、無法純函式驗證。

## 2. 分層與依賴方向

**單 aggregate 形態**（user-experience 以 UI 互動為主）：
```
presentation (SettingsPanel widget + 滑鼠定位器 widget)
        │ 依賴（單向）
        ▼
domain read-model（滑鼠定位器效果計算，規劃中）
        │ 依賴（單向）
        ▼
domain aggregate + VO（無獨立 aggregate）
        ▲ 單向
        │ 依賴
data（設定持久化 via data-management domain）
```

**依賴方向底線（不可違反）**：

- domain 不得 import data / presentation / UI 框架 / 外部服務。違反則喪失純函式可測性。
- user-experience domain 依賴 data-management domain（讀取/寫入 SettingsModel）和 input domain（滑鼠綁定控制器）。此為單向依賴。
- user-experience domain 依賴 platform domain（click-through 切換）。此為單向依賴，platform 不反向依賴 user-experience。

## 3. Bundle 界定表

| Bundle | 分類 | 納入概念 | 排除 | 目標路徑 | 測試層/方法 | 實作狀態 | 資料契約文件引用連結 |
|---|---|---|---|---|---|---|---|
| SettingsPanel | 非 domain（presentation） | 設定面板 UI、即時預覽、熱鍵呼出（SPEC-005 FR-01~04） | domain 計算 | `lib/widgets/settings_panel.dart` | widget test | 已實作 | N/A |
| CursorLocator | 非 domain（presentation） | 聚光燈效果、螢幕邊框閃爍、游標波紋擴散（SPEC-008 FR-03~05） | domain 計算 | 規劃中（無對應 lib/ 路徑） | widget test | 規劃中 | N/A |
| CursorLocatorDomain | read-model | 目標螢幕判定、跨螢幕跟隨邏輯（SPEC-008 FR-02） | UI 渲染效果 | 規劃中（無對應 lib/ 路徑） | unit：螢幕判定邏輯 | 規劃中 | N/A |
| CursorLocatorSettings | 非 domain（cross-cutting） | 定位器設定項目與持久化（SPEC-008 FR-06） | domain 計算 | 規劃中（無對應 lib/ 路徑） | unit：設定序列化 | 規劃中 | N/A |

### Bundle 不變式清單（per-bundle）

| Bundle | 不變式（每條可轉一個 unit test） |
|---|---|
| SettingsPanel | 熱鍵呼出切換面板可見性；click-through 在面板開啟時動態解除 |
| CursorLocatorDomain | 目標螢幕判定回傳有效螢幕；跨螢幕跟隨追蹤游標位置 |

## 4. 邊界決策

### 4.1 滑鼠定位器歸 user-experience 而非 display

滑鼠定位器是使用者互動體驗功能（協助定位游標），非時鐘顯示。SPEC-008 的效果（聚光燈、邊框閃爍、波紋）屬 UX 增強，與 display domain 的靜態時鐘顯示語意不同。

### 4.2 SPEC-008 FR-01 全域熱鍵觸發

全域熱鍵觸發歸 presentation 層（SettingsPanel 同層級的熱鍵綁定），非 domain 層。熱鍵注冊是平台 API 互動，由 presentation 層協調。

## 5. 對實作票的切分指引

| 票 | 層 | domain map 對齊指引 |
|---|---|---|
| 設定面板票 | presentation | SettingsPanel widget，依賴 data-management + input |
| 滑鼠定位器票 | domain + presentation | CursorLocatorDomain（domain）+ CursorLocator（presentation） |

## 6. 觀察到的技術債（待追蹤）

- 無已知技術債。滑鼠定位器（SPEC-008）尚未實作。

## 7. FR → Bundle 覆蓋對照

### SPEC-005（設定面板與呼出機制）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | SettingsPanel（presentation） | 全域熱鍵 Cmd+Opt+, |
| FR-02 | SettingsPanel（presentation） | 動態解除 click-through |
| FR-03 | SettingsPanel（presentation） | 設定面板 UI 內容 |
| FR-04 | SettingsPanel（presentation） | 即時預覽 |

### SPEC-008（滑鼠定位器）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | CursorLocator（presentation，規劃中） | 全域熱鍵觸發 |
| FR-02 | CursorLocatorDomain（規劃中） | 目標螢幕判定與跨螢幕跟隨 |
| FR-03 | CursorLocator（presentation，規劃中） | 聚光燈效果 |
| FR-04 | CursorLocator（presentation，規劃中） | 螢幕邊框閃爍 |
| FR-05 | CursorLocator（presentation，規劃中） | 游標波紋擴散 |
| FR-06 | CursorLocatorSettings（cross-cutting，規劃中） | 設定項目與持久化 |

---

**Last Updated**: 2026-07-29 | **Source**: 1.4.0-W1-006

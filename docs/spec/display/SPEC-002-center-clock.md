---
id: SPEC-002
title: "螢幕中央時鐘顯示"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: display
subdomain: clock

related_usecases:
  - UC-01
related_specs:
  - SPEC-001
implements_requirements:
  - PROP-001 In Scope（螢幕中央顯示當前時間 / 每秒更新）
depends_on_domains:
  - platform
---

# SPEC-002: 螢幕中央時鐘顯示

## 概述

定義 screen_clock 主要 UI 元素：在透明遮罩視窗的中央顯示當前時間，每秒更新一次。MVP 版本樣式寫死為易讀預設（白色、粗體、大字、有 stroke 描邊），不提供使用者設定。

## 功能需求

### FR-01: 當前時間顯示

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：在視窗正中央顯示當前本機時間。

**約束條件**：

- 時間來源：`DateTime.now()`（本機時區）
- 預設格式：`HH:mm:ss`（24 小時制）
- 時區跟隨系統，不在 app 內提供時區選擇

**驗收標準**：

- [ ] 啟動時立即顯示當前時間（不出現預設佔位字串）
- [ ] 顯示與系統 menu bar 時鐘秒數差異 ≤ 1 秒
- [ ] 切換系統時區後 app 重啟可正確反映新時區

---

### FR-02: 每秒自動更新

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：時鐘文字每秒自動更新一次。

**約束條件**：

- 使用 `Timer.periodic(Duration(seconds: 1), ...)`
- 必須在 widget `dispose()` 時取消 timer，避免記憶體洩漏
- 只重繪時鐘子樹（透過 `setState` 在 clock widget 內），不重繪整個 root widget

**驗收標準**：

- [ ] 觀察 60 秒，時間文字逐秒更新無遺漏
- [ ] hot reload / hot restart 後 timer 不重複建立（無雙倍更新）
- [ ] app 關閉時 timer 已停止（無未取消的 timer 警告）

---

### FR-03: 中央定位

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：時鐘文字位於視窗（即螢幕）正中央。

**約束條件**：

- 採用 `Center` widget 包裹 `Text`
- 文字基線置中對齊（垂直 & 水平）

**驗收標準**：

- [ ] 在不同解析度下視覺中央誤差 ≤ 5 pixel
- [ ] 螢幕解析度變更後時鐘仍位於新中央

---

### FR-04: 預設樣式

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 In Scope |
| 對應用例 | UC-01 |

**描述**：時鐘文字採用易讀的預設樣式，能在任何底色（白桌布 / 黑桌布 / 圖片桌布）上保持可讀。

**約束條件**：

- 字型大小：120 sp（粗略對應 macOS 1920×1080 螢幕中可從約 2m 距離輕鬆讀取）
- 字重：`FontWeight.w700`
- 顏色：白色為主，加 2 sp 黑色 stroke 描邊（避免白底桌布看不見）
- MVP 不開放使用者調整

**驗收標準**：

- [ ] 在純白桌布上時鐘清晰可讀
- [ ] 在純黑桌布上時鐘清晰可讀
- [ ] 在亮色照片桌布上時鐘清晰可讀

---

## 非功能需求

### NFR-01: 重繪效能

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | 時鐘每秒更新的 widget 重繪不超過時鐘子樹；CPU 平均使用率 < 1%（M1 以上機型，閒置 5 分鐘量測） |

**描述**：每秒重繪僅限時鐘子樹，不可觸發整個 `MaterialApp` 重繪。

---

### NFR-02: 跨平台一致性

| 項目 | 值 |
|------|-----|
| 類型 | 相容性 |
| 指標 | 在 macOS 與未來 Windows 平台上時鐘呈現相同視覺結果 |

**描述**：時鐘 widget 不應依賴平台特定 API；視窗層由 SPEC-001 抽象。

---

## 資料模型

時鐘狀態：

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| current | `DateTime` | 是 | 當前時間，由 timer 每秒更新 |
| format | `DateFormat` | 是 | 顯示格式；MVP 寫死 `HH:mm:ss` |

## 介面規格

### Clock widget 介面

```dart
class CenterClock extends StatefulWidget {
  const CenterClock({super.key});

  @override
  State<CenterClock> createState() => _CenterClockState();
}
```

依賴：無外部注入，內部建立 timer。

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| `Timer.periodic` 建立失敗 | E_TIMER_INIT | log 並讓 timer 退化為單次更新（不可運作但不 crash） | 無 GUI；只 stderr |
| `DateTime.now()` 取得失敗 | — | 不會發生（Dart runtime 保證） | — |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| widget 不可阻擋互動 | 即使 widget 本身在最上層，遮罩視窗已 click-through，事件穿透由 SPEC-001 負責 | 時鐘 widget 不需處理事件穿透 |
| MVP 不支援樣式設定 | 字型、顏色、大小、位置寫死 | 將來增加設定面板時需重構為注入式樣式參數 |
| 不引入時鐘格式化第三方套件 | MVP 用 `String.padLeft` 手寫，避免依賴 | 簡化依賴；未來支援多 locale 時引入 `intl` |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

---
id: SPEC-005
title: "設定面板與呼出機制"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: user-experience
subdomain: settings-panel

related_usecases: []
related_specs:
  - SPEC-001
  - SPEC-002
  - SPEC-004
implements_requirements:
  - PROP-001 v1.0.0「完整設定面板」
depends_on_domains:
  - data-management
---

# SPEC-005: 設定面板與呼出機制

## 概述

定義 v1.0.0 設定面板的呼出方式、UI 內容、與 click-through 全穿透的互動衝突解法。本規格依賴 SPEC-001（透明遮罩）+ SPEC-004（設定持久化），是兩者的 UI 整合。

## 呼出機制決策

| 候選方案 | 優點 | 缺點 | 結論 |
|---------|------|------|------|
| 右鍵選單 | macOS 慣用 | 遮罩 click-through 下完全不可達 | 不採用 |
| Cmd+Opt+, 系統熱鍵 | 與 macOS 偏好設定快捷鍵 Cmd+, 鄰近、不需 focus | 需 hotkey_manager 套件、與其他 app 可能衝突 | 採用 |
| Menu bar status icon | macOS 慣用、發現性高 | 需 tray_manager 套件、額外的 UI 元件 | 不採用（額外成本） |

採用 `hotkey_manager`。

## 功能需求

### FR-01: 全域熱鍵 Cmd+Opt+,

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 |

**描述**：注冊系統級熱鍵 `Cmd + Option + ,`，按下時 toggle 設定面板（顯示/關閉）。

**約束條件**：

- 使用 `hotkey_manager` 套件
- 註冊發生於 main 啟動流程
- app 退出時取消註冊
- 熱鍵衝突時 fallback：log warning，等待使用者修改其他 app 的熱鍵

**驗收標準**：

- [ ] 任何 app 在前景時 Cmd+Opt+, 都能呼出設定面板
- [ ] 重複按下時 toggle（再按一次關閉）

---

### FR-02: 設定面板開啟時動態解除 click-through

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 + SPEC-001 設計約束 |

**描述**：設定面板開啟期間，視窗不再 click-through（接收滑鼠/鍵盤），讓使用者可以與表單互動；關閉後恢復全穿透。

**約束條件**：

- 開啟：`windowManager.setIgnoreMouseEvents(false)`
- 關閉：`windowManager.setIgnoreMouseEvents(true)`
- 切換期間時鐘繼續走（不阻塞）
- 切換需在 50ms 內完成（NFR-01）

**驗收標準**：

- [ ] 面板開啟後可以操作 Slider、ColorPicker 等
- [ ] 面板關閉後遮罩立即恢復可穿透
- [ ] 面板開啟期間，遮罩外的桌面點擊不被攔截（floating modal 行為）

---

### FR-03: 設定面板 UI 內容

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 |

**描述**：以模態 dialog 呈現可調項目。

**欄位**（對應 SettingsModel）：

| 控件 | 對應欄位 | 控件型別 | 範圍 |
|------|---------|---------|------|
| 字型大小 | `fontSize` | Slider | 40 ~ 240 |
| 描邊寬度 | `strokeWidth` | Slider | 0 ~ 8 |
| 填色 | `fillColor` | 預設色板 + 自訂 ARGB 輸入 | 任意 |
| 描邊色 | `strokeColor` | 同上 | 任意 |
| 時間格式 | `timeFormat` | Dropdown | "HH:mm:ss" / "HH:mm" |
| 目標螢幕 | `targetScreenIndex` | Dropdown（含螢幕清單） | 0..N-1 |
| 開機啟動 | `autoLaunch` | Switch | true/false |

**約束條件**：

- 設定面板尺寸固定（如 480x540），不全螢幕
- 含「儲存」與「取消」兩個按鈕
- 「儲存」呼叫 `SettingsService.save` 並關閉面板
- 「取消」捨棄未存變更並關閉面板
- 樣式預覽（FR-04）為即時反映

**驗收標準**：

- [ ] 全部 7 個欄位皆可調整
- [ ] 儲存後重啟設定保留
- [ ] 取消後設定不變

---

### FR-04: 即時預覽

| 項目 | 值 |
|------|-----|
| 優先級 | P0 |
| 來源 | PROP-001 v1.0.0 |

**描述**：在設定面板中拖動 slider / 切換顏色時，遮罩中央時鐘即時反映新樣式（不需按儲存）。

**約束條件**：

- 樣式狀態以 `ValueNotifier<SettingsModel>` 管理（lib/state/settings_controller.dart）
- CenterClock 改為從 controller 讀取樣式（不再用 AppConstants 直接綁定）
- 取消時 controller 還原啟動時快照
- 儲存時 controller 寫入 service 並保留

**驗收標準**：

- [ ] 拖動 fontSize slider 時遮罩時鐘即時放大/縮小
- [ ] 切換顏色時即時變色
- [ ] 取消後遮罩時鐘回到啟動時狀態
- [ ] 儲存後遮罩時鐘維持選定狀態

---

## 非功能需求

### NFR-01: click-through 切換延遲

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | 熱鍵按下到面板可互動 < 200ms |

---

### NFR-02: 設定面板可達性

| 項目 | 值 |
|------|-----|
| 類型 | 可用性 |
| 指標 | 鍵盤可完整操作（Tab/Enter/Esc） |

---

## 介面規格

### SettingsController

```dart
class SettingsController extends ValueNotifier<SettingsModel> {
  SettingsController(SettingsModel initial) : _initial = initial, super(initial);

  final SettingsModel _initial;
  void resetToStartup() => value = _initial;
}
```

### 主流程整合

main.dart 在 windowManager 設定後啟動 SettingsController，並注入到 widget tree（root provider）。
Hotkey 觸發時：
1. setIgnoreMouseEvents(false)
2. push SettingsPanel route
3. on close: setIgnoreMouseEvents(true)

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| hotkey 註冊失敗 | E_HOTKEY_REGISTER | log + 不阻擋啟動；使用者無法呼出面板（需重啟） | stderr |
| setIgnoreMouseEvents 切換失敗 | E_CLICK_TOGGLE | log + 嘗試重新呼叫 | stderr |
| SettingsService.save 失敗 | E_PREFS_SAVE（同 SPEC-004） | dialog 顯示「儲存失敗」 | UI |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| 設定面板必須在動態 click-through 解除後才可互動 | FR-02 是 FR-03/04 的前置 | 開啟順序固定 |
| ValueNotifier 比 Provider 套件輕量 | MVP 不引入 Riverpod 等套件 | 樣式注入用內建工具 |
| 取消按鈕必須完全還原 | 不可保留 partial 變更 | controller 持有 _initial 快照 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

---
id: SPEC-006
title: "macOS 開機自動啟動"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"
owner: tarrragon

domain: platform
subdomain: auto-launch

related_usecases: []
related_specs:
  - SPEC-004
  - SPEC-005
implements_requirements:
  - PROP-001 v1.0.0「開機啟動」
depends_on_domains:
  - data-management
---

# SPEC-006: macOS 開機自動啟動

## 概述

定義 screen_clock v1.0.0 在 macOS 上的開機自動啟動行為。使用者在設定面板切換 `autoLaunch` 後，下次重開機 / 登入時 app 應自動啟動或不啟動。

## 方案決策

| 候選方案 | 優點 | 缺點 | 結論 |
|---------|------|------|------|
| `launch_at_startup` 套件 | 跨平台 API、官方 leanflutter 維護、macOS 13+ 用 SMAppService、舊版 fallback launchd plist | 多一個依賴 | 採用 |
| 手寫 `launchd` plist | 完全控制 | 路徑硬編碼風險、權限處理複雜、不跨平台 | 不採用 |
| 直接呼叫 `SMAppService` Swift API | 原生、官方 | 只支援 macOS 13+；需要 Swift binding 自行寫 | 不採用 |

採用 `launch_at_startup` 套件。

## 功能需求

### FR-01: 啟用 / 停用開機啟動

| 項目 | 值 |
|------|-----|
| 優先級 | P1 |
| 來源 | PROP-001 v1.0.0 |

**描述**：當 `SettingsModel.autoLaunch` 切換時，呼叫對應的 enable / disable API。

**約束條件**：

- 同步 SettingsModel 變更：toggle switch → controller.update → AutoLaunchService 套用
- 失敗時 log + 不阻擋使用者繼續操作；設定 toggle 回滾到 OS 實際狀態

**驗收標準**：

- [ ] toggle on → 重啟系統後自動啟動 app
- [ ] toggle off → 重啟系統後不會啟動 app
- [ ] toggle 期間 SettingsModel.autoLaunch 與 OS 狀態一致

---

### FR-02: 查詢當前狀態

| 項目 | 值 |
|------|-----|
| 優先級 | P1 |
| 來源 | PROP-001 v1.0.0 |

**描述**：啟動時 app 可查詢自身是否已註冊為 LaunchAtLogin，用於同步 UI。

**約束條件**：

- 啟動時若 SettingsModel.autoLaunch 與 OS 狀態不一致 → 以 OS 狀態為準並覆寫 settings

**驗收標準**：

- [ ] 啟動後 SettingsModel.autoLaunch == 實際 OS 狀態

---

## 非功能需求

### NFR-01: 切換延遲

| 項目 | 值 |
|------|-----|
| 類型 | 效能 |
| 指標 | toggle 後 < 500ms 內套用完成 |

---

## 介面規格

### AutoLaunchService

```dart
abstract class AutoLaunchService {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}
```

預設實作 `LaunchAtStartupAutoLaunchService` 走 `launch_at_startup` 套件。

## 錯誤處理

| 錯誤場景 | 錯誤碼 | 處理方式 | 使用者提示 |
|---------|--------|---------|-----------|
| 套件未在 macOS 上 setup | E_AUTOLAUNCH_INIT | log + 視為 disabled | stderr |
| enable 失敗（缺少權限 / sandbox） | E_AUTOLAUNCH_ENABLE | log + 不更新 settings | dialog 提示 |
| disable 失敗 | E_AUTOLAUNCH_DISABLE | log + 維持 enabled UI 狀態 | dialog 提示 |

## 設計約束

| 約束 | 說明 | 影響 |
|------|------|------|
| 不開放使用者自訂啟動引數 | 開機啟動時不帶 `--screen=N`，由儲存的 targetScreenIndex 決定 | 設計簡單 |
| 開機啟動只影響 macOS | Windows 在 v1.1.x 才有對應實作 | 跨平台時補 SPEC |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

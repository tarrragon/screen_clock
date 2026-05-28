---
id: UC-03
title: "退出遮罩"
status: draft
source_proposal: PROP-001
created: "2026-05-29"
updated: "2026-05-29"
version: "1.0"

primary_actor: "桌面使用者"
secondary_actors: []

platform: app
extension_status: not-applicable

related_specs:
  - SPEC-001
related_usecases:
  - UC-01
ticket_refs: []
---

# UC-03: 退出遮罩

## 基本資訊

| 項目 | 值 |
|------|-----|
| 用例 ID | UC-03 |
| 用例名稱 | 退出遮罩 |
| 主要行為者 | 桌面使用者 |
| 利益關係人 | 使用者：可隨時關閉時鐘；系統：app 釋放所有資源 |
| 前置條件 | UC-01 已完成；遮罩在執行中 |
| 成功保證 | app 正常退出；timer 已取消；視窗關閉；無殘留 process |

## 主要成功場景

1. **觸發退出**
   - 使用者按下 Cmd+Q
   - 或於 Dock app icon 右鍵 → Quit
   - 或從 macOS Activity Monitor 結束 process

2. **取消 timer**
   - app 的 Clock widget `dispose()` 被呼叫
   - `Timer.periodic` 被 cancel

3. **關閉視窗**
   - `window_manager` 關閉視窗
   - 視窗從螢幕消失

4. **結束 process**
   - Flutter runtime 退出
   - 所有資源釋放

## 替代場景

### 03a: 使用 Activity Monitor 強制結束

**觸發條件**：使用者於 Activity Monitor 對 process 按 Force Quit

1. macOS 直接終止 process
2. timer 與視窗未經 dispose 流程直接被回收
3. （MVP 接受此行為；不額外處理）

## 例外場景

### EX-03-01: timer 未取消

| 項目 | 值 |
|------|-----|
| 觸發條件 | Clock widget `dispose()` 未正確取消 timer |
| 錯誤碼 | E_TIMER_LEAK |
| 處理方式 | Dart runtime 可能輸出 unhandled timer warning |
| 使用者提示 | 無 |
| 恢復策略 | 屬實作 bug；需在實作時於 `dispose()` 確保 `timer?.cancel()` |

### EX-03-02: 視窗無法關閉

| 項目 | 值 |
|------|-----|
| 觸發條件 | `window_manager` 在某 macOS 版本退出時 hang |
| 錯誤碼 | E_WM_DESTROY |
| 處理方式 | 使用者需手動 Force Quit |
| 使用者提示 | 無 |
| 恢復策略 | Activity Monitor → Force Quit |

## 驗收條件

### 功能驗收

- [ ] Cmd+Q 後 app 於 1 秒內退出
- [ ] Dock 右鍵 Quit 行為等同 Cmd+Q
- [ ] 退出後 Activity Monitor 中無殘留 process
- [ ] 退出後可立即重新啟動

### 邊界條件

- [ ] timer 在退出時有被 cancel（透過 debug 模式驗證無 timer leak warning）
- [ ] 多次啟動 / 退出 cycle（10 次以上）無資源洩漏

### 效能要求

| 指標 | 目標值 |
|------|--------|
| Cmd+Q 到 process 結束 | < 1000 ms |

## UI 互動流程

```
[使用者: Cmd+Q]
       │
       ▼
[macOS: 發送 terminate 訊號]
       │
       ▼
[Flutter: 觸發 widget tree dispose]
       │
       ▼
[Clock widget: dispose → timer.cancel()]
       │
       ▼
[window_manager: 關閉視窗]
       │
       ▼
[process 結束]
```

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-05-29 | 初始版本 |

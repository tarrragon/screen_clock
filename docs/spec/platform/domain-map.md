---
id: DOMAIN-MAP-platform
domain: "platform"
source_specs: [SPEC-001, SPEC-003, SPEC-006]
related_usecases: []
created: "2026-07-29"
updated: "2026-07-29"
---

# Domain Map — platform

> 產出來源：1.4.0-W1-006。本文件界定 DDD domain bundle 邊界，作為切層、派發與測試策略的權威依據。
> 與 SPEC-001（透明全螢幕遮罩視窗）、SPEC-003（多螢幕選擇）、SPEC-006（macOS 開機自動啟動）交叉引用。

## 1. 目的與 UC / DDD 正交關係

本文件補上 platform domain 的**水平視角**：按業務知識把 domain 切成 bundle。UC 是**垂直視角**（一條使用者劇本貫穿 UI → 邏輯 → 持久化），一個 UC 橫切多個 bundle。

**核心準則**：domain 層保持純——無 I/O、無 UI 形狀、對顯示偏好（如語系、格式化、單位換算）與框架一無所知。違反則 domain 被 I/O 與顯示偏好污染，測試被迫拖真實依賴、無法純函式驗證。

## 2. 分層與依賴方向

**單 aggregate 形態**（platform domain 以偵測與配置為主）：
```
presentation (UI 層 + 狀態管理)
        │ 依賴（單向）
        ▼
domain read-model（螢幕偵測、全螢幕偵測）
        │ 依賴（單向）
        ▼
domain aggregate + VO（ScreenArg 值物件）
        ▲ 單向
        │ 依賴
data（auto_launch_service 持久化 + window_manager 平台 API）
```

**依賴方向底線（不可違反）**：

- domain 不得 import data / presentation / UI 框架 / 外部服務。違反則喪失純函式可測性。
- platform domain 不得依賴 input / display / data-management / user-experience domain。Platform 是基礎設施供應者，被其他 domain 依賴，不反向依賴。
- read-model bundle 依賴 aggregate，彼此不互相依賴。違反則單一概念改動沿耦合鏈擴散。

## 3. Bundle 界定表

| Bundle | 分類 | 納入概念 | 排除 | 目標路徑 | 測試層/方法 | 實作狀態 | 資料契約文件引用連結 |
|---|---|---|---|---|---|---|---|
| ScreenArg | supporting VO | CLI 引數解析 `--screen=N`（SPEC-003 FR-02） | 螢幕偵測邏輯 | `lib/platform/screen_arg.dart` | unit：邊界值（null/0/負數/多次出現） | 已實作 | N/A |
| DisplayDetector | read-model | 可用螢幕清單偵測、螢幕熱插拔（SPEC-003 FR-01, FR-03, FR-05） | CLI 引數解析 | `lib/platform/display_detector.dart` | unit：螢幕清單偵測邏輯 | 已實作 | N/A |
| FullscreenDetector | read-model | 全螢幕應用偵測（SPEC-001 FR-01 視窗尺寸貼合） | 視窗管理 API | `lib/platform/fullscreen_detector.dart` | unit：偵測邏輯 | 已實作 | N/A |
| WindowManager 整合 | 非 domain（infra） | 透明背景、無邊框、無陰影、永遠置頂、click-through、鍵盤焦點（SPEC-001 FR-01~06） | domain 計算 | `lib/main.dart`（window_manager 初始化） | integration：平台 API 整合 | 已實作 | N/A |
| AutoLaunchService | 非 domain（infra） | 開機自動啟動啟用/停用/查詢（SPEC-006 FR-01, FR-02） | domain 計算 | `lib/services/auto_launch_service.dart` | unit：啟用/停用邏輯 | 已實作 | N/A |

### Bundle 不變式清單（per-bundle）

| Bundle | 不變式（每條可轉一個 unit test） |
|---|---|
| ScreenArg | 未提供/格式錯誤/非數字/負數引數回傳 null；多次出現取最後一次 |
| DisplayDetector | 螢幕清單至少包含主螢幕；熱插拔事件觸發重新偵測 |
| FullscreenDetector | 全螢幕狀態變更通知觀察者 |
| AutoLaunchService | 啟用/停用操作冪等；查詢狀態反映最後一次操作 |

## 4. 邊界決策

### 4.1 WindowManager 整合歸屬

WindowManager 初始化（透明、frameless、always-on-top、click-through）目前集中在 `main.dart`，非獨立 bundle。這些是平台基礎設施配置，歸為 infra 層。若未來提取為獨立 service 類別，再建立獨立 bundle。此為現況描述。

### 4.2 AutoLaunchService 歸 platform 而非 data-management

開機啟動是平台能力（macOS LaunchAgent），非使用者資料管理。雖然啟用狀態需持久化，但持久化是 service 內部實作細節，domain 職責屬 platform。

## 5. 對實作票的切分指引

| 票 | 層 | domain map 對齊指引 |
|---|---|---|
| 視窗透明/click-through 票 | infra | WindowManager 整合，依賴方向見 §2 |
| 多螢幕偵測票 | domain | DisplayDetector + ScreenArg，依 §3 拆 bundle |
| 開機自動啟動票 | infra | AutoLaunchService，持久化細節屬 service 內部 |

## 6. 觀察到的技術債（待追蹤）

- WindowManager 初始化目前集中在 main.dart，未提取為獨立 service 類別。影響低，暫不追蹤。

## 7. FR → Bundle 覆蓋對照

### SPEC-001（透明全螢幕遮罩視窗）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | WindowManager 整合（infra）+ FullscreenDetector | 全螢幕覆蓋 + 尺寸貼合 |
| FR-02 | WindowManager 整合（infra） | 真透明背景（macOS 原生設定） |
| FR-03 | WindowManager 整合（infra） | 無邊框、無陰影 |
| FR-04 | WindowManager 整合（infra） | 永遠置頂 |
| FR-05 | WindowManager 整合（infra） | click-through |
| FR-06 | WindowManager 整合（infra） | 鍵盤焦點不被攔截 |

### SPEC-003（多螢幕選擇）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | DisplayDetector | 偵測可用螢幕清單 |
| FR-02 | ScreenArg | CLI 引數指定目標螢幕 |
| FR-03 | DisplayDetector | 視窗尺寸與位置貼合 |
| FR-04 | ScreenArg + DisplayDetector | 偵測失敗/引數錯誤 fallback |
| FR-05 | DisplayDetector | 螢幕熱插拔處理 |

### SPEC-006（macOS 開機自動啟動）

| FR 群 | 覆蓋 | 備註 |
|---|---|---|
| FR-01 | AutoLaunchService（infra） | 啟用/停用開機啟動 |
| FR-02 | AutoLaunchService（infra） | 查詢當前狀態 |

---

**Last Updated**: 2026-07-29 | **Source**: 1.4.0-W1-006

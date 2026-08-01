---
id: SPEC-009
title: "使用者設定持久化資料契約"
status: draft
source_proposal: null
created: "2026-07-29"
updated: "2026-08-01"
version: "1.3"
owner: sassafras-data-administrator

# Domain 歸屬
domain: data-management
subdomain: "data-contract"

# 關聯
related_specs: [SPEC-004, SPEC-007, SPEC-008]
---

# 使用者設定持久化 資料契約

## 概述

本契約涵蓋 `SettingsModel`（`lib/models/settings_model.dart`）的完整持久化約定：schema v1 至 v3 的既成欄位語意與版本演進、v4 的規劃條目，以及 `SettingsService`（`lib/services/settings_service.dart`）的讀寫與降級行為。

A 區記錄換一種儲存後端（例如改用 SQLite 或應用支援目錄下的 JSON 檔）仍必須成立的邏輯約定；B 區記錄綁定當前 `shared_preferences` 單鍵 JSON 字串實作的細節，儲存後端更換時本區需整段重寫。

**資料來源**：欄位與行為一律以實際程式碼為準（`lib/models/settings_model.dart`、`lib/services/settings_service.dart`、`lib/state/settings_controller.dart`、`lib/app_constants.dart`），歷史版本差異以 git 歷史逐版本比對取得。v4 已於 `1.4.0-W1-001.2` 落地為 code。

## 可攜性邊界原則

本文件依「儲存後端遷移後是否仍成立」分兩區。判準：若把 `shared_preferences` 換成 SQLite 或獨立 JSON 檔後仍需遵守，屬 A 區；只在當前實作下成立，屬 B 區。

| 區塊 | 判準 | 儲存後端遷移後 |
|------|------|-------------|
| A 區：邏輯契約 | DB-agnostic，描述欄位語意、不變式、版本演進保證 | 仍成立，照搬 |
| B 區：實作綁定 | DB-specific，描述 `shared_preferences` + JSON 字串的實現機制 | 需依新後端重寫 |

---

## A 區：邏輯契約（DB-agnostic）

### A.1 表/欄位語意

單一邏輯實體 `SettingsModel`，一份使用者設定為一筆紀錄（單例）。下表為 schema v4（現行 code）的完整欄位集。

| 欄位 | 型別 | 單位/格式 | 值域 | 說明 |
|------|------|----------|------|------|
| `schemaVersion` | int | 整數版本號 | >= 1，現行寫入值 4 | 寫出時恆為 code 常數；見 A.3 INV-02 與 A.3 註記（讀取端不使用） |
| `fontSize` | double | 邏輯像素 | > 0，預設 `AppSizes.clockFontSize` | 時鐘字級（SPEC-002 FR-04） |
| `fillColor` | Color | ARGB32 整數 | 0x00000000–0xFFFFFFFF | 時鐘填色 |
| `strokeColor` | Color | ARGB32 整數 | 0x00000000–0xFFFFFFFF | 時鐘描邊色 |
| `strokeWidth` | double | 邏輯像素 | >= 0，預設 `AppSizes.clockStrokeWidth` | 描邊寬度 |
| `timeFormat` | String | 時間格式字串 | 預設 `AppText.timeFormat` | 時間顯示格式（SPEC-002 FR-01） |
| `targetScreenIndex` | int | 螢幕索引 | >= 0，預設 0 | 目標顯示螢幕（SPEC-003 FR-02） |
| `autoLaunch` | bool | — | true / false，預設 false | 開機啟動（SPEC-006） |
| `birthDate` | DateTime? | epoch 毫秒（整數） | 可為 null（未設定） | 生命計時模式基準日；**唯一可為 null 的欄位** |
| `lifeTimerMode` | bool | — | true / false，預設 false | 生命計時模式開關 |
| `bindings` | List\<MouseBinding\> | 物件清單 | 同 `buttonNumber` 已去重 | 滑鼠按鍵綁定清單（SPEC-007 FR-02） |
| `bindingsSeeded` | bool | — | true / false | **欄位級 migration 旗標**（非使用者設定）；一次性預設綁定 seed 遷移旗標；缺鍵視為 false（未遷移）。與 `schemaVersion` 正交，見下方「欄位級 migration 旗標」說明 |
| `cursorLocatorEnabled` | bool | — | true / false，預設 true | 游標定位器啟用開關（SPEC-008 FR-06） |
| `cursorLocatorEffectDurationSeconds` | double | 秒 | 0.5–3.0，預設 1.5 | 游標定位器特效時長（SPEC-008 FR-06）；值域僅由 UI 元件與預設值保證，持久層不驗證 |
| `cursorLocatorPrimaryColor` | Color | ARGB32 整數 | 0x00000000–0xFFFFFFFF，預設 `0xFF2196F3`（系統藍） | 游標定位器主色調（SPEC-008 FR-06） |

**Schema 版本演進**（逐版本以 git 比對 `toJson()` 欄位集取得）：

| schema | 引入 commit | 新增欄位 | 舊版讀入保證 |
|--------|------------|---------|-------------|
| 1 | `bd83aea` feat(1.0.0-W1-002) | `fontSize`、`fillColor`、`strokeColor`、`strokeWidth`、`timeFormat`、`targetScreenIndex`、`autoLaunch` | 初版，無前置版本 |
| 2 | `afa3d67` feat: 生命計時模式 | `lifeTimerMode`、`birthDate` | v1 資料缺兩欄 → `lifeTimerMode` 補 false、`birthDate` 補 null |
| 3 | `d05724a` feat(1.3.0-W2-002) | `bindings` | v2 資料缺 `bindings` → 解析為空清單 |
| 3（同版擴充） | `10284df` feat(1.3.0-W3-002) | `bindingsSeeded` | 缺鍵 → false，觸發一次性 seed 遷移（見 A.6 / B.3）。**未提升 schemaVersion**，v3 內部存在「有無 `bindingsSeeded`」兩種資料形態 |
| 4 | `1.4.0-W1-001.2` | 游標定位器三項設定：`cursorLocatorEnabled`（bool，預設 true）、`cursorLocatorEffectDurationSeconds`（double 秒，預設 1.5，範圍 0.5–3.0）、`cursorLocatorPrimaryColor`（Color ARGB32 int，預設 `0xFF2196F3` 系統藍） | v3 及更早資料缺欄 → 補上述預設值，不拋例外 |

> v4 列來源為 **`lib/models/settings_model.dart`（1.4.0-W1-001.2 落地）**。三個欄位的 Dart 欄位名與 JSON 鍵名一致（同 SettingsModel 其餘欄位慣例，未經 `AppSettingsKeys` 間接層）。`cursorLocatorPrimaryColor` 預設值刻意不用 `Colors.blue`（`MaterialColor` 子型別，round-trip 後與 `Color` 比較 `==` 會因 `runtimeType` 不同而失效），改採同色值的 `Color(0xFF2196F3)`。

**欄位級 migration 旗標**（`bindingsSeeded` 及未來同類欄位）：

| 面向 | `schemaVersion` | 欄位級 migration 旗標 |
|------|-----------------|----------------------|
| 回答的問題 | 這筆資料由哪一版 code 寫出 | 這筆資料是否已執行過某一次特定 migration |
| 解析端是否讀取 | 否（`fromJson()` 完全不讀，見 A.3 註記） | 是（旗標值直接決定 migration 是否觸發） |
| 缺鍵 fallback | 不適用 | 字面 `false`（**不是** `defaults()` 值） |
| 生命週期 | 隨每次 schema 演進遞增 | 單向一次性，true 後不再回 false（INV-07） |

兩者語意正交：旗標不表達版本、版本不表達遷移狀態，不得互相取代或合併。

`bindingsSeeded` 的 fallback 為字面 `false` 而非 `defaults()` 的 `true`（`settings_model.dart` 的 `fromJson`），是刻意設計：若取 `defaults()` 值，舊資料會被誤判為已遷移，`_migrateBindingSeed()` 將永不觸發。此為全表唯一不遵循「缺欄取 `defaults()`」通則的欄位。

其直接後果：**同為 `schemaVersion: 3` 存在兩種資料形態**（`10284df` 之前寫出者無 `bindingsSeeded`，之後寫出者有）。此為既定事實而非缺陷，任何針對 v3 的相容性測試須同時涵蓋 v3-early 與 v3-late 兩形態。

> **與 SPEC-004 分工**：SPEC-004 `## 資料模型` 與 FR-01 聚焦「設定面板功能需要哪些欄位」；本節聚焦欄位的格式、值域與版本邊界約束。
>
> **與 SPEC-004 同步狀態**：SPEC-004 FR-01 欄位表（現補齊至 14 欄）、FR-02 `schemaVersion` 現況值、NFR-02 相容性策略描述已更新至與本節一致，過往「停留在 v1 時點」的落差已回補，不再重複記錄。

### A.2 狀態責任分層

| 欄位/表 | 分層 | 說明 |
|--------|------|------|
| `fontSize`、`fillColor`、`strokeColor`、`strokeWidth`、`timeFormat`、`targetScreenIndex`、`birthDate`、`lifeTimerMode`、`bindings` | canonical | 使用者意圖的唯一來源，僅由設定面板經 `SettingsController` 寫入 |
| `autoLaunch` | canonical，但與 OS 狀態對帳 | 持久層為 canonical；`SettingsController.persist()` 呼叫 `AutoLaunchService.setEnabled()` 後若 OS 回報狀態不符，以 OS 實際狀態回寫覆蓋（OS 為該欄的最終仲裁者） |
| `schemaVersion` | 追蹤欄位 | 僅標示寫出時的 code 版本；不參與任何解析決策（見 A.3 註記） |
| `bindingsSeeded` | 追蹤欄位 | 一次性遷移旗標，不表達使用者意圖，不參與業務計算 |

### A.3 不變式清單

| 編號 | 不變式 | 對應 domain-map 條目 |
|------|--------|----------------------|
| INV-01 | 除 `birthDate` 外所有欄位 non-null | 本文件新增（SPEC-004 FR-01「所有欄位 non-null」的 v2 後修正版） |
| INV-02 | `schemaVersion` 單調遞增；寫出值恆等於當前 code 常數 | 本文件新增 |
| INV-03 | 欄位一旦加入即不移除、不改型別；schema 演進只允許加欄 | SPEC-004「設計約束：MVP 不做 migration」 |
| INV-04 | `fromJson()` 對任意輸入永不拋例外；缺欄或型別錯誤 → 該欄取 `defaults()` 值 | SPEC-004 FR-02 |
| INV-05 | `fromJson(model.toJson()) == model`（round-trip 相等） | SPEC-004 FR-02 驗收標準 |
| INV-06 | `bindings` 內 `buttonNumber` 唯一（`dedupeBindingsByButton` 收斂） | SPEC-007 FR-02 |
| INV-07 | `bindingsSeeded` 單向：一旦為 true 不再回 false | 本文件新增 |
| INV-08 | 讀取任一舊版資料不得使 app 崩潰；最壞情況降級為 `defaults()` | SPEC-004 FR-03 |
| INV-09 | `SettingsModel` 為不可變物件；變更一律經 `copyWith` 產生新實例 | SPEC-004 FR-01 |

> **`schemaVersion` 的實際角色（重要）**：`fromJson()` 完全不讀取 `schemaVersion`，版本相容全靠「欄位缺失 → 取預設值」達成。因此 `schemaVersion` 是**單向的稽核標記**：只在 `toJson()` 寫出，從不參與解析，不作為任何分支依據。實測佐證（1.4.0-W1-011 實驗 E1）：`schemaVersion` 為缺失、`99`、`'garbage'`、`-1` 四種輸入所產生的 `SettingsModel` 完全相等。版本號可為任意值甚至不存在，解析行為不變。
>
> 此設計的後果：無法對「同名欄位語意變更」做版本分支處理，故 INV-03（只加欄、不改型別）是相容性的必要前提，不可放寬。

#### migration 治理規則

本契約採「加欄 + 預設值 fallback」策略（B.3），不設版本分派層。為避免該策略在演進中被靜默侵蝕，以下規則對所有修改 `SettingsModel` 的變更生效：

| 規則 | 內容 |
|------|------|
| G-01 | 欄位級 migration 旗標得在**不提升 `schemaVersion`** 的情況下新增（`bindingsSeeded` 為既有先例） |
| G-02 | 但該次新增**必須登錄於 A.1 Schema 版本演進表**，以「N（同版擴充）」列標示引入 commit、新增欄位與缺鍵行為。未登錄的同版擴充視為違反本契約 |
| G-03 | 新增一般設定欄位（非旗標）必須提升 `schemaVersion` 並於演進表新增一列 |
| G-04 | 旗標累積達 **3 個**時，觸發「升級為版本分支解析」的評估（見下表 T-04） |

G-04 的理由：每個旗標為資料形態引入一次二分，N 個旗標即 2^N 種形態組合。旗標數 1 至 2 時，形態數（2 至 4）仍可由 fixture 矩陣窮舉；達 3 個時形態數為 8，窮舉成本超過改以 `schemaVersion` 分派的成本。

**現行旗標計數：1**（`bindingsSeeded`）。新增旗標時須同步更新此計數。

#### 升級為版本分支解析（方案 B）的觸發條件

「版本分支解析」指 `fromJson()` 讀取 `schemaVersion` 並依版本分派至對應解析路徑或 migration 函式鏈。出現下列**任一**可驗證條件時，必須先完成該升級，才能進行對應變更；不得以現行加欄策略硬做：

| 編號 | 觸發條件 | 依據（1.4.0-W1-011 實測後果） |
|------|---------|------------------------------|
| T-01 | 需變更既有欄位的**型別** | E2：不拋例外。可轉型時靜默寬鬆轉型（`targetScreenIndex: 2.9 → 2` 無條件截斷、`'3.5' → 3.5`、`'true' → true`）；不可轉型時靜默取預設。使用者資料被改值或重置且無訊號 |
| T-02 | 需變更既有欄位的**語意或單位** | E3：現行機制完全無法偵測。型別不變時舊值被新語意原樣接收，零例外零警示。`birthDate` 若由 epoch 毫秒改為 epoch 秒，`946684800` 會被解讀為 1970-01-12。錯誤會在下次 `save()` 被持久化，原始資料永久遺失 |
| T-03 | 需**移除**既有欄位 | E4：方向 A（新版讀舊資料）安全，多餘欄位靜默忽略；方向 B（舊版讀新資料）造成 write-back 截斷，見 A.5 |
| T-04 | 欄位級 migration 旗標累積達 **3 個** | 形態組合數達 8，超過版本分派成本（G-04） |

四項條件皆為可判定事件（變更意圖明確、旗標數可清點），非時間性或主觀判斷。判定為觸發時，應建立獨立 ticket 執行升級，該 ticket 完成前對應變更維持阻塞。

**未觸發時維持現狀的理由**：實測顯示現行策略的缺口是「INV-03 違規無偵測訊號」而非「無法解析舊資料」。純加欄變更（如 schema 4）在 INV-03 前提下由 E4a 證實安全。因此防線設於 golden fixture 迴歸測試（涵蓋 v1 / v2 / v3-early / v3-late 四形態，1.4.0-W1-015），而非預先重構解析層。

### A.4 交易邊界

| 交易邊界 | 涵蓋寫入 | 說明 |
|---------|---------|------|
| 整份設定 | 全部欄位一次寫出 | `SettingsModel` 為單一聚合，序列化為一份 payload 一次寫入；不存在部分欄位寫入成功、部分失敗的中間態 |
| `autoLaunch` OS 對帳 | 持久層寫入 + OS 開機項設定 | 兩者**非原子**：`persist()` 先寫持久層再設 OS，OS 回報不符時再寫一次。中途失敗可能留下持久層與 OS 不一致，下次 `persist()` 修正 |
| `bindingsSeeded` 遷移 | 讀取 → 補綁定 → 回寫 | 讀寫分離的 read-modify-write，非原子；單機單行程情境下無競爭，見 A.6 |

### A.5 錯誤語意契約

本 domain **不定義型別化 domain 例外**：所有錯誤在資料層被吸收為降級行為並記錄日誌，不向上層拋出（SPEC-004 FR-03）。

| 錯誤類型 | 對應行為 | 觸發情境 |
|--------------|------------------|---------|
| 儲存後端初始化失敗 | 回 `defaults()` + 日誌（SPEC-004 E_PREFS_INIT） | 平台 channel 不可用 |
| payload 非物件 / 反序列化失敗 | 回 `defaults()` + 日誌（E_PREFS_PARSE） | 資料損毀、被外部竄改 |
| 單一欄位型別錯誤 | 該欄取預設值，其餘欄位照常解析 | 手動編輯、跨版本型別誤植 |
| `bindings` 單筆解析失敗 / 未知 action 型別 | 略過該筆，其餘保留 | 舊版寫入未知動作型別 |
| 寫入 I/O 例外 | 吞掉 + 日誌（E_PREFS_SAVE），記憶體狀態維持 | 磁碟或平台錯誤 |
| unique / FK / CHECK 違反 | 不適用 | 當前無關聯式約束層 |

> **契約後果**：呼叫端無法區分「首次啟動」與「資料損毀」——兩者都回 `defaults()`。若未來需要區分（例如提示使用者設定遺失），須在此契約新增回傳型別而非僅改實作。

#### 已接受風險：降級寫回截斷（direction B）

| 項目 | 內容 |
|------|------|
| 風險 | 使用者以新版 app 寫出資料後，回退至舊版 app 執行。舊版 `fromJson()` 只認得自己那代的鍵，新欄位靜默丟棄；舊版一旦 `save()`，`toJson()` 全量重寫，新欄位資料**永久遺失** |
| 實測佐證 | 1.4.0-W1-011 實驗 E4b：v1 版解析新版 payload 後，`schemaVersion`、`lifeTimerMode`、`bindings`、`bindingsSeeded` 全數靜默丟棄 |
| 判定 | **已接受風險**，不建修復 ticket |
| 不可修復的理由 | 防護必須由**讀取端**執行，而讀取端是已發布的舊版 binary。舊版 binary 不受任何新版程式碼或本契約約束——今日新增的欄位保留邏輯，只能保護今日之後發布的版本讀取更未來的資料，對已在使用者機器上的舊版無效。此為「向前相容需在過去實作」的結構性限制，非實作缺漏 |
| 殘餘風險控制 | macOS app 降版需使用者主動替換 bundle，非自動路徑，發生率低但非零。無遙測可量測實際發生率 |
| 重新評估觸發 | 若本專案導入自動更新且支援自動回滾（rollback 使降版成為非使用者主動的自動路徑），此風險須重新評估並建立對應 ticket |

### A.6 恢復模型

| 情境 | 驗證方式 |
|------|---------|
| 備份還原 | **本專案無自動備份機制**。使用者層級的復原手段為刪除儲存項後重新設定（等同回到 `defaults()`）。還原後驗證：讀入不拋例外、`fromJson(toJson())` round-trip 相等、`bindings` 無重複 `buttonNumber` |
| 資料損毀 | 讀取降級為 `defaults()`；下一次寫入即以完整合法 payload 覆蓋損毀內容 |
| 跨版本降級（新版寫入後被舊版讀取） | **不保證**：`fromJson()` 只挑已知鍵、`toJson()` 全量重寫，未知欄位不被保留。以新版寫入後再用舊版 app 儲存，新欄位資料永久遺失。此為已知契約限制，非缺陷；已接受風險的完整判定與不可修復理由見 A.5「已接受風險：降級寫回截斷（direction B）」 |
| `bindingsSeeded` 遷移中斷 | 旗標與綁定同一份 payload 寫出，中斷則旗標維持 false，下次啟動重跑遷移（冪等：綁定非空時不覆蓋使用者自訂） |

---

## B 區：實作綁定（DB-specific）

> 本區綁定 `shared_preferences` + 單鍵 JSON 字串實作。更換儲存後端時需整段重寫，A 區不受影響。

### B.1 保證層歸屬

當前無資料庫約束層，所有不變式由應用層保證。

| 不變式編號 | 保證層 | 歸屬理由 |
|-----------|--------|---------|
| INV-01 | 應用層 | Dart null safety + `SettingsModel` 建構子必填參數（SPEC-004 FR-01） |
| INV-02 | 應用層 | `toJson()` 寫入 `SettingsModel.schemaVersion` 常數 |
| INV-03 | 應用層（人工） | 無機械強制；靠 code review 與本契約 A.3 註記把關。**這是本契約最脆弱的一條**：違反不會有任何自動化訊號，只在使用者升級後資料異常時才暴露 |
| INV-04 | 應用層 | `fromJson()` 全欄位走 `_asDouble` / `_asInt` / `_asBool` / `_asString` / `_asColor` / `_asDateTime` 容錯轉換，失敗回 null 再 fallback 預設 |
| INV-05 | 應用層 + 測試 | 由 round-trip 測試保證（SPEC-004 FR-02 驗收標準） |
| INV-06 | 應用層 | `dedupeBindingsByButton()` 於 `fromJson` 與 `copyWith` 兩處收斂 |
| INV-07 | 應用層 | `_migrateBindingSeed()` 僅由 false 寫向 true，無反向路徑 |
| INV-08 | 應用層 | `load()` 外層 try-catch 兜底回 `defaults()` |
| INV-09 | 應用層 | `@immutable` + 全 `final` 欄位 |

### B.2 邊界行為的引擎機制

| 邊界行為 | 引擎機制 | 說明 |
|---------|---------|------|
| 儲存位置 | `SharedPreferences` 單一 key `screen_clock.settings.v1` | 定義於 `PreferencesSettingsService.storageKey`；key 名含 `v1` 為歷史命名，**與 `schemaVersion` 無關**，不隨 schema 升版變動 |
| 序列化格式 | `jsonEncode(settings.toJson())` 存為單一 String | 非 `shared_preferences` 逐欄位存放；整份設定為一個 JSON 字串 |
| `Color` 編碼 | ARGB32 int（`(a<<24)\|(r<<16)\|(g<<8)\|b`，各通道 `(channel*255).round() & 0xff`） | 見 `_colorToInt`；解碼為 `Color(argb)` |
| `DateTime` 編碼 | epoch 毫秒 int | `birthDate` 為 null 時**不寫入該鍵**（Map 不存 null），非寫入 null |
| `bindings` 編碼 | 物件陣列，鍵名 `bindings`（`AppSettingsKeys.bindingsKey`） | 每筆由 `MouseBinding.toJson()` 產生 |
| `bindingsSeeded` 編碼 | bool，鍵名 `bindingsSeeded`（`AppSettingsKeys.bindingsSeededKey`） | 缺鍵解析為 false |
| 讀取時機 | app 啟動時，於 `windowManager.show()` 之前（SPEC-004 FR-04） | 讀失敗不阻擋啟動 |
| 寫入時機 | 設定面板「儲存」觸發 `SettingsController.persist()`；另有啟動期 seed 遷移的自動回寫 | 無自動定期寫入 |
| upsert | `prefs.setString(key, value)`，同鍵直接覆寫 | 無 ON CONFLICT 概念 |
| FK 刪除策略 | 不適用 | 無關聯式結構 |
| CHECK 違反例外 | 不適用 | 無 DB 層驗證；值域約束僅由 UI 元件與預設值保證，持久層不驗證 |
| 降級行為（讀不到 / 損毀） | 缺鍵或空字串 → `defaults()`；非 JSON 物件 → `defaults()` + `debugPrint`；例外 → `defaults()` + `debugPrint` | 見 `PreferencesSettingsService.load()` |
| 測試替身 | `InMemorySettingsService` | 記憶體實作，繞過平台 channel；契約行為（容錯降級）不在其覆蓋範圍 |

### B.3 Schema 演進策略與 Seed 資料政策

| 項目 | 決策 | 說明 |
|------|------|------|
| Schema 演進策略 | 支援演進，採「加欄 + 預設值 fallback」，無版本分支 migration | 無 `onUpgrade` 鉤子；`fromJson()` 不讀 `schemaVersion`。依賴規則：只要維持 INV-03（只加欄、不改型別、不刪欄），此策略成立。何時必須升級為以 `schemaVersion` 分派的顯式 migration 層，見 A.3「升級為版本分支解析（方案 B）的觸發條件」T-01 至 T-04 |
| 例外：命令式 migration | `_migrateBindingSeed()`（`PreferencesSettingsService`）是目前唯一的命令式遷移；其觸發依據 `bindingsSeeded` 這個欄位級 migration 旗標，治理規則見 A.3 G-01 至 G-04 | 觸發條件為 `bindingsSeeded == false`（含缺鍵），非版本號比較。行為：綁定為空才補入 `defaults().bindings`（避免覆蓋 v3 早期使用者自訂），無論如何標記 seeded 並立即回寫 |
| Seed 資料政策 | `SettingsModel.defaults()` 內含一筆預設綁定 | 側鍵拖曳滾動（`AppInputBinding.defaultDragScrollButton` + `DragScrollAction`，SPEC-007 FR-03），使功能首次啟動即可用；`defaults()` 的 `bindingsSeeded` 為 true |
| v4 演進 | 沿用加欄 + 預設值 fallback，不需命令式 migration | `1.4.0-W1-001.2` 落地確認：三項新設定皆有明確預設值，`fromJson()` 缺欄補預設值不拋例外，符合現行策略 |

---

## 欄位 × 既有載體對照表

| 欄位/章節 | 承載狀態 | 既有載體 | 說明 |
|----------|---------|---------|------|
| 表/欄位語意（單位/值域/格式） | 部分承載，本文件補約束細節 | SPEC-004 `## 資料模型` / FR-01 | SPEC-004 現已同步至 v4 欄位集，本文件補單位/值域/格式細節 |
| 不變式陳述 | 本文件新建完整清單並附編號 | 無 domain-map | 本專案尚無 domain-map；INV-03/INV-04 呼應 SPEC-004 設計約束與 FR-02 |
| 契約 ↔ 測試對應 | 未承載 | 無 `docs/traceability.yaml` | 本專案尚無 traceability 第三軸；INV 編號待後續建立對應測試索引 |
| 可攜性分區（A/B 兩區結構） | 新建 | 無 | — |
| 狀態責任分層 | 新建 | 無 | — |
| 交易邊界 | 新建 | 無 | — |
| 錯誤語意契約 | 部分承載 | SPEC-004 `## 錯誤處理`（E_PREFS_*） | 本文件補「不定義型別化例外」的契約後果 |
| 恢復模型 | 新建 | 無 | 含「跨版本降級不保證」的顯式限制聲明 |
| 保證層歸屬 | 新建 | 無 | — |
| Schema 演進策略 | 部分承載 | SPEC-004 NFR-02 / 設計約束 | 本文件補現行 v1–v4 實況、治理規則（G-01–G-04 / T-01–T-04）與唯一命令式 migration |

---

## 適用判準（本文件是否需要撰寫）

| 旗標 | 判定 | 理由 |
|------|------|------|
| 契約文件（要/不要） | 要 | 多 AI 代理協作、跨版本交接；schema 已演進三版且 SPEC-004 未同步，欄位真相僅存在於 code 與 git 歷史，缺乏可交接載體 |
| migration 治理（要/不要） | 要 | 已存在一條命令式 migration（`_migrateBindingSeed`）且未綁 schemaVersion；v4 即將升版，需明文治理規則避免相容性回歸 |
| dormant 豁免（如適用） | 不適用 | 設定持久化為每次啟動必經路徑，有明確 production 觸達 |

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-07-29 | 初始版本：記錄 schema v1–v3 既成事實與 v4 規劃條目（1.4.0-W1-007） |
| 1.1 | 2026-07-29 | 回填 1.4.0-W1-011 評估結論：A.1 `bindingsSeeded` 標註為欄位級 migration 旗標並補正交性說明；A.3 補 `schemaVersion` 單向稽核標記的實測佐證、migration 治理規則 G-01–G-04、版本分支解析升級觸發條件 T-01–T-04；A.5 記錄降級寫回截斷（direction B）為已接受風險（1.4.0-W1-016） |
| 1.2 | 2026-07-31 | 回填 1.4.0-W1-001.2 落地結果：A.1 主表與版本演進表 v4 列由「規劃中」轉為實作事實，補上三個欄位的實際 Dart/JSON 鍵名（`cursorLocatorEnabled` / `cursorLocatorEffectDurationSeconds` / `cursorLocatorPrimaryColor`）與 `cursorLocatorPrimaryColor` 預設值改用 `Color(0xFF2196F3)`（非 `Colors.blue`）的理由；B.3 v4 演進列更新為已確認 |
| 1.3 | 2026-08-01 | SPEC-004 已同步更新至 code 現況，A.1「已知落差」段落改為「與 SPEC-004 同步狀態」確認說明，移除已回補的落差記錄 |

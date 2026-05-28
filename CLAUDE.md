# CLAUDE.md

本文件為 Claude Code 在此專案中的開發指導規範。

---

## 1. 專案身份

**專案名稱**: screen_clock

**專案目標**: 桌面螢幕透明遮罩時鐘。全螢幕透明覆蓋在指定螢幕上，中央顯示時間；視窗點擊穿透（click-through），不阻擋底下程式的鍵盤滑鼠操作。v1.0 之前只支援 macOS；Windows 留待 v1.1.x。

**專案類型**: Flutter Desktop（v1.0 前 macOS only；v1.1.x 起加入 Windows）

| 項目 | 值 |
|------|------|
| **語言** | Dart |
| **Flutter SDK** | Dart `^3.11.1`（隨之對應的 Flutter stable） |
| **實作代理人** | parsley-flutter-developer |
| **識別特徵** | `pubspec.yaml`、`macos/`、`windows/` 平台目錄存在；無 `android/`、`ios/`、`web/` 的執行需求（雖然 scaffold 包含這些目錄） |

**啟用的 MCP/Plugin**:

- `dart` — Dart/Flutter 語意工具（已於 `settings.local.json` 的 `enabledMcpjsonServers` 啟用）

---

## 2. 核心價值

@.claude/rules/core/quality-baseline.md

---

## 3. 規則系統

@.claude/rules/README.md

---

## 4. Skill 指令

@.claude/pm-rules/skill-index.md

---

## 5. 方法論參考

@.claude/pm-rules/methodology-index.md

---

## 6. 技術選型與架構決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 平台優先順序 | v1.0 之前只做 macOS；v1.1.x 起加 Windows | macOS 的透明 + click-through 支援較成熟；Windows 的 layered window 需額外處理且風險較高，延後到 1.0 之後處理 |
| 視窗管理 | `window_manager` 套件 | 跨 macOS/Windows 提供 frameless、always-on-top、ignore-mouse-events 的統一 API |
| 透明背景 (macOS) | `MainFlutterWindow.swift` 內設 `isOpaque = false; backgroundColor = .clear` | window_manager 無法在 macOS 完整設定原生視窗透明，需平台原生程式碼補足 |
| 透明背景 (Windows) | 留待 v1.1.x；屆時於 `windows/runner/` 改用 layered window（`WS_EX_LAYERED \| WS_EX_TRANSPARENT`） | 純 `setBackgroundColor(transparent)` 在 Windows 可能無法完全透明，需 layered window。MVP→v1.0 不處理 |
| 點擊穿透 | `windowManager.setIgnoreMouseEvents(true)` | 核心需求：底下程式仍可操作 |
| 互動切換策略 | 預設全穿透；若日後加入可互動 UI（設定面板等），需動態切換：滑鼠進入互動區呼叫 `setIgnoreMouseEvents(false)`，離開後設回 `true` | 全穿透與可互動互斥，需用事件驅動切換而非單一狀態 |
| 永遠置頂 | `windowManager.setAlwaysOnTop(true)` | 確保時鐘始終可見 |
| 視窗外觀 | frameless + 無陰影（`setHasShadow(false)`） | 遮罩風格需要無邊框、無視覺干擾 |
| 多螢幕選擇 | 待規劃 | 目前先單螢幕（主螢幕）；多螢幕選擇納入未來版本 |
| 常數集中 | 全專案常數統一於 `lib/app_constants.dart`（`AppText` / `AppSizes` / `AppColors` / `AppDurations` / `AppWindow`） | 嚴禁在任何程式碼中硬編碼字串字面值、尺寸數字、顏色、時間間隔、視窗旗標。所有來自規格的固定值都必須在此檔案命名後引用。v1.0.0 設定面板上線時，使用者可調項目改由 `SettingsModel` 注入；不可調項目保留於本檔 |

### 必要的平台原生改動

**macOS** — `macos/Runner/MainFlutterWindow.swift`：

```swift
override func awakeFromNib() {
    // ... existing code ...
    self.isOpaque = false
    self.backgroundColor = .clear
}
```

**Windows** — 推遲到 v1.1.x。屆時於 `windows/runner/` 加入 layered window 旗標（`WS_EX_LAYERED | WS_EX_TRANSPARENT`）。v1.0 之前不處理 Windows。

### main.dart 啟動骨架

```dart
WidgetsFlutterBinding.ensureInitialized();
await windowManager.ensureInitialized();
windowManager.waitUntilReadyToShow().then((_) async {
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(AppColors.overlayBackground);
  await windowManager.setAlwaysOnTop(AppWindow.isAlwaysOnTop);
  await windowManager.setIgnoreMouseEvents(AppWindow.ignoreMouseEvents);
  await windowManager.setHasShadow(AppWindow.hasShadow);
  await windowManager.show();
});
```

> 上方範例已示範常數引用方式：`Colors.transparent` 改為 `AppColors.overlayBackground`、`true/false` 改為 `AppWindow.*`。實作時須照此規範。

### 常數集中規範

`lib/app_constants.dart` 是專案唯一的常數來源（single source of truth）。

**禁止行為**：

| 反例 | 正解 |
|------|------|
| `Text('Screen Clock')` | `Text(AppText.appTitle)` |
| `fontSize: 120` | `fontSize: AppSizes.clockFontSize` |
| `color: Colors.white` | `color: AppColors.clockFill` |
| `Duration(seconds: 1)` | `AppDurations.clockTick` |
| `await windowManager.setAlwaysOnTop(true)` | `await windowManager.setAlwaysOnTop(AppWindow.isAlwaysOnTop)` |
| `Offset(0, 0)` 或 `Offset.zero` 用於視窗原點 | `AppSizes.windowOrigin` |

**例外（允許硬編碼的少數情境）**：

- Dart / Flutter 框架本身的列舉值（如 `FontWeight.w700`、`MainAxisAlignment.center`）
- 純結構性數字（如 `padLeft(2, '0')` 的位數）
- 平台原生程式碼（Swift / Win32），常數屬該平台側
- 測試檔案中的 fixture 值

**判斷準則**：抽常數的目的是讓字面值（literal）在使用處能以**能表達意圖的命名**取代，使程式碼本身說明「為什麼是這個值」，減少對註解的依賴。判斷不在於使用頻率，也不在於是否寫在 SPEC，而在於：

> 在使用處讀到這個字面值時，讀者能否一眼讀懂它的意義？

- 不能（例如 `fontSize: 120` 的 `120`、`Duration(seconds: 1)` 的 `1`、`Color(0xFF...)` 的色碼）→ 抽成有意義命名的常數，讓命名本身替代註解。
- 可以（例如平台框架的列舉值 `FontWeight.w700`、結構性參數 `padLeft(2, '0')` 的位數、測試 fixture）→ 不必為抽而抽。

簡言之：**字面值是否需要被命名才有意義？** 是 → 抽；否 → 留。

---

## 7. 專案文件

### 任務追蹤

| 文件 | 用途 |
|------|------|
| `docs/todolist.yaml` | 結構化版本索引（Source of Truth） |
| `docs/work-logs/` | 版本工作日誌 |
| `CHANGELOG.md` | 版本變更記錄 |
| `docs/work-logs/v{version}/tickets/` | Ticket 文件 |

### 關鍵原始碼

| 路徑 | 角色 |
|------|------|
| `lib/app_constants.dart` | 全專案常數集中檔（單一來源；見 Section 6「常數集中規範」） |
| `lib/main.dart` | 啟動流程（window_manager 初始化、視窗屬性設定） |

### 需求追蹤

| 文件 | 用途 |
|------|------|
| `docs/proposals/PROP-*.md` | 提案層級需求 |
| `docs/spec/{domain}/*.md` | SPEC 規格 |
| `docs/usecases/UC-*.md` | 用例 |
| `docs/proposals-tracking.yaml` | 提案追蹤索引 |

---

## 8. 里程碑

- **v0.0.x**：Flutter scaffold（已完成）
- **v0.1.x**：macOS 透明全螢幕視窗 + click-through 基礎能力（最小可行）
- **v0.2.x**：中央時鐘 widget（時間顯示、字型/顏色基本可調）
- **v0.3.x**：多螢幕選擇、目標螢幕指定
- **v1.0.0**：完整設定面板（樣式、位置、顯示螢幕、開機啟動）— macOS 為唯一支援平台
- **v1.1.x**：Windows 平台支援（layered window 透明）— 1.0 之前不考慮 Windows

---

*專案入口文件 - 詳細規則請參考 `.claude/rules/` 目錄*

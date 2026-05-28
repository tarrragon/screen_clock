# CLAUDE.md

本文件為 Claude Code 在此專案中的開發指導規範。

---

## 1. 專案身份

**專案名稱**: screen_clock

**專案目標**: 桌面螢幕透明遮罩時鐘。全螢幕透明覆蓋在指定螢幕上，中央顯示時間；視窗點擊穿透（click-through），不阻擋底下程式的鍵盤滑鼠操作。主要目標平台 macOS，次要平台 Windows。

**專案類型**: Flutter Desktop（macOS / Windows）

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
| 平台優先順序 | macOS 主、Windows 次 | macOS 的透明 + click-through 支援較成熟；Windows 的 layered window 需額外處理且風險較高 |
| 視窗管理 | `window_manager` 套件 | 跨 macOS/Windows 提供 frameless、always-on-top、ignore-mouse-events 的統一 API |
| 透明背景 (macOS) | `MainFlutterWindow.swift` 內設 `isOpaque = false; backgroundColor = .clear` | window_manager 無法在 macOS 完整設定原生視窗透明，需平台原生程式碼補足 |
| 透明背景 (Windows) | `windows/runner/` 改用 layered window（`WS_EX_LAYERED \| WS_EX_TRANSPARENT`）做後備方案 | 純 `setBackgroundColor(transparent)` 在 Windows 可能無法完全透明，需 layered window |
| 點擊穿透 | `windowManager.setIgnoreMouseEvents(true)` | 核心需求：底下程式仍可操作 |
| 互動切換策略 | 預設全穿透；若日後加入可互動 UI（設定面板等），需動態切換：滑鼠進入互動區呼叫 `setIgnoreMouseEvents(false)`，離開後設回 `true` | 全穿透與可互動互斥，需用事件驅動切換而非單一狀態 |
| 永遠置頂 | `windowManager.setAlwaysOnTop(true)` | 確保時鐘始終可見 |
| 視窗外觀 | frameless + 無陰影（`setHasShadow(false)`） | 遮罩風格需要無邊框、無視覺干擾 |
| 多螢幕選擇 | 待規劃 | 目前先單螢幕（主螢幕）；多螢幕選擇納入未來版本 |

### 必要的平台原生改動

**macOS** — `macos/Runner/MainFlutterWindow.swift`：

```swift
override func awakeFromNib() {
    // ... existing code ...
    self.isOpaque = false
    self.backgroundColor = .clear
}
```

**Windows** — `windows/runner/` 視需要加入 layered window 旗標（`WS_EX_LAYERED | WS_EX_TRANSPARENT`），實作時再評估必要性。

### main.dart 啟動骨架

```dart
WidgetsFlutterBinding.ensureInitialized();
await windowManager.ensureInitialized();
windowManager.waitUntilReadyToShow().then((_) async {
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setIgnoreMouseEvents(true);
  await windowManager.setHasShadow(false);
  await windowManager.show();
});
```

---

## 7. 專案文件

### 任務追蹤

| 文件 | 用途 |
|------|------|
| `docs/todolist.yaml` | 結構化版本索引（Source of Truth） |
| `docs/work-logs/` | 版本工作日誌 |
| `CHANGELOG.md` | 版本變更記錄 |
| `docs/work-logs/v{version}/tickets/` | Ticket 文件 |

### 專案文件

待專案規模成長後補入規格與設計文件。目前僅有 Flutter scaffold 與本指導文件。

---

## 8. 里程碑

- **v0.0.x**：Flutter scaffold（已完成）
- **v0.1.x**：macOS 透明全螢幕視窗 + click-through 基礎能力（最小可行）
- **v0.2.x**：中央時鐘 widget（時間顯示、字型/顏色基本可調）
- **v0.3.x**：Windows 平台支援（layered window 透明）
- **v0.4.x**：多螢幕選擇、目標螢幕指定
- **v1.0.0**：完整設定面板（樣式、位置、顯示螢幕、開機啟動）

---

*專案入口文件 - 詳細規則請參考 `.claude/rules/` 目錄*

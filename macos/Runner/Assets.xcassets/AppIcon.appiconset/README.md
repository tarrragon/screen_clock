# App Icon 資產替換指引（v1.0.0-W4-001）

目前資料夾為 Flutter scaffold 預設圖示，發布前須替換為 screen_clock 專屬圖示。

## 規範

macOS Big Sur 之後的 app icon 採圓角矩形，建議在 1024×1024 設計稿留 ~10% 透明邊（macOS 會自動套用圓角遮罩，邊緣若貼齊會被裁切）。

## 必要檔案

| 檔名 | 邏輯尺寸 | 物理尺寸（含 @2x） | scale |
|------|---------|---------------------|-------|
| `app_icon_16.png` | 16×16 | 16×16 | 1x |
| `app_icon_32.png` | 16×16 / 32×32 | 32×32 | 2x / 1x |
| `app_icon_64.png` | 32×32 | 64×64 | 2x |
| `app_icon_128.png` | 128×128 | 128×128 | 1x |
| `app_icon_256.png` | 128×128 / 256×256 | 256×256 | 2x / 1x |
| `app_icon_512.png` | 256×256 / 512×512 | 512×512 | 2x / 1x |
| `app_icon_1024.png` | 512×512 | 1024×1024 | 2x |

Contents.json 已連好上述檔名，**只要原檔名替換 PNG 就會生效**。

## 替換流程

1. 用任意設計工具（Figma、Sketch、Pixelmator）匯出 1024×1024 PNG
2. 用 [Bakery](https://apps.apple.com/app/bakery-simple-icon-maker/id1575220747) 或 `iconutil` 產生上述 7 個尺寸
3. 覆寫本資料夾中的 7 個 PNG（檔名保持不變）
4. `flutter clean && flutter build macos --release` 驗證 Dock / Launchpad 顯示
5. commit 訊息：`feat(1.0.0-W4-001): replace app icon with screen_clock branding`

## MVP 設計建議

時鐘主題 + 透明遮罩意象：
- 中央放鐘面 / 時間數字（呼應產品名）
- 背景半透明灰底（呼應遮罩功能）
- 避免文字（小尺寸下不可讀）

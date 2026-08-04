import Cocoa
import QuartzCore

/// 螢幕邊框閃爍特效（SPEC-008 FR-04、UC-06）。
///
/// 沿目標螢幕四周描繪寬 `borderWidth` 的邊框，於播放起點後閃爍
/// `flashCycleCount` 次、每次淡入淡出週期 `flashCycleDuration`，之後保持不可見
/// 直到播放結束。
///
/// 邊框以單一 `CALayer` 的 `borderWidth` 繪製而非四條矩形子圖層：`borderWidth`
/// 由 Core Animation 往 `bounds` **內緣**描繪且不填滿內部（`backgroundColor`
/// 保持 nil），故「僅佔四周邊緣、不遮蔽螢幕中央內容」由圖層屬性本身保證，
/// 不依賴四條矩形的座標計算正確；四條矩形則需自行維護角落接合與長寬推導。
///
/// 「非目標螢幕無邊框」由控制器的單一 surface 設計保證（特效視窗只建在目標
/// 螢幕）；本型別只在 `attach` 傳入的 layer 內繪製，不觸碰任何其他圖層或視窗。
final class CursorLocatorBorderFlashRenderer: CursorLocatorEffectRendering {

  /// 邊框圖層。`nil` 表示尚未 attach 或已 detach。
  ///
  /// 對外唯讀（寫入僅限本型別）：邊框的幾何、顏色、不透明度是本子票的驗收
  /// 對象，而 `CALayer` 的實際呈現無法在單元測試環境取樣，故以圖層屬性作為
  /// 可觀測面。
  private(set) var borderLayer: CALayer?

  func attach(to layer: CALayer, tint: NSColor, duration: TimeInterval) {
    // 重置（播放中再次觸發）會重新 attach，主色調可能已變更；先移除舊圖層，
    // 避免同一 layer 上疊出第二條邊框。
    detach()

    let border = CALayer()
    border.frame = layer.bounds
    border.borderWidth = CursorLocatorEffectConstants.borderWidth
    border.borderColor = tint.cgColor
    // 首幀 render 之前不應可見：attach 與首幀之間可能間隔一次螢幕更新，
    // 以 opacity 1 起始會閃出一格全亮邊框。
    border.opacity = 0

    layer.addSublayer(border)
    borderLayer = border

    NSLog("[cursor-locator] BorderFlashRenderer attach: bounds=\(layer.bounds)")
  }

  func render(_ frame: CursorLocatorEffectFrame) {
    // 螢幕解析度變更或視窗跨螢幕搬遷時 bounds 會改變，逐幀依
    // `frame.layerBounds`（控制器單一來源）對齊，不再倚賴
    // `autoresizingMask` 隱式跟隨父層的觸發時機（1.4.0-W3-023）。
    borderLayer?.frame = frame.layerBounds
    borderLayer?.opacity = Float(Self.flashAlpha(elapsed: frame.elapsed))
  }

  func detach() {
    let bounds = borderLayer?.bounds ?? .zero
    borderLayer?.removeFromSuperlayer()
    borderLayer = nil

    NSLog("[cursor-locator] BorderFlashRenderer detach: bounds=\(bounds)")
  }

  /// 三次淡入淡出的不透明度曲線（純函式，供直接覆蓋邊界值）。
  ///
  /// 每個週期前半淡入（0 至 1）、後半淡出（1 至 0），三個週期結束後恆為 0。
  /// 以 `elapsed`（自首幀起算的絕對秒數）而非 `progress` 推導：週期長度是
  /// SPEC 固定的 200 ms，與使用者可調的總時長無關，由 `progress` 反推會使
  /// 週期隨總時長伸縮而違反規格。
  ///
  /// - Parameter elapsed: 自首幀起算的秒數。負值（在途幀或時鐘倒退）視為 0。
  static func flashAlpha(elapsed: TimeInterval) -> CGFloat {
    let cycle = CursorLocatorEffectConstants.flashCycleDuration
    let totalFlashDuration = cycle * Double(CursorLocatorEffectConstants.flashCycleCount)
    guard cycle > 0, elapsed > 0, elapsed < totalFlashDuration else { return 0 }

    let phase = elapsed.truncatingRemainder(dividingBy: cycle)
    let halfCycle = cycle / 2
    let value = phase < halfCycle ? phase / halfCycle : (cycle - phase) / halfCycle
    return CGFloat(value)
  }
}

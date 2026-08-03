import Cocoa
import QuartzCore

/// 游標波紋擴散特效（SPEC-008 FR-05，子票 `1.4.0-W3-001.4`）。
///
/// 以游標為圓心連續發出三圈同心圓，單圈半徑由 20 px 擴散至 180 px、透明度
/// 由 100% 淡至 0%、歷時 500 ms，相鄰兩圈間隔 150 ms。數值一律取自
/// `CursorLocatorEffectConstants`，本檔不出現規格字面值。
///
/// 圓心一律取自 `CursorLocatorEffectFrame.cursorPointInLayer`（每幀由控制器
/// 單次取樣後交付），不自行呼叫 `NSEvent.mouseLocation`：FR-05 明文要求與
/// FR-03 聚光燈共用同一組取樣，各自取樣會使波紋圓心在快速移動時跑出亮區外。

/// 單圈在某一時刻的外觀。`nil` 表示該圈此刻不可見（尚未發出或已淡盡）。
///
/// 抽為值型別而非直接寫進 layer 更新流程，使時間曲線可獨立於 CoreAnimation
/// 驗證——測試不需建立圖層即能斷言半徑與透明度。
struct CursorLocatorRippleRingAppearance: Equatable {
  let radius: CGFloat
  let alpha: CGFloat
}

/// 波紋的時間曲線。純函式集合，不持有狀態。
enum CursorLocatorRippleTimeline {

  /// 第 `ringIndex` 圈於 `elapsed` 秒時的外觀；未發出或已淡盡時為 `nil`。
  ///
  /// 以絕對時間軸（`elapsed`）而非 `progress` 推導：三圈的發出間隔與單圈
  /// 生命期都是 SPEC 明定的絕對秒數，換算成 progress 會隨 `duration` 變動。
  static func appearance(ringIndex: Int, elapsed: TimeInterval)
    -> CursorLocatorRippleRingAppearance?
  {
    let emissionTime = TimeInterval(ringIndex) * CursorLocatorEffectConstants.rippleEmissionInterval
    let age = elapsed - emissionTime
    let lifetime = CursorLocatorEffectConstants.rippleRingLifetime
    guard age >= 0, age <= lifetime, lifetime > 0 else { return nil }

    let ratio = CGFloat(age / lifetime)
    let startRadius = CursorLocatorEffectConstants.rippleStartRadius
    let radiusSpan = CursorLocatorEffectConstants.rippleEndRadius - startRadius
    return CursorLocatorRippleRingAppearance(
      radius: startRadius + radiusSpan * ratio,
      alpha: 1 - ratio
    )
  }
}

/// FR-05 的 `CursorLocatorEffectRendering` 實作。
///
/// 每圈各佔一個 `CAShapeLayer`：圈數固定為三，逐圈持有圖層使每幀只需更新
/// 既有圖層的 path 與 opacity，不在動畫期間增刪圖層。
final class CursorLocatorRippleRenderer: CursorLocatorEffectRendering {

  private var ringLayers: [CAShapeLayer] = []

  func attach(to layer: CALayer, tint: NSColor, duration: TimeInterval) {
    detach()

    let strokeColor = tint.cgColor
    ringLayers = (0..<CursorLocatorEffectConstants.rippleRingCount).map { _ in
      let ringLayer = CAShapeLayer()
      ringLayer.fillColor = nil
      ringLayer.strokeColor = strokeColor
      ringLayer.lineWidth = CursorLocatorEffectConstants.rippleLineWidth
      ringLayer.contentsScale = layer.contentsScale
      ringLayer.opacity = 0
      layer.addSublayer(ringLayer)
      return ringLayer
    }
  }

  /// 每幀重畫三圈。已發出的圈同樣以本幀游標位置為圓心（三圈永遠同心），
  /// 而非釘在各自發出當下的位置：FR-05「圓心跟隨游標」與其驗收標準
  /// 「播放期間移動游標，波紋圓心跟隨」指的是波紋整體跟隨，釘住舊位置會
  /// 拖出軌跡而非同心圓。
  func render(_ frame: CursorLocatorEffectFrame) {
    for (index, ringLayer) in ringLayers.enumerated() {
      guard
        let appearance = CursorLocatorRippleTimeline.appearance(
          ringIndex: index, elapsed: frame.elapsed)
      else {
        ringLayer.opacity = 0
        continue
      }

      ringLayer.path = Self.ringPath(center: frame.cursorPointInLayer, radius: appearance.radius)
      ringLayer.opacity = Float(appearance.alpha)
    }
  }

  /// 移除本 renderer 加到宿主圖層上的一切。播放的四條結束路徑共用此出口，
  /// 故「淡出完整、無殘留圖形」由圖層移除保證，不倚賴最後一幀的透明度。
  func detach() {
    ringLayers.forEach { $0.removeFromSuperlayer() }
    ringLayers = []
  }

  private static func ringPath(center: CGPoint, radius: CGFloat) -> CGPath {
    let boundingBox = CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
    return CGPath(ellipseIn: boundingBox, transform: nil)
  }
}

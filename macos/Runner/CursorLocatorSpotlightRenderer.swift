import Cocoa
import QuartzCore

/// 聚光燈特效（SPEC-008 FR-03，子票 `1.4.0-W3-001.2`）。
///
/// 目標螢幕整體壓暗，游標周圍保留一圈未壓暗的圓形亮區，形成手電筒照射效果。
///
/// 繪製方式：一層覆蓋全螢幕的壓暗圖層，其 `mask` 為一顆放射狀漸層——遮罩在
/// 亮區半徑內 alpha 為 0（壓暗層被完全遮蔽，該處維持原亮度）、往外經一段
/// 羽化帶漸變到 alpha 1（壓暗層完全顯示）。以遮罩漸層而非 `CAShapeLayer`
/// 挖洞，是因為形狀圖層的邊界是硬邊，違反 FR-03「邊緣以漸層過渡避免硬邊」。
///
/// 壓暗程度不隨 `progress` 變化：播放末段的整體淡出由特效視窗層級的
/// `fadeAlpha` 負責（FR-06 的時長含淡出），本 renderer 若再自行淡出會與其
/// 相乘，使實際壓暗低於規格值。
final class CursorLocatorSpotlightRenderer: CursorLocatorEffectRendering {

  /// 壓暗層。`attach` 時建立、`detach` 時移除；未 attach 期間為 nil。
  private var dimLayer: CALayer?

  /// 壓暗層的遮罩（放射狀漸層），圓心每幀跟隨游標。
  private var holeMask: CAGradientLayer?

  func attach(to layer: CALayer, tint: NSColor, duration: TimeInterval) {
    detach()

    let mask = makeHoleMask(bounds: layer.bounds)
    let dim = makeDimLayer(bounds: layer.bounds, mask: mask)

    withoutImplicitAnimations {
      layer.addSublayer(dim)
    }

    self.dimLayer = dim
    self.holeMask = mask
  }

  func render(_ frame: CursorLocatorEffectFrame) {
    guard let dim = dimLayer, let mask = holeMask else { return }

    // 依附的圖層可能因視窗搬到另一台螢幕而改變尺寸，故每幀重新對齊。
    let bounds = dim.superlayer?.bounds ?? dim.bounds

    withoutImplicitAnimations {
      dim.frame = bounds
      mask.frame = CGRect(origin: .zero, size: bounds.size)
      applyHoleCenter(frame.cursorPointInLayer, to: mask, in: bounds.size)
    }
  }

  func detach() {
    withoutImplicitAnimations {
      dimLayer?.removeFromSuperlayer()
    }
    dimLayer = nil
    holeMask = nil
  }

  // MARK: - 建構

  private func makeDimLayer(bounds: CGRect, mask: CAGradientLayer) -> CALayer {
    let dim = CALayer()
    dim.frame = bounds
    dim.backgroundColor = NSColor.black.cgColor
    dim.opacity = Float(CursorLocatorEffectConstants.spotlightDimOpacity)
    dim.mask = mask
    return dim
  }

  /// 建立遮罩：中心到亮區半徑之間 alpha 0，往外羽化到 alpha 1。
  ///
  /// `CAGradientLayer` 在漸層範圍之外沿用最後一個顏色，因此羽化帶以外的整個
  /// 螢幕都會拿到 alpha 1，不需另外鋪滿。
  private func makeHoleMask(bounds: CGRect) -> CAGradientLayer {
    let mask = CAGradientLayer()
    mask.type = .radial
    mask.frame = CGRect(origin: .zero, size: bounds.size)
    mask.colors = [
      NSColor.black.withAlphaComponent(0).cgColor,
      NSColor.black.withAlphaComponent(0).cgColor,
      NSColor.black.withAlphaComponent(1).cgColor,
    ]
    mask.locations = [
      0,
      NSNumber(value: CursorLocatorEffectConstants.spotlightBrightStopRatio),
      1,
    ]
    applyHoleCenter(
      CGPoint(x: bounds.midX, y: bounds.midY),
      to: mask,
      in: bounds.size
    )
    return mask
  }

  /// 把亮區圓心（圖層座標，左下原點）換算成漸層的單位座標。
  ///
  /// `CAGradientLayer` 的 `startPoint` 是放射漸層圓心、`endPoint` 是漸層橢圓
  /// 的邊緣點，兩者皆為單位座標；把「亮區半徑 + 羽化帶」以像素除以圖層邊長
  /// 換算成單位長度，漸層在兩軸上才會是正圓而非隨螢幕長寬比拉伸的橢圓。
  private func applyHoleCenter(_ point: CGPoint, to mask: CAGradientLayer, in size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }

    let outerRadius = CursorLocatorEffectConstants.spotlightOuterRadius
    let center = CGPoint(x: point.x / size.width, y: point.y / size.height)
    mask.startPoint = center
    mask.endPoint = CGPoint(
      x: center.x + outerRadius / size.width,
      y: center.y + outerRadius / size.height
    )
  }

  /// 圖層屬性的隱含動畫會讓亮區「滑」向新位置而非即時跟隨（FR-03 要求無可見
  /// 延遲），且每幀都會新建動畫物件；故所有幾何寫入一律停用隱含動畫。
  private func withoutImplicitAnimations(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }
}

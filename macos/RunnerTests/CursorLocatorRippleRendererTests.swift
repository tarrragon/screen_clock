import XCTest

@testable import screen_clock

/// 游標波紋擴散（SPEC-008 FR-05，子票 `1.4.0-W3-001.4`）。
///
/// 分兩層：時間曲線（`CursorLocatorRippleTimeline`）以純函式驗證半徑、透明度
/// 與三圈時序；繪製（`CursorLocatorRippleRenderer`）驗證圖層數量、圓心跟隨、
/// 顏色來源與收尾清除。
final class CursorLocatorRippleRendererTests: XCTestCase {

  private let lifetime = CursorLocatorEffectConstants.rippleRingLifetime
  private let interval = CursorLocatorEffectConstants.rippleEmissionInterval
  private let startRadius = CursorLocatorEffectConstants.rippleStartRadius
  private let endRadius = CursorLocatorEffectConstants.rippleEndRadius

  // MARK: - 單圈時間曲線

  func testFirstRing_startsAtStartRadiusWithFullAlpha() {
    let appearance = CursorLocatorRippleTimeline.appearance(ringIndex: 0, elapsed: 0)
    XCTAssertEqual(appearance?.radius, startRadius)
    XCTAssertEqual(appearance?.alpha, 1)
  }

  func testFirstRing_reachesEndRadiusWithZeroAlphaAtLifetime() {
    let appearance = CursorLocatorRippleTimeline.appearance(ringIndex: 0, elapsed: lifetime)
    XCTAssertEqual(appearance?.radius, endRadius)
    XCTAssertEqual(appearance?.alpha, 0)
  }

  /// 半徑與透明度皆為線性內插：中點應恰為兩端點的中間值。
  func testFirstRing_interpolatesLinearlyAtMidLifetime() {
    let appearance = CursorLocatorRippleTimeline.appearance(ringIndex: 0, elapsed: lifetime / 2)
    XCTAssertEqual(appearance?.radius ?? 0, (startRadius + endRadius) / 2, accuracy: 1e-6)
    XCTAssertEqual(appearance?.alpha ?? 0, 0.5, accuracy: 1e-6)
  }

  /// 淡盡後不得再回傳外觀，否則末段會殘留一圈定格在終止半徑的圖形。
  func testRing_isInvisibleAfterLifetime() {
    XCTAssertNil(
      CursorLocatorRippleTimeline.appearance(ringIndex: 0, elapsed: lifetime + 0.001))
  }

  // MARK: - 三圈時序

  func testLaterRings_areEmittedAtFixedInterval() {
    for ringIndex in 0..<CursorLocatorEffectConstants.rippleRingCount {
      let emissionTime = TimeInterval(ringIndex) * interval
      XCTAssertNil(
        CursorLocatorRippleTimeline.appearance(
          ringIndex: ringIndex, elapsed: emissionTime - 0.001),
        "第 \(ringIndex) 圈在發出前不應可見")
      XCTAssertEqual(
        CursorLocatorRippleTimeline.appearance(ringIndex: ringIndex, elapsed: emissionTime)?.radius,
        startRadius,
        "第 \(ringIndex) 圈應自起始半徑發出")
    }
  }

  /// 同一時刻三圈半徑互不相同：三圈同時可見時應呈現由外而內的擴散序列。
  func testRings_haveDistinctRadiiWhileOverlapping() {
    let elapsed = TimeInterval(CursorLocatorEffectConstants.rippleRingCount - 1) * interval
    let radii = (0..<CursorLocatorEffectConstants.rippleRingCount).compactMap {
      CursorLocatorRippleTimeline.appearance(ringIndex: $0, elapsed: elapsed)?.radius
    }

    XCTAssertEqual(radii.count, CursorLocatorEffectConstants.rippleRingCount)
    XCTAssertEqual(radii, radii.sorted(by: >), "圈序越早半徑應越大")
  }

  // MARK: - 繪製

  func testAttach_addsOneLayerPerRingUsingTint() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()

    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)

    let ringLayers = hostLayer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
    XCTAssertEqual(ringLayers.count, CursorLocatorEffectConstants.rippleRingCount)
    for ringLayer in ringLayers {
      XCTAssertEqual(ringLayer.strokeColor, NSColor.red.cgColor)
      XCTAssertNil(ringLayer.fillColor, "波紋為圓環，實心填色會蓋住底下畫面")
    }
  }

  /// 重新 attach（重置播放）不得累積圖層，否則多次觸發後波紋越畫越多層。
  func testReattach_doesNotAccumulateLayers() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()

    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)
    renderer.attach(to: hostLayer, tint: .green, duration: 1.0)

    XCTAssertEqual(hostLayer.sublayers?.count, CursorLocatorEffectConstants.rippleRingCount)
  }

  func testRender_centersVisibleRingsOnSampledCursorPoint() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()
    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)

    let cursorPoint = CGPoint(x: 300, y: 400)
    renderer.render(frame(elapsed: 0, cursorPoint: cursorPoint))

    let firstRing = ringLayers(of: hostLayer)[0]
    XCTAssertEqual(center(of: firstRing).x, cursorPoint.x, accuracy: 1e-6)
    XCTAssertEqual(center(of: firstRing).y, cursorPoint.y, accuracy: 1e-6)
    XCTAssertEqual(firstRing.opacity, 1, accuracy: 1e-6)
  }

  /// FR-05 驗收標準「播放期間移動游標，波紋圓心跟隨」：已發出的圈同樣重定圓心，
  /// 三圈維持同心而非拖出軌跡。
  func testRender_movesAlreadyEmittedRingsWithCursor() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()
    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)

    renderer.render(frame(elapsed: interval, cursorPoint: CGPoint(x: 100, y: 100)))
    let movedPoint = CGPoint(x: 800, y: 200)
    renderer.render(frame(elapsed: interval, cursorPoint: movedPoint))

    let visibleCenters = ringLayers(of: hostLayer)
      .filter { $0.opacity > 0 }
      .map { center(of: $0) }
    XCTAssertEqual(visibleCenters.count, 2, "t=interval 時應有兩圈可見")
    for visibleCenter in visibleCenters {
      XCTAssertEqual(visibleCenter.x, movedPoint.x, accuracy: 1e-6)
      XCTAssertEqual(visibleCenter.y, movedPoint.y, accuracy: 1e-6)
    }
  }

  func testRender_keepsUnemittedRingsTransparent() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()
    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)

    renderer.render(frame(elapsed: 0, cursorPoint: CGPoint(x: 10, y: 10)))

    let opacities = ringLayers(of: hostLayer).map { $0.opacity }
    XCTAssertEqual(opacities[0], 1, accuracy: 1e-6)
    XCTAssertEqual(opacities[1], 0)
    XCTAssertEqual(opacities[2], 0)
  }

  /// 「波紋淡出完整，播放結束後無殘留圖形」：四條結束路徑共用 `detach`，
  /// 故以圖層移除保證，不倚賴最後一幀的透明度。
  func testDetach_removesEveryRingLayer() {
    let renderer = CursorLocatorRippleRenderer()
    let hostLayer = CALayer()
    renderer.attach(to: hostLayer, tint: .red, duration: 1.5)
    renderer.render(frame(elapsed: 0, cursorPoint: CGPoint(x: 10, y: 10)))

    renderer.detach()

    XCTAssertTrue(hostLayer.sublayers?.isEmpty ?? true)
  }

  // MARK: - Helpers

  private func frame(elapsed: TimeInterval, cursorPoint: CGPoint) -> CursorLocatorEffectFrame {
    CursorLocatorEffectFrame(
      progress: 0,
      elapsed: elapsed,
      duration: 1.5,
      cursorPointInLayer: cursorPoint,
      tint: .red
    )
  }

  private func ringLayers(of hostLayer: CALayer) -> [CAShapeLayer] {
    hostLayer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
  }

  private func center(of ringLayer: CAShapeLayer) -> CGPoint {
    let box = ringLayer.path?.boundingBoxOfPath ?? .zero
    return CGPoint(x: box.midX, y: box.midY)
  }
}

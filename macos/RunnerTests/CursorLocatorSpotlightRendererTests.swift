import XCTest

@testable import screen_clock

/// `CursorLocatorSpotlightRenderer` 與其常數的覆蓋（SPEC-008 FR-03）。
///
/// FR-03 驗收標準中「邊緣為漸層非鋸齒硬邊」與「移動游標無可見延遲」屬視覺
/// 判準，自動測試無法斷言，由實機驗證票 `1.4.0-W3-006` 涵蓋；本檔涵蓋可
/// 斷言的部分：規格數值、attach/detach 造成的圖層增減、render 對游標位置的
/// 反應。
final class CursorLocatorSpotlightRendererTests: XCTestCase {

  private let hostBounds = CGRect(x: 0, y: 0, width: 1000, height: 500)

  private func makeHostLayer() -> CALayer {
    let layer = CALayer()
    layer.frame = hostBounds
    return layer
  }

  private func makeFrame(cursor: CGPoint) -> CursorLocatorEffectFrame {
    CursorLocatorEffectFrame(
      progress: 0.5,
      elapsed: 0.75,
      duration: 1.5,
      cursorPointInLayer: cursor,
      tint: .systemBlue
    )
  }

  // MARK: - 規格數值

  /// SPEC-008 FR-03「壓暗透明度上限 55%」。
  func testDimOpacity_doesNotExceedSpecUpperBound() {
    XCTAssertLessThanOrEqual(CursorLocatorEffectConstants.spotlightDimOpacity, 0.55)
  }

  /// SPEC-008 FR-03「保留明亮的圓形半徑 120 px」。
  func testBrightRadius_matchesSpec() {
    XCTAssertEqual(CursorLocatorEffectConstants.spotlightBrightRadius, 120)
  }

  /// 羽化帶存在才可能有漸層過渡；寬度為零等同硬邊。
  func testEdgeFeather_isPositive() {
    XCTAssertGreaterThan(CursorLocatorEffectConstants.spotlightEdgeFeather, 0)
  }

  func testOuterRadius_isBrightRadiusPlusFeather() {
    XCTAssertEqual(
      CursorLocatorEffectConstants.spotlightOuterRadius,
      CursorLocatorEffectConstants.spotlightBrightRadius
        + CursorLocatorEffectConstants.spotlightEdgeFeather
    )
  }

  /// 亮區邊界必須落在漸層內部（0 < ratio < 1），否則漸層退化成硬邊或全羽化。
  func testBrightStopRatio_liesStrictlyInsideGradient() {
    let ratio = CursorLocatorEffectConstants.spotlightBrightStopRatio
    XCTAssertGreaterThan(ratio, 0)
    XCTAssertLessThan(ratio, 1)
  }

  // MARK: - 圖層生命週期

  func testAttach_addsSingleDimSublayerWithMaskedOpacity() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()

    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    XCTAssertEqual(host.sublayers?.count, 1)
    let dim = try? XCTUnwrap(host.sublayers?.first)
    XCTAssertEqual(dim?.frame, hostBounds)
    XCTAssertEqual(
      Double(dim?.opacity ?? 0),
      CursorLocatorEffectConstants.spotlightDimOpacity,
      accuracy: 0.0001
    )
    XCTAssertTrue(dim?.mask is CAGradientLayer)
  }

  /// 重置路徑：播放中再次觸發會重新 attach，不得累積圖層。
  func testAttachTwice_doesNotAccumulateLayers() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()

    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    XCTAssertEqual(host.sublayers?.count, 1)
  }

  func testDetach_removesAllAddedLayers() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()

    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)
    renderer.detach()

    XCTAssertTrue(host.sublayers?.isEmpty ?? true)
  }

  /// 四條結束路徑共用 `detach`，重複呼叫（如逾時與自然結束相繼觸發）不得崩潰。
  func testDetachTwice_isIdempotent() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()

    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)
    renderer.detach()
    renderer.detach()

    XCTAssertTrue(host.sublayers?.isEmpty ?? true)
  }

  // MARK: - 每幀跟隨

  /// 亮區圓心消費 `cursorPointInLayer`，不自行取樣。
  func testRender_placesGradientCenterAtCursorPoint() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    renderer.render(makeFrame(cursor: CGPoint(x: 250, y: 400)))

    guard let mask = host.sublayers?.first?.mask as? CAGradientLayer else {
      return XCTFail("expected gradient mask")
    }
    // 單位座標：250/1000 = 0.25、400/500 = 0.8。
    XCTAssertEqual(mask.startPoint.x, 0.25, accuracy: 0.0001)
    XCTAssertEqual(mask.startPoint.y, 0.8, accuracy: 0.0001)
  }

  /// 漸層半徑在兩軸上換算後須對應同一像素距離，否則亮區在非正方形螢幕會被
  /// 拉成橢圓。
  func testRender_gradientRadiusMapsToSamePixelDistanceOnBothAxes() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    renderer.render(makeFrame(cursor: CGPoint(x: 500, y: 250)))

    guard let mask = host.sublayers?.first?.mask as? CAGradientLayer else {
      return XCTFail("expected gradient mask")
    }
    let outer = CursorLocatorEffectConstants.spotlightOuterRadius
    let horizontalPixels = (mask.endPoint.x - mask.startPoint.x) * hostBounds.width
    let verticalPixels = (mask.endPoint.y - mask.startPoint.y) * hostBounds.height
    XCTAssertEqual(horizontalPixels, outer, accuracy: 0.0001)
    XCTAssertEqual(verticalPixels, outer, accuracy: 0.0001)
  }

  /// 連續多幀移動：圓心逐幀更新，不停留在首幀位置。
  func testRender_updatesCenterOnEveryFrame() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    renderer.render(makeFrame(cursor: CGPoint(x: 100, y: 100)))
    guard let mask = host.sublayers?.first?.mask as? CAGradientLayer else {
      return XCTFail("expected gradient mask")
    }
    let first = mask.startPoint

    renderer.render(makeFrame(cursor: CGPoint(x: 900, y: 400)))
    let second = mask.startPoint

    XCTAssertNotEqual(first.x, second.x, accuracy: 0.0001)
    XCTAssertNotEqual(first.y, second.y, accuracy: 0.0001)
    XCTAssertEqual(second.x, 0.9, accuracy: 0.0001)
    XCTAssertEqual(second.y, 0.8, accuracy: 0.0001)
  }

  /// detach 後殘留的 frame 呼叫（逾時與末幀競態）不得崩潰或重建圖層。
  func testRender_afterDetach_isNoOp() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)
    renderer.detach()

    renderer.render(makeFrame(cursor: CGPoint(x: 100, y: 100)))

    XCTAssertTrue(host.sublayers?.isEmpty ?? true)
  }

  /// 視窗搬到不同尺寸的螢幕後，壓暗層須重新覆蓋整個圖層，否則邊緣露出未壓暗帶。
  func testRender_resizesDimLayerToCurrentHostBounds() {
    let host = makeHostLayer()
    let renderer = CursorLocatorSpotlightRenderer()
    renderer.attach(to: host, tint: .systemBlue, duration: 1.5)

    let resized = CGRect(x: 0, y: 0, width: 1600, height: 900)
    host.frame = resized
    renderer.render(makeFrame(cursor: CGPoint(x: 800, y: 450)))

    XCTAssertEqual(host.sublayers?.first?.frame, CGRect(origin: .zero, size: resized.size))
  }
}

import XCTest

@testable import screen_clock

/// 三種特效同時存在於同一 `contentLayer` 時的整併層級覆蓋（整併票 `1.4.0-W3-001`）。
///
/// 各子票（`.2` 聚光燈、`.3` 邊框閃爍、`.4` 波紋）在自己的 worktree 內只看得到
/// 空的 renderers 陣列，故以下三件事沒有任何單一子票的測試涵蓋得到：
/// 疊加順序、composite 對三者的廣播、detach 後的殘留。
///
/// 本檔以 production 的 renderer 組合（順序見 `MainFlutterWindow.swift` 接線處）
/// 為受測對象，不重複驗證各 renderer 自身的繪製細節——那屬各子票的測試檔。
final class CursorLocatorEffectCompositionTests: XCTestCase {

  private let hostBounds = CGRect(x: 0, y: 0, width: 1000, height: 500)

  /// production 的 renderer 組合與順序。與 `MainFlutterWindow.swift` 接線處
  /// 保持一致；此處若與 production 分歧，z-order 斷言即失去意義。
  private func makeProductionRenderer() -> CursorLocatorCompositeRenderer {
    CursorLocatorCompositeRenderer(renderers: [
      CursorLocatorSpotlightRenderer(),
      CursorLocatorRippleRenderer(),
      CursorLocatorBorderFlashRenderer()
    ])
  }

  private func makeHostLayer() -> CALayer {
    let layer = CALayer()
    layer.frame = hostBounds
    return layer
  }

  private func makeFrame(elapsed: TimeInterval) -> CursorLocatorEffectFrame {
    CursorLocatorEffectFrame(
      progress: elapsed / 1.5,
      elapsed: elapsed,
      duration: 1.5,
      cursorPointInLayer: CGPoint(x: 500, y: 250),
      tint: .systemBlue
    )
  }

  // MARK: - 疊加順序（z-order）

  /// 陣列順序即 sublayer 疊加順序（先加者在下）。聚光燈是覆蓋全螢幕的壓暗
  /// 遮罩，排在其後的波紋與邊框才不會被壓暗蓋住。
  func testAttach_stacksSpotlightBelowRippleBelowBorderFlash() {
    let layer = makeHostLayer()

    makeProductionRenderer().attach(to: layer, tint: .systemBlue, duration: 1.5)

    let sublayers = layer.sublayers ?? []
    // 聚光燈 1 層（帶 hole mask 的壓暗層）+ 波紋 3 圈 + 邊框 1 層。
    XCTAssertEqual(sublayers.count, 1 + CursorLocatorEffectConstants.rippleRingCount + 1)

    // 底層為聚光燈：唯一帶 mask 的圖層（亮區挖洞用）。
    XCTAssertNotNil(sublayers.first?.mask, "聚光燈壓暗層必須墊底，否則會蓋住波紋與邊框")

    // 中段為波紋：三個 CAShapeLayer（同心圓環）。
    let rippleRange = 1..<(1 + CursorLocatorEffectConstants.rippleRingCount)
    for index in rippleRange {
      XCTAssertTrue(
        sublayers[index] is CAShapeLayer,
        "索引 \(index) 應為波紋圓環，實際為 \(type(of: sublayers[index]))"
      )
    }

    // 最外層為邊框：唯一設定 borderWidth 的圖層，不受壓暗影響。
    XCTAssertEqual(sublayers.last?.borderWidth, CursorLocatorEffectConstants.borderWidth)
    XCTAssertNil(sublayers.last?.mask)
  }

  // MARK: - composite 廣播

  /// `attach` 廣播到三者：任一 renderer 漏接都會使該特效整場不出現。
  func testAttach_isBroadcastToAllThreeRenderers() {
    let layer = makeHostLayer()

    makeProductionRenderer().attach(to: layer, tint: .systemBlue, duration: 1.5)

    let sublayers = layer.sublayers ?? []
    XCTAssertTrue(sublayers.contains { $0.mask != nil }, "聚光燈未接上")
    XCTAssertTrue(sublayers.contains { $0 is CAShapeLayer }, "波紋未接上")
    XCTAssertTrue(
      sublayers.contains { $0.borderWidth == CursorLocatorEffectConstants.borderWidth },
      "邊框閃爍未接上"
    )
  }

  /// `render` 只更新既有圖層，不得每幀新增——逐幀累積會在播放中無上限成長。
  func testRender_doesNotAddSublayersPerFrame() {
    let layer = makeHostLayer()
    let renderer = makeProductionRenderer()
    renderer.attach(to: layer, tint: .systemBlue, duration: 1.5)
    let countAfterAttach = layer.sublayers?.count

    for elapsed in stride(from: 0.0, through: 1.5, by: 0.1) {
      renderer.render(makeFrame(elapsed: elapsed))
    }

    XCTAssertEqual(layer.sublayers?.count, countAfterAttach)
  }

  // MARK: - detach 殘留

  /// `detach` 廣播到三者且不留殘留。任一 renderer 漏移除，其圖層會殘留在
  /// 下一次播放的畫面上（surface 可能被重用）。
  func testDetach_removesEverySublayer() {
    let layer = makeHostLayer()
    let renderer = makeProductionRenderer()
    renderer.attach(to: layer, tint: .systemBlue, duration: 1.5)
    renderer.render(makeFrame(elapsed: 0.5))
    XCTAssertFalse((layer.sublayers ?? []).isEmpty)

    renderer.detach()

    XCTAssertTrue(
      (layer.sublayers ?? []).isEmpty,
      "detach 後殘留 \((layer.sublayers ?? []).count) 個 sublayer"
    )
  }

  /// 重播（attach → detach → attach）不得疊加：圖層數與首次 attach 相同。
  func testReattach_afterDetachDoesNotAccumulateLayers() {
    let layer = makeHostLayer()
    let renderer = makeProductionRenderer()

    renderer.attach(to: layer, tint: .systemBlue, duration: 1.5)
    let firstCount = layer.sublayers?.count
    renderer.detach()
    renderer.attach(to: layer, tint: .systemRed, duration: 2.0)

    XCTAssertEqual(layer.sublayers?.count, firstCount)
  }
}

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

  // MARK: - 隱含動畫停用（1.4.0-W3-021）

  /// 建立與 production 同構的宿主：layer-hosted view 掛在視窗上。
  ///
  /// 隱含動畫只在圖層樹已被 commit 且連上實際 render context 時才會生成，
  /// 脫離視窗的裸 `CALayer` 寫入 animatable 屬性不產生任何動畫（實測），
  /// 用裸圖層斷言 `animationKeys` 為空會恆真而無法分辨受測行為。視窗不
  /// `orderFront`（實測不需要），避免測試期間有畫面彈出。
  ///
  /// 回傳的視窗須由呼叫端持有到斷言結束：視窗釋放會連帶拆掉圖層樹。
  private func makeHostedLayer() -> (window: NSWindow, layer: CALayer) {
    let view = NSView(frame: hostBounds)
    let layer = CALayer()
    layer.frame = hostBounds
    view.layer = layer
    view.wantsLayer = true

    let window = NSWindow(
      contentRect: hostBounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    return (window, layer)
  }

  /// 收集宿主底下所有會被寫入 animatable 屬性的圖層：三個 renderer 的
  /// sublayer 加上聚光燈壓暗層的遮罩（遮罩不在 `sublayers` 內但每幀被寫入
  /// `frame` 與漸層座標）。
  private func animatableLayers(under host: CALayer) -> [CALayer] {
    let sublayers = host.sublayers ?? []
    return sublayers + sublayers.compactMap { $0.mask }
  }

  private func assertNoImplicitAnimation(
    _ layers: [CALayer], stage: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    for layer in layers {
      XCTAssertEqual(
        layer.animationKeys() ?? [], [],
        "\(stage) 後 \(type(of: layer)) 啟動了隱含動畫：\(layer.animationKeys() ?? [])",
        file: file, line: line
      )
    }
  }

  /// 每幀寫入 `opacity`／`frame`／`path` 都是 animatable 屬性；宿主為
  /// layer-hosted layer，其 sublayer 的 `delegate` 為 nil，AppKit 不回傳停用
  /// action，未包 `CATransaction` 時每次寫入都會啟動預設 0.25 秒的隱含動畫。
  /// 該時長長於 FR-04 的 200 ms 閃爍週期，會使閃爍在實機上被抹平——本測試是
  /// 唯一能分辨該情形的觀測面（純函式曲線測試看不到）。
  func testRender_doesNotStartImplicitAnimationOnAnySublayer() {
    let (window, layer) = makeHostedLayer()
    let renderer = makeProductionRenderer()
    renderer.attach(to: layer, tint: .systemBlue, duration: 1.5)
    // commit 圖層樹：其後的屬性寫入才會進入隱含動畫的判定路徑。
    CATransaction.flush()

    // 覆蓋閃爍週期內外：週期內 opacity 逐幀變動，最能觸發隱含動畫。
    for elapsed in stride(from: 0.0, through: 1.5, by: 0.05) {
      renderer.render(makeFrame(elapsed: elapsed))
      assertNoImplicitAnimation(
        animatableLayers(under: layer), stage: "render(elapsed: \(elapsed))")
      CATransaction.flush()
    }

    XCTAssertNotNil(window.contentView)
  }

  /// `detach` 的移除同樣須即時：三個 renderer 皆以「圖層移除」保證播放結束
  /// 無殘留，移除若被隱含動畫延後，殘影會留到下一次播放。
  func testDetach_doesNotStartImplicitAnimationOnRemovedLayers() {
    let (window, layer) = makeHostedLayer()
    let renderer = makeProductionRenderer()
    renderer.attach(to: layer, tint: .systemBlue, duration: 1.5)
    CATransaction.flush()
    renderer.render(makeFrame(elapsed: 0.5))
    CATransaction.flush()
    let removedLayers = animatableLayers(under: layer)
    XCTAssertFalse(removedLayers.isEmpty)

    renderer.detach()

    assertNoImplicitAnimation(removedLayers, stage: "detach")
    XCTAssertNotNil(window.contentView)
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

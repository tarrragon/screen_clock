import XCTest

@testable import screen_clock

/// 真實 `NSWindow` 屬性契約（app-hosted）。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計群組 F（T2.F-01 ~ F-07），
/// 覆蓋 Phase 1 GWT 場景 22、§2.5 十二項視窗屬性契約。`BUNDLE_LOADER` /
/// `TEST_HOST` / `ENABLE_TESTABILITY` 已由母票 Phase 1.5 查證，本群組建立
/// 真實 `NSWindow` 並直接斷言，不使用替身。
///
/// 本群組不參與洩漏斷言（母票 Phase 2 §三反面設計）：`NSWindow` 釋放時機
/// 受 AppKit 內部持有影響，weak 斷言會 flaky。洩漏斷言只對 spy surface 成立
/// （見 CursorLocatorEffectControllerLifecycleTests）。
final class CursorLocatorSurfaceContractTests: XCTestCase {

  private var surface: WindowCursorLocatorSurface!

  private var testFrame: NSRect {
    NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
  }

  override func setUp() {
    super.setUp()
    let created = try! makeProductionCursorLocatorSurface(frame: testFrame)
    surface = (created as! WindowCursorLocatorSurface)
  }

  override func tearDown() {
    surface.close()
    surface = nil
    super.tearDown()
  }

  /// T2.F-01（場景 22 視窗基本屬性）
  func testBasicWindowProperties() {
    XCTAssertEqual(surface.window.styleMask, .borderless)
    XCTAssertFalse(surface.window.isOpaque)
    XCTAssertEqual(surface.window.backgroundColor, .clear)
    XCTAssertFalse(surface.window.hasShadow)
    XCTAssertEqual(surface.window.alphaValue, 1.0)
    XCTAssertFalse(surface.window.isReleasedWhenClosed)
  }

  /// T2.F-02（場景 22 層級）
  func testWindowLevel() {
    XCTAssertEqual(surface.window.level, .screenSaver)
  }

  /// T2.F-03（場景 22 collectionBehavior）：逐項比對而非整個集合等值，
  /// 避免 AppKit 預設附加旗標導致脆性失敗。
  func testCollectionBehaviorContainsRequiredMembers() {
    let behavior = surface.window.collectionBehavior
    XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(behavior.contains(.stationary))
    XCTAssertTrue(behavior.contains(.ignoresCycle))
    // .moveToActiveSpace 與 .canJoinAllSpaces 互斥，同時設會使跨 Space 行為未定義。
    XCTAssertFalse(behavior.contains(.moveToActiveSpace))
  }

  /// T2.F-04（場景 22 滑鼠穿透）
  func testIgnoresMouseEvents() {
    XCTAssertTrue(surface.window.ignoresMouseEvents)
  }

  /// T2.F-05（場景 22 不搶焦點）。不斷言 isVisible（測試環境下 app 可能非
  /// front，isVisible 非契約項）。
  func testDoesNotBecomeKeyWindow() {
    XCTAssertFalse(surface.window.canBecomeKey)
    surface.window.orderFrontRegardless()
    XCTAssertFalse(surface.window.isKeyWindow)
  }

  /// T2.F-06（場景 22 frame 覆蓋）：建立後未被 AppKit 調整；borderless
  /// 視窗不受標題列高度影響。
  func testFrameMatchesRequestedFrame() {
    XCTAssertEqual(surface.window.frame, testFrame)
  }

  /// T2.F-07（場景 22 未成為 key 的負向保證）：直接鎖定 canBecomeKey
  /// 覆寫確實生效，而非僅未主動 makeKey（P0-8 的真正風險是誤用
  /// makeKeyAndOrderFront）。
  func testMakeKeyDoesNotSucceed() {
    surface.window.makeKey()
    XCTAssertFalse(surface.window.isKeyWindow)
  }

  // MARK: - layer-hosted 幾何與 scale 同步（1.4.0-W3-018）

  /// hostView 轉為 layer-hosted 後，AppKit 不再替 hosted layer 做 frame 與
  /// contentsScale 同步，本組即針對那兩項換走的自動行為。斷言對象是真實
  /// `NSWindow` 經 AppKit resize 後的 contentView，非 test double 的 CALayer。

  /// 搬遷至不同尺寸的 frame 後，hosted layer 幾何跟上 hostView bounds。
  /// 缺此同步時 contentLayer.frame 停在 init 尺寸，繪製區被裁切或偏移，
  /// 且無錯誤無日誌。
  func testContentLayerFrameFollowsResizeOnMove() {
    let enlarged = NSRect(
      x: testFrame.origin.x,
      y: testFrame.origin.y,
      width: testFrame.width + 320,
      height: testFrame.height + 240
    )
    surface.move(toScreenFrame: enlarged)

    let hostBounds = surface.window.contentView!.bounds
    XCTAssertEqual(hostBounds.size, enlarged.size)
    XCTAssertEqual(surface.contentLayer.frame, hostBounds)
  }

  /// 縮小方向亦須同步：只在放大方向驗證會讓「只設過一次較大值」的實作矇混通過。
  func testContentLayerFrameFollowsShrinkOnMove() {
    let shrunk = NSRect(
      x: testFrame.origin.x,
      y: testFrame.origin.y,
      width: max(testFrame.width - 200, 100),
      height: max(testFrame.height - 150, 100)
    )
    surface.move(toScreenFrame: shrunk)

    XCTAssertEqual(surface.contentLayer.frame, surface.window.contentView!.bounds)
  }

  /// init 當下 contentsScale 即對齊視窗 backingScaleFactor；停在預設 1.0
  /// 會使 Retina 上實際渲染解析度減半（畫面模糊，無錯誤無日誌）。
  func testContentsScaleMatchesBackingScaleAtInit() {
    XCTAssertEqual(surface.contentLayer.contentsScale, surface.window.backingScaleFactor)
  }

  /// 跨螢幕搬遷後 contentsScale 重新對齊該螢幕 backingScaleFactor。
  /// 單機測試環境可能只有一個 scale，故斷言的是「搬遷後與當前視窗一致」
  /// 這條恆成立的關係，而非硬編碼 2.0。
  func testContentsScaleRealignsAfterMove() {
    let moved = NSRect(
      x: testFrame.origin.x,
      y: testFrame.origin.y,
      width: testFrame.width + 100,
      height: testFrame.height + 100
    )
    surface.move(toScreenFrame: moved)

    XCTAssertEqual(surface.contentLayer.contentsScale, surface.window.backingScaleFactor)
  }

  // MARK: - 隱含動畫防護（1.4.0-W3-027 重寫）
  //
  // 原版以真實 `WindowCursorLocatorSurface`（`.screenSaver` 層級 + 特殊
  // `collectionBehavior` + `orderFrontRegardless`）作宿主，經 1.4.0-W3-026
  // RED 對照兩輪實測（無 flush / 有 flush）確認 animationKeys() 恆為空，
  // 為空斷言、無回歸保護。W3-027 進一步以 XCTFail canary 確認該實測所用的
  // 是重新編譯的二進位（非建置快取殘留），排除「移除防護未真正生效」的
  // 替代解釋後，才動手重寫。
  //
  // 改比照 1.4.0-W3-021 `CursorLocatorEffectCompositionTests.makeHostedLayer`
  // 已驗證有效的手法：獨立 `NSWindow` + layer-hosted `NSView`，不經過
  // `WindowCursorLocatorSurface` 的完整 production 初始化（`.screenSaver`
  // 層級、`collectionBehavior`、`orderFrontRegardless` 等均與隱含動畫防護
  // 無關，但足以構成原測試無分辨力的環境差異之一）。直接建構
  // production 的 `LayerHostingView`（已由本票放寬為 `internal`），驗證的
  // 仍是同一份 `synchronizeHostedLayer()` 實作，不是另起爐灶的替代邏輯。

  /// 獨立宿主：`LayerHostingView` 掛在最小 `NSWindow` 上，不透過
  /// `WindowCursorLocatorSurface` 建構。回傳的視窗須由呼叫端持有到斷言
  /// 結束——視窗釋放會連帶拆掉圖層樹。
  private func makeIndependentHostedLayerView() -> (window: NSWindow, view: LayerHostingView) {
    let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
    let contentLayer = CALayer()
    contentLayer.frame = bounds

    let view = LayerHostingView(frame: bounds)
    view.layer = contentLayer
    view.wantsLayer = true

    let window = NSWindow(
      contentRect: bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    return (window, view)
  }

  /// acceptance 第 4 條掃描的第三處：layer-backed 時 AppKit 會透過
  /// `layer.delegate` 停用隱含動畫，hosted layer 的 delegate 為 nil，frame
  /// 變更會啟動 0.25 秒隱含動畫，使搬遷期間 layer 落在舊位置。
  ///
  /// 呼叫 `view.setFrameSize` 直接觸發 `LayerHostingView.setFrameSize` 覆寫
  /// ->`synchronizeHostedLayer()`，與 production 的
  /// `WindowCursorLocatorSurface.move()` 在不同尺寸時觸發的路徑相同
  /// （見該類別 `setFrameSize` 覆寫）；`testContentLayerFrameFollowsResizeOnMove`
  /// 等既有測試已覆蓋「move() 是否呼叫到這條路徑」，本測試不重複驗證。
  /// 不透過 `setFrameSize`：實測發現 AppKit 對 layer-hosting view 的
  /// `setFrameSize` 自身已會把 hosted layer 的幾何同步到與 `bounds` 一致
  /// （production 註解「AppKit 由 view 幾何推導 hosted layer 的
  /// bounds/position」），使 `synchronizeHostedLayer()` 內的 `frame =
  /// bounds` 寫入值與現值相同、CALayer 不視為變更、不產生隱含動畫——
  /// 無論是否停用 action 兩者結果一樣，此路徑對本測試無分辨力。
  ///
  /// 改為人工先把 hosted layer 的 frame 撥到與 `bounds`不同的值（本身用
  /// 停用 action 的 transaction 寫入，避免這筆準備動作污染待測的
  /// `animationKeys()`），再直接呼叫 `synchronizeHostedLayer()`（production
  /// 受測方法本身，非替代邏輯），使其內部的 `frame = bounds` 是一次真正
  /// 的幾何變更，animationKeys() 才有分辨力。
  func testGeometrySyncDoesNotStartImplicitAnimation() {
    let (window, view) = makeIndependentHostedLayerView()
    CATransaction.flush()

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    view.layer?.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    CATransaction.commit()
    CATransaction.flush()
    XCTAssertNotEqual(
      view.layer?.frame, view.bounds, "前置條件失敗：hosted layer 未與 bounds 不同步")

    view.synchronizeHostedLayer()

    XCTAssertEqual(view.layer?.frame, view.bounds)
    XCTAssertEqual(view.layer?.animationKeys() ?? [], [])
    XCTAssertNotNil(window.contentView)
  }

  // MARK: - renderer sublayer contentsScale 搬遷後重發（1.4.0-W3-022）

  /// `move` 除了對齊 hosted layer 自身，還須重新下發至 renderer 掛在其上的
  /// sublayer：以人工設一個偏離值的 sublayer 模擬「搬遷前殘留舊 scale」，
  /// 斷言搬遷後被重新對齊，而非只有 contentLayer 自身對齊、sublayer 維持舊值。
  func testSublayerContentsScaleRealignsAfterMove() {
    let sublayer = CALayer()
    sublayer.contentsScale = surface.contentLayer.contentsScale + 1.0
    surface.contentLayer.addSublayer(sublayer)

    let moved = NSRect(
      x: testFrame.origin.x,
      y: testFrame.origin.y,
      width: testFrame.width + 100,
      height: testFrame.height + 100
    )
    surface.move(toScreenFrame: moved)

    XCTAssertEqual(sublayer.contentsScale, surface.contentLayer.contentsScale)
  }

  /// `mask` 掛在 sublayer 底下（非 `sublayers` 陣列成員，Spotlight 的
  /// `holeMask` 即此形態），搬遷後同樣須被重新對齊，不能只掃一層 sublayers
  /// 就視為完成。
  func testMaskedSublayerContentsScaleRealignsAfterMove() {
    let sublayer = CALayer()
    let mask = CALayer()
    mask.contentsScale = surface.contentLayer.contentsScale + 1.0
    sublayer.mask = mask
    surface.contentLayer.addSublayer(sublayer)

    let moved = NSRect(
      x: testFrame.origin.x,
      y: testFrame.origin.y,
      width: testFrame.width + 50,
      height: testFrame.height + 50
    )
    surface.move(toScreenFrame: moved)

    XCTAssertEqual(mask.contentsScale, surface.contentLayer.contentsScale)
  }
}

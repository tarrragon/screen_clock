import XCTest

@testable import screen_clock

/// 特效繪製的時間軸與設定接線基礎（子票 1.4.0-W3-001.1）。
///
/// 覆蓋四項基礎：normalized progress 的推進來源與夾限、每幀單一次游標取樣
/// 由繪製層共用、`request.tint` 與 `duration` 的實際消費、座標轉換。三種
/// 特效本身（聚光燈 / 邊框閃爍 / 波紋）不在本檔範圍。
final class CursorLocatorEffectFrameTests: XCTestCase {

  private let t0: CFTimeInterval = 1000.0
  private let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

  private var log: SurfaceCallLog!
  private var factory: SpySurfaceFactory!
  private var driver: ManualFrameDriver!
  private var scheduler: ManualDeadlineScheduler!
  private var renderer: SpyCursorLocatorRenderer!
  private var cursorBox: MutableValueBox<NSPoint>!
  private var sampleCount: MutableValueBox<Int>!
  private var controller: CursorLocatorEffectController!

  override func setUp() {
    super.setUp()
    log = SurfaceCallLog()
    factory = SpySurfaceFactory(log: log)
    driver = ManualFrameDriver(log: log)
    scheduler = ManualDeadlineScheduler()
    renderer = SpyCursorLocatorRenderer()
    cursorBox = MutableValueBox(NSPoint(x: 960, y: 540))
    sampleCount = MutableValueBox(0)
    controller = CursorLocatorEffectController(
      snapshotProvider: { ScreenSnapshotFixtures.singleMain },
      locationSampler: { [cursorBox, sampleCount] in
        sampleCount!.value += 1
        return cursorBox!.value
      },
      surfaceMaker: factory.make,
      frameDriver: driver,
      deadlineScheduler: scheduler.schedule,
      renderer: renderer
    )
  }

  override func tearDown() {
    controller = nil
    sampleCount = nil
    cursorBox = nil
    renderer = nil
    scheduler = nil
    driver = nil
    factory = nil
    log = nil
    super.tearDown()
  }

  // MARK: - normalized progress（純函式）

  func testProgress_isZeroAtStartAndOneAtEnd() {
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 0, duration: 1.5), 0,
      accuracy: 1e-9)
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 1.5, duration: 1.5), 1,
      accuracy: 1e-9)
  }

  func testProgress_isElapsedOverDuration() {
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 0.75, duration: 1.5), 0.5,
      accuracy: 1e-9)
  }

  /// 逾時保險或在途幀可能送來超過 duration 的 elapsed；夾限缺失會讓依 progress
  /// 推導半徑的特效在末段畫出超出規格範圍的圖形。
  func testProgress_clampsOutOfRangeElapsed() {
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 3.0, duration: 1.5), 1,
      accuracy: 1e-9)
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: -1.0, duration: 1.5), 0,
      accuracy: 1e-9)
  }

  func testProgress_nonPositiveDurationIsTreatedAsFinished() {
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 0, duration: 0), 1,
      accuracy: 1e-9)
    XCTAssertEqual(
      CursorLocatorEffectController.normalizedProgress(elapsed: 0, duration: -1), 1,
      accuracy: 1e-9)
  }

  // MARK: - 座標轉換（純函式）

  func testLayerPoint_subtractsScreenOriginWithoutFlippingY() {
    let point = CursorLocatorEffectController.layerPoint(
      forCursorLocation: NSPoint(x: 2100, y: 300),
      screenFrame: NSRect(x: 1920, y: 0, width: 1920, height: 1080)
    )
    XCTAssertEqual(point, CGPoint(x: 180, y: 300))
  }

  /// 第二螢幕位於主螢幕左方或下方時螢幕原點為負，減法必須照樣成立。
  func testLayerPoint_handlesNegativeScreenOrigin() {
    let point = CursorLocatorEffectController.layerPoint(
      forCursorLocation: NSPoint(x: -100, y: -200),
      screenFrame: NSRect(x: -1920, y: -1080, width: 1920, height: 1080)
    )
    XCTAssertEqual(point, CGPoint(x: 1820, y: 880))
  }

  // MARK: - progress 對齊 CVDisplayLink 而非牆鐘

  func testRenderedProgress_advancesWithDisplayLinkTimestamps() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 2.0, tint: .white))

    driver.emit(at: t0)
    driver.emit(at: t0 + 0.5)
    driver.emit(at: t0 + 1.0)

    XCTAssertEqual(renderer.frames.map { $0.progress }, [0, 0.25, 0.5])
    XCTAssertEqual(renderer.frames.map { $0.elapsed }, [0, 0.5, 1.0])
  }

  // MARK: - layerBounds 單一來源（1.4.0-W3-023）

  /// `layerBounds` 與 `cursorPointInLayer` 同一處（`deliverFrame`）填入，讀自
  /// `session.surface.contentLayer.bounds`，不是渲染層各自取樣的結果。先讓
  /// surface 的 `contentLayer` 落在一個刻意與 attach 時不同的尺寸，若
  /// `deliverFrame` 沒有逐幀重讀而是快取初始值，斷言即會落空。
  func testDeliverFrame_layerBoundsReflectsSurfaceContentLayerBounds() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 2.0, tint: .white))

    guard let surface = factory.weakBoxes.last?.value as? SpyCursorLocatorSurface else {
      return XCTFail("預期播放已建立 surface")
    }
    let resized = CGRect(x: 0, y: 0, width: 1280, height: 720)
    surface.contentLayer.frame = resized

    driver.emit(at: t0)

    XCTAssertEqual(renderer.frames.last?.layerBounds, surface.contentLayer.bounds)
    XCTAssertEqual(renderer.frames.last?.layerBounds.size, resized.size)
  }

  // MARK: - FR-03 與 FR-05 共用同一組取樣

  /// 一幀內只呼叫 `locationSampler` 一次：螢幕判定與繪製層共用同一次取樣。
  /// 各自取樣會使聚光燈亮區與波紋圓心在快速移動時偶發偏移。
  func testCursorSample_isTakenOncePerFrameAndSharedWithRenderer() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 2.0, tint: .white))
    let samplesAfterPlay = sampleCount.value

    cursorBox.value = NSPoint(x: 100, y: 200)
    driver.emit(at: t0)
    XCTAssertEqual(sampleCount.value - samplesAfterPlay, 1)

    cursorBox.value = NSPoint(x: 300, y: 400)
    driver.emit(at: t0 + 0.1)
    XCTAssertEqual(sampleCount.value - samplesAfterPlay, 2)

    XCTAssertEqual(
      renderer.frames.map { $0.cursorPointInLayer },
      [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 400)]
    )
  }

  // MARK: - tint 與 duration 的消費者

  func testAttach_receivesRequestTintAndDuration() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .red))

    XCTAssertEqual(
      renderer.attachments, [.init(tint: .red, duration: 1.5)])
    XCTAssertEqual(renderer.attachedLayers.count, 1)
  }

  func testRenderedFrame_carriesTintAndDuration() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .red))
    driver.emit(at: t0)

    XCTAssertEqual(renderer.frames.first?.tint, .red)
    XCTAssertEqual(renderer.frames.first?.duration, 1.5)
  }

  /// 重置（播放中再次觸發）時設定可能已變更，故須以新的時長與主色調重新
  /// attach，否則後續幀仍依舊參數繪製。
  func testReplay_reattachesWithNewTintAndDuration() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .red))
    try controller.play(CursorLocatorPlayRequest(duration: 3.0, tint: .green))

    XCTAssertEqual(
      renderer.attachments,
      [.init(tint: .red, duration: 1.5), .init(tint: .green, duration: 3.0)]
    )

    driver.emit(at: t0)
    XCTAssertEqual(renderer.frames.last?.tint, .green)
    XCTAssertEqual(renderer.frames.last?.duration, 3.0)
  }

  // MARK: - 繪製層生命週期

  func testDetach_isCalledWhenPlaybackEnds() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.0, tint: .white))
    XCTAssertEqual(renderer.detachCount, 0)

    driver.emit(at: t0)
    driver.emit(at: t0 + 1.0)

    XCTAssertEqual(renderer.detachCount, 1)
    XCTAssertEqual(renderer.frames.last?.progress, 1)
  }

  func testDetach_isCalledOnExplicitStop() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    controller.stop()

    XCTAssertEqual(renderer.detachCount, 1)
  }

  // MARK: - 廣播

  func testCompositeRenderer_broadcastsToEveryRenderer() {
    let first = SpyCursorLocatorRenderer()
    let second = SpyCursorLocatorRenderer()
    let composite = CursorLocatorCompositeRenderer(renderers: [first, second])
    let layer = CALayer()
    let frame = CursorLocatorEffectFrame(
      progress: 0.5,
      elapsed: 0.75,
      duration: 1.5,
      cursorPointInLayer: CGPoint(x: 10, y: 20),
      layerBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      tint: .blue
    )

    composite.attach(to: layer, tint: .blue, duration: 1.5)
    composite.render(frame)
    composite.detach()

    for spy in [first, second] {
      XCTAssertEqual(spy.attachments, [.init(tint: .blue, duration: 1.5)])
      XCTAssertEqual(spy.frames, [frame])
      XCTAssertEqual(spy.detachCount, 1)
    }
  }
}

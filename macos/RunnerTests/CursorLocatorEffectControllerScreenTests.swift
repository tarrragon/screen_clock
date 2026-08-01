import XCTest

@testable import screen_clock

/// `CursorLocatorEffectController` 螢幕接線、跨螢幕跟隨、熱插拔覆蓋。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計群組 D（T2.D-01 ~ D-08），
/// 覆蓋 Phase 1 GWT 場景 4、10、11、12。案例編號與母票 Test Design 保持
/// 一致，方便交叉核對。
///
/// 依 Phase 2 §1.3：測試 class 不持有 `static var` 可變狀態，fixture 一律於
/// `setUp` 重建。
final class CursorLocatorEffectControllerScreenTests: XCTestCase {

  private let t0: CFTimeInterval = 1000.0

  private var log: SurfaceCallLog!
  private var factory: SpySurfaceFactory!
  private var driver: ManualFrameDriver!
  private var scheduler: ManualDeadlineScheduler!
  private var snapshotBox: MutableValueBox<CursorScreenSnapshot>!
  private var cursorBox: MutableValueBox<NSPoint>!
  private var controller: CursorLocatorEffectController!

  override func setUp() {
    super.setUp()
    log = SurfaceCallLog()
    factory = SpySurfaceFactory(log: log)
    driver = ManualFrameDriver(log: log)
    scheduler = ManualDeadlineScheduler()
    snapshotBox = MutableValueBox(ScreenSnapshotFixtures.singleMain)
    cursorBox = MutableValueBox(NSPoint(x: 960, y: 540))
    controller = CursorLocatorEffectController(
      snapshotProvider: { [snapshotBox] in snapshotBox!.value },
      locationSampler: { [cursorBox] in cursorBox!.value },
      surfaceMaker: factory.make,
      frameDriver: driver,
      deadlineScheduler: scheduler.schedule
    )
  }

  override func tearDown() {
    controller = nil
    scheduler = nil
    driver = nil
    factory = nil
    log = nil
    snapshotBox = nil
    cursorBox = nil
    super.tearDown()
  }

  private func assertPlaying(
    _ state: CursorLocatorPlaybackState,
    elapsed: TimeInterval,
    duration: TimeInterval,
    screenFrame: NSRect,
    accuracy: TimeInterval = 1e-9,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .playing(let actualElapsed, let actualDuration, let actualFrame) = state else {
      XCTFail("預期 .playing，實際為 \(state)", file: file, line: line)
      return
    }
    XCTAssertEqual(actualElapsed, elapsed, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actualDuration, duration, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actualFrame, screenFrame, file: file, line: line)
  }

  // MARK: - 場景 4：接線（判定結果真的被拿去開視窗）

  /// T2.D-01：游標位於螢幕 B，工廠收到的引數恰為 B 的 frame 且僅被呼叫一次。
  /// 缺此案例時，判定正確但接線永遠傳 main 仍會全綠（母票 Phase 1.5 P0-5）。
  func testPlay_wiresResolvedScreenFrameIntoSurfaceFactory() throws {
    let snapshot = ScreenSnapshotFixtures.sideBySide
    snapshotBox.value = snapshot
    cursorBox.value = NSPoint(x: 2500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))

    XCTAssertEqual(factory.requestedFrames, [snapshot.entries[1].frame])

    driver.emit(at: t0)

    assertPlaying(controller.state, elapsed: 0, duration: 1.5, screenFrame: snapshot.entries[1].frame)
  }

  /// T2.D-02：退回 main 的判定結果同樣須被拿去開視窗。
  func testPlay_fallbackToMain_stillWiresFrameIntoFactory() throws {
    let snapshot = ScreenSnapshotFixtures.withGap
    snapshotBox.value = snapshot
    cursorBox.value = NSPoint(x: 2000, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))

    XCTAssertEqual(factory.requestedFrames, [snapshot.entries[1].frame])
  }

  // MARK: - 場景 10：跨螢幕跟隨

  /// T2.D-03：游標序列由 A 切至 B，surface 搬遷恰一次，move 與 retarget
  /// 於同一幀內成對出現。
  func testFrame_cursorMovesAcrossScreens_surfaceFollowsOnce() throws {
    let snapshot = ScreenSnapshotFixtures.sideBySide
    snapshotBox.value = snapshot
    cursorBox.value = NSPoint(x: 500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))

    driver.emit(at: t0)
    driver.emit(at: t0 + 0.1)
    driver.emit(at: t0 + 0.2)

    cursorBox.value = NSPoint(x: 2500, y: 500)
    driver.emit(at: t0 + 0.3)
    driver.emit(at: t0 + 0.4)
    driver.emit(at: t0 + 0.5)

    XCTAssertEqual(log.moveCount, 1)
    XCTAssertEqual(log.retargetedDisplayIDs, [snapshot.entries[1].displayID])

    guard
      let moveIndex = log.events.firstIndex(where: {
        if case .move = $0 { return true }
        return false
      }),
      let retargetIndex = log.events.firstIndex(where: {
        if case .retarget = $0 { return true }
        return false
      })
    else {
      XCTFail("應同時存在 move 與 retarget 事件")
      return
    }
    XCTAssertEqual(abs(moveIndex - retargetIndex), 1, "move 與 retarget 須於同一幀內成對出現")
  }

  /// T2.D-04：來回跨螢幕，搬遷判斷比較的是「當前所在」而非「是否曾搬遷過」。
  func testFrame_cursorMovesBackAndForth_surfaceFollowsEachTransition() throws {
    let snapshot = ScreenSnapshotFixtures.sideBySide
    snapshotBox.value = snapshot
    cursorBox.value = NSPoint(x: 500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))
    driver.emit(at: t0)

    cursorBox.value = NSPoint(x: 2500, y: 500)
    driver.emit(at: t0 + 0.1)

    cursorBox.value = NSPoint(x: 500, y: 500)
    driver.emit(at: t0 + 0.2)

    XCTAssertEqual(log.moveCount, 2)
    XCTAssertEqual(
      log.retargetedDisplayIDs,
      [snapshot.entries[1].displayID, snapshot.entries[0].displayID]
    )
  }

  /// T2.D-05：游標於同一螢幕內移動，不觸發 move/retarget。
  /// 與 T2.D-03 成對，防止實作每幀無條件 move 也讓 T2.D-03 通過。
  func testFrame_cursorStaysWithinSameScreen_doesNotTriggerMove() throws {
    let snapshot = ScreenSnapshotFixtures.sideBySide
    snapshotBox.value = snapshot
    cursorBox.value = NSPoint(x: 100, y: 100)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))
    driver.emit(at: t0)

    for k in 1...4 {
      cursorBox.value = NSPoint(x: 100 + Double(k) * 10, y: 100)
      driver.emit(at: t0 + 0.1 * Double(k))
    }

    XCTAssertEqual(log.moveCount, 0)
    XCTAssertTrue(log.retargetedDisplayIDs.isEmpty)
  }

  // MARK: - 場景 11 / 12：熱插拔

  /// T2.D-06：目標螢幕於第 3 幀起被拔除，surface 搬遷至重判定結果的
  /// frame，播放不中斷。
  func testFrame_targetScreenRemoved_surfaceMigratesToRemainingScreen() throws {
    snapshotBox.value = ScreenSnapshotFixtures.sideBySide
    cursorBox.value = NSPoint(x: 2500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.1)

    // 第 3 幀起改為只剩 A（游標仍在原 B 座標，現落於間隙，mainIndex=0）
    let remaining = ScreenSnapshotFixtures.singleMain
    snapshotBox.value = remaining
    driver.emit(at: t0 + 0.2)

    XCTAssertEqual(log.retargetedDisplayIDs.last, remaining.entries[0].displayID)
    guard case .playing(_, _, let frame) = controller.state else {
      XCTFail("播放不應中斷")
      return
    }
    XCTAssertEqual(frame, remaining.entries[0].frame)
  }

  /// T2.D-07：播放中螢幕數歸零，第 3 幀即立即 close 並回 idle，不 throw。
  func testFrame_allScreensGone_endsImmediatelyWithoutThrowing() throws {
    snapshotBox.value = ScreenSnapshotFixtures.singleMain
    cursorBox.value = NSPoint(x: 500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.1)

    snapshotBox.value = ScreenSnapshotFixtures.empty
    driver.emit(at: t0 + 0.2)

    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(driver.stopCount, 1)
    XCTAssertEqual(scheduler.cancelCount, 1)
    XCTAssertNil(factory.weakBoxes[0].value)
  }

  /// T2.D-08：螢幕歸零結束後續幀被世代序號攔下，涵蓋「自然結束」而非
  /// 「stop 結束」的在途幀，與 T2.C-11 同型。
  func testFrame_afterAllScreensGone_subsequentFrameIsIgnored() throws {
    snapshotBox.value = ScreenSnapshotFixtures.singleMain
    cursorBox.value = NSPoint(x: 500, y: 500)

    try controller.play(CursorLocatorPlayRequest(duration: 5.0, tint: .white))
    driver.emit(at: t0)

    snapshotBox.value = ScreenSnapshotFixtures.empty
    driver.emit(at: t0 + 0.1)

    let eventCountBefore = log.events.count
    snapshotBox.value = ScreenSnapshotFixtures.singleMain
    driver.emit(at: t0 + 0.2)

    XCTAssertEqual(log.events.count, eventCountBefore)
  }
}

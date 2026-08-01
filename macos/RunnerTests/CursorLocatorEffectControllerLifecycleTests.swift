import XCTest

@testable import screen_clock

/// `CursorLocatorEffectController` 生命週期覆蓋：播放／重置／釋放／淡出／
/// 逾時／stop。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計群組 C（T2.C-01 ~ C-19），
/// 覆蓋 Phase 1 GWT 場景 5~9、13~18。案例編號與母票 Test Design 保持一致，
/// 方便交叉核對。
///
/// 依 Phase 2 §1.3：測試 class 不持有 `static var` 可變狀態，fixture 一律於
/// `setUp` 重建，使各案例可獨立於 parallelizable 執行下正確隔離。
final class CursorLocatorEffectControllerLifecycleTests: XCTestCase {

  private let t0: CFTimeInterval = 1000.0

  private var log: SurfaceCallLog!
  private var factory: SpySurfaceFactory!
  private var driver: ManualFrameDriver!
  private var scheduler: ManualDeadlineScheduler!
  private var snapshotBox: MutableValueBox<CursorScreenSnapshot>!
  private var cursorBox: MutableValueBox<NSPoint>!
  private var controller: CursorLocatorEffectController!

  private var mainFrame: NSRect { ScreenSnapshotFixtures.singleMain.entries[0].frame }

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

  /// 以 accuracy 比較 `.playing` 的 elapsed/duration，不直接用 `Equatable`
  /// 對整個 enum 做精確浮點比對（母票 Phase 2 §四備註：elapsed 以 accuracy 比較）。
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

  // MARK: - 場景 5 / 6：單次播放釋放

  /// T2.C-01：單次播放，中途為 playing、結束後為 idle 並確實 close。
  func testPlay_singlePlayback_releasesAfterDuration() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.5)

    assertPlaying(controller.state, elapsed: 0.5, duration: 1.5, screenFrame: mainFrame)

    driver.emit(at: t0 + 1.5)

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(driver.stopCount, 1)
    XCTAssertEqual(scheduler.cancelCount, 1)
  }

  /// T2.C-02：釋放後 spy 的 weak 參照為 nil（S2）且 close 計數為 1（S1），
  /// 兩訊號同一案例內並列。
  func testPlay_afterRelease_weakReferenceIsNilAndCloseCountOne() throws {
    autoreleasepool {
      do {
        try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
        driver.emit(at: t0)
        driver.emit(at: t0 + 1.5)
      } catch {
        XCTFail("不應拋出: \(error)")
      }
    }

    XCTAssertNil(factory.weakBoxes[0].value)
    XCTAssertEqual(log.closeCount, 1)
  }

  /// T2.C-03：首幀即入 playing，起點時間戳取自首幀而非 play 當下的時鐘。
  func testPlay_firstFrame_entersPlayingWithZeroElapsed() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)

    assertPlaying(controller.state, elapsed: 0, duration: 1.5, screenFrame: mainFrame)
    XCTAssertEqual(log.makeCount, 1)
  }

  // MARK: - 場景 7 / 8：重複觸發

  /// T2.C-04：播放中再次 play 為重置，不建立第二個 surface。
  func testPlay_calledAgainWhilePlaying_resetsWithoutNewSurface() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.8)

    try controller.play(CursorLocatorPlayRequest(duration: 2.0, tint: .black))
    driver.emit(at: t0 + 0.8)

    XCTAssertEqual(log.makeCount, 1)
    XCTAssertEqual(log.closeCount, 0)
    assertPlaying(controller.state, elapsed: 0, duration: 2.0, screenFrame: mainFrame)
    XCTAssertEqual(log.alphaValues.last, 1.0)
  }

  /// T2.C-05：重置後時間重新起算，是「重置」與「疊加」的真正鑑別點。
  func testPlay_afterReset_newDurationCountsFromResetPoint() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.8)

    try controller.play(CursorLocatorPlayRequest(duration: 2.0, tint: .black))
    driver.emit(at: t0 + 0.8)
    driver.emit(at: t0 + 2.7)

    guard case .playing = controller.state else {
      XCTFail("重置起點為 t0+0.8，2.0 秒後才到 t0+2.8，t0+2.7 應仍在播放中")
      return
    }

    driver.emit(at: t0 + 2.8)

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(log.closeCount, 1)
  }

  /// T2.C-06：同一次播放期間連續 play 十次，工廠與 close 計數皆不變動。
  func testPlay_repeatedTenTimesWhilePlaying_doesNotAccumulateSurfaces() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)

    for k in 1...10 {
      try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
      driver.emit(at: t0 + 0.1 * Double(k))

      XCTAssertEqual(log.makeCount, 1, "第 \(k) 次觸發後仍不應建立第二個 surface")
      XCTAssertEqual(log.closeCount, 0, "第 \(k) 次觸發後不應 close")
      guard case .playing = controller.state else {
        XCTFail("第 \(k) 次觸發後應仍在播放中")
        return
      }
    }
  }

  // MARK: - 場景 9：十次完整播放無洩漏

  /// T2.C-07：連續十次完整播放，S1（close 計數）+ S2（weak 全數為 nil）
  /// 同時成立，禁止以任一單一訊號冒充無洩漏證據。
  func testPlay_tenCompletePlaybacks_leavesNoSurfaceLeak() throws {
    for k in 0..<10 {
      autoreleasepool {
        let base = t0 + Double(k) * 10
        do {
          try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
          driver.emit(at: base)
          driver.emit(at: base + 1.5)
        } catch {
          XCTFail("不應拋出: \(error)")
        }
      }

      XCTAssertEqual(controller.state, .idle)
    }

    XCTAssertEqual(log.makeCount, 10)
    XCTAssertEqual(log.closeCount, 10)
    XCTAssertEqual(factory.weakBoxes.count, 10)
    for box in factory.weakBoxes {
      XCTAssertNil(box.value)
    }
  }

  // MARK: - 場景 14：逾時保險

  /// T2.C-08：完全不送幀，僅觸發逾時保險，涵蓋 CVDisplayLink 完全停擺情形。
  func testPlay_timeoutInsurance_forcesEndWhenNoFramesArrive() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))

    XCTAssertEqual(scheduler.scheduledDelays, [2.0])

    scheduler.fire()

    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(driver.stopCount, 1)
    XCTAssertNil(factory.weakBoxes[0].value)
  }

  /// T2.C-09：正常結束後逾時保險已被取消，二次觸發為 no-op，不二次 close。
  func testPlay_afterNaturalEnd_timeoutFireIsNoOp() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 1.5)

    scheduler.fire()

    XCTAssertEqual(log.closeCount, 1)
  }

  // MARK: - 場景 15 / 16 / 17：stop

  /// T2.C-10：播放中呼叫 stop，立即釋放。
  func testStop_whilePlaying_releasesImmediately() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)

    controller.stop()

    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(driver.stopCount, 1)
    XCTAssertEqual(scheduler.cancelCount, 1)
    XCTAssertNil(factory.weakBoxes[0].value)
  }

  /// T2.C-11：stop 後在途幀對已關閉的 surface 未做任何呼叫，事件總數不變。
  func testStop_thenStaleFrame_isIgnored() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    controller.stop()

    let eventCountBefore = log.events.count
    driver.emit(at: t0 + 0.2)

    XCTAssertEqual(log.events.count, eventCountBefore)
    XCTAssertEqual(controller.state, .idle)
  }

  /// T2.C-12：跨輪次的舊世代閉包送幀同樣被攔下，非只擋 stop 後的幀。
  func testPlay_afterStopAndReplay_staleClosureFromPreviousGenerationIsIgnored() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    let staleOnFrame = driver.onFrame
    controller.stop()

    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    let eventCountAfterSecondPlay = log.events.count

    staleOnFrame?(t0 + 0.1)

    XCTAssertEqual(log.makeCount, 2)
    XCTAssertEqual(
      log.events.count, eventCountAfterSecondPlay,
      "舊世代閉包送幀不應在新一輪 surface 上留下任何事件"
    )
  }

  /// T2.C-13：idle 時 stop 為 no-op，且冪等（可重複呼叫）。
  func testStop_whileIdle_isNoOp() {
    XCTAssertTrue(log.events.isEmpty)

    controller.stop()
    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(log.events.isEmpty)

    controller.stop()
    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(log.events.isEmpty)
  }

  // MARK: - 場景 13：淡出

  /// T2.C-14：淡出窗起點之前，未曾出現任何 alpha 設定呼叫。
  func testFadeWindow_beforeThreshold_noAlphaCallsRecorded() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    // fadeDuration = min(0.2, 1.5*0.4=0.6) = 0.2；窗起於 elapsed 1.3
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.5)
    driver.emit(at: t0 + 1.0)
    driver.emit(at: t0 + 1.29)

    XCTAssertTrue(log.alphaValues.isEmpty)
  }

  /// T2.C-15：淡出窗內 alpha 嚴格遞減且落於 (0, 1)，鎖定線性曲線契約。
  ///
  /// 起點取 elapsed=1.31（非窗口起點 1.3 本身），避開絕對時間戳相加產生的
  /// 浮點誤差落在「恰為門檻」這種對 `>=` 比較方向敏感的邊界（同一組固定
  /// 值 `t0=1000.0` 與 `duration-fadeDuration=1.3` 相加/相減後，`elapsed`
  /// 實際運算結果會些微小於門檻，屬絕對時間戳設計下的已知浮點特性，非
  /// 實作缺陷）。
  func testFadeWindow_afterThreshold_alphaDecreasesMonotonicallyToZero() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 1.31)
    driver.emit(at: t0 + 1.35)
    driver.emit(at: t0 + 1.40)
    driver.emit(at: t0 + 1.45)
    driver.emit(at: t0 + 1.49)

    let values = log.alphaValues
    XCTAssertEqual(values.count, 5)
    for i in 1..<values.count {
      XCTAssertLessThan(values[i], values[i - 1])
    }
    XCTAssertEqual(values[0], 0.95, accuracy: 1e-6)
    XCTAssertEqual(values.last!, 0.05, accuracy: 1e-6)
  }

  /// T2.C-16：短時長（0.4 秒）驗證 `min` 分支的比例側，避免只測到固定 0.2。
  func testFadeWindow_shortDuration_usesProportionalWindow() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 0.4, tint: .white))
    // fadeDuration = min(0.2, 0.4*0.4=0.16) = 0.16；窗起於 elapsed 0.24
    driver.emit(at: t0)
    driver.emit(at: t0 + 0.20)

    XCTAssertTrue(log.alphaValues.isEmpty)

    driver.emit(at: t0 + 0.30)

    guard let alpha = log.alphaValues.last else {
      XCTFail("elapsed 0.30 應已進入淡出窗")
      return
    }
    XCTAssertGreaterThan(alpha, 0)
    XCTAssertLessThan(alpha, 1)
  }

  /// T2.C-17：淡出含在 duration 內，總時長恆等於使用者設定值。
  func testDuration_totalPlaybackEqualsConfiguredValue() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    driver.emit(at: t0)
    driver.emit(at: t0 + 1.4999)

    guard case .playing = controller.state else {
      XCTFail("elapsed 1.4999 應仍在播放中")
      return
    }

    driver.emit(at: t0 + 1.5)

    XCTAssertEqual(controller.state, .idle)
  }

  // MARK: - 場景 18：duration 邊界

  /// T2.C-18：duration 為 0，首幀即結束，不 throw。
  func testPlay_zeroDuration_endsOnFirstFrame() throws {
    try controller.play(CursorLocatorPlayRequest(duration: 0, tint: .white))
    driver.emit(at: t0)

    XCTAssertEqual(log.makeCount, 1)
    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertNil(factory.weakBoxes[0].value)
  }

  /// T2.C-19：duration 為負值（Dart 側已約束但原生層須有定義行為的殘餘輸入）。
  func testPlay_negativeDuration_endsOnFirstFrame() throws {
    try controller.play(CursorLocatorPlayRequest(duration: -1, tint: .white))
    driver.emit(at: t0)

    XCTAssertEqual(log.makeCount, 1)
    XCTAssertEqual(log.closeCount, 1)
    XCTAssertEqual(controller.state, .idle)
  }
}

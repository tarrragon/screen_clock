import FlutterMacOS
import XCTest

@testable import screen_clock

/// 錯誤路徑與 `FlutterError` 對應覆蓋。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計群組 E（T2.E-01 ~ E-06），
/// 覆蓋 Phase 1 GWT 場景 19、20、21。
///
/// 依 Phase 2 §1.3：測試 class 不持有 `static var` 可變狀態，fixture 一律於
/// `setUp` 重建。
final class CursorLocatorErrorMappingTests: XCTestCase {

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

  /// T2.E-01（場景 19 視窗建立失敗）：拋出 windowCreationFailed，狀態維持
  /// idle，且失敗路徑不留下未取消的排程或已啟動的驅動。
  func testWindowCreationFailureThrowsAndLeavesNoResidualScheduling() {
    factory = SpySurfaceFactory(log: log, behavior: .throwOnCall(1))
    controller = CursorLocatorEffectController(
      snapshotProvider: { [snapshotBox] in snapshotBox!.value },
      locationSampler: { [cursorBox] in cursorBox!.value },
      surfaceMaker: factory.make,
      frameDriver: driver,
      deadlineScheduler: scheduler.schedule
    )

    XCTAssertThrowsError(
      try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    ) { error in
      guard case CursorLocatorError.windowCreationFailed = error else {
        XCTFail("預期 .windowCreationFailed，實際為 \(error)")
        return
      }
    }

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(driver.startCount, 0)
    XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
  }

  /// T2.E-02（場景 19 失敗後可再次 play）：失敗未使狀態機卡死。
  func testPlayAgainAfterFailureSucceeds() {
    factory = SpySurfaceFactory(log: log, behavior: .throwOnCall(1))
    controller = CursorLocatorEffectController(
      snapshotProvider: { [snapshotBox] in snapshotBox!.value },
      locationSampler: { [cursorBox] in cursorBox!.value },
      surfaceMaker: factory.make,
      frameDriver: driver,
      deadlineScheduler: scheduler.schedule
    )

    XCTAssertThrowsError(
      try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    )

    // 第二次呼叫改為成功行為
    factory = SpySurfaceFactory(log: log, behavior: .succeed)
    controller = CursorLocatorEffectController(
      snapshotProvider: { [snapshotBox] in snapshotBox!.value },
      locationSampler: { [cursorBox] in cursorBox!.value },
      surfaceMaker: factory.make,
      frameDriver: driver,
      deadlineScheduler: scheduler.schedule
    )

    XCTAssertNoThrow(try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white)))
    driver.emit(at: t0)
    guard case .playing = controller.state else {
      XCTFail("預期 .playing，實際為 \(controller.state)")
      return
    }
  }

  /// T2.E-03（場景 21 無可用螢幕）：拋出 noAvailableScreen，工廠未被呼叫、
  /// 驅動未啟動。
  func testNoAvailableScreenThrowsWithoutTouchingFactoryOrDriver() {
    snapshotBox.value = ScreenSnapshotFixtures.empty

    XCTAssertThrowsError(
      try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white))
    ) { error in
      guard case CursorLocatorError.noAvailableScreen = error else {
        XCTFail("預期 .noAvailableScreen，實際為 \(error)")
        return
      }
    }

    XCTAssertTrue(factory.requestedFrames.isEmpty)
    XCTAssertEqual(driver.startCount, 0)
  }

  /// T2.E-04（場景 20 退回 main 不中斷）：不 throw，於 main 的 frame 建立
  /// surface，且能正常推進至結束。
  func testFallbackToMainDoesNotThrowAndReleasesNormally() {
    snapshotBox.value = ScreenSnapshotFixtures.withGap
    cursorBox.value = NSPoint(x: 2000, y: 500)  // 落於間隙

    let mainEntry = ScreenSnapshotFixtures.withGap.entries[1]

    XCTAssertNoThrow(try controller.play(CursorLocatorPlayRequest(duration: 1.5, tint: .white)))
    XCTAssertEqual(factory.requestedFrames, [mainEntry.frame])

    driver.emit(at: t0)
    driver.emit(at: t0 + 1.5)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(log.closeCount, 1)
  }

  /// T2.E-05（場景 19/21 錯誤碼字面）：以字串字面逐字斷言，不引用實作端
  /// 常數（母票 Phase 2 §四反向約束）——常數改名時本斷言須同步改，
  /// 錯誤碼契約才有鎖定力。
  func testErrorMappingUsesLiteralErrorCodes() {
    let windowError = CursorLocatorErrorMapping.flutterError(
      for: .windowCreationFailed(underlying: "underlying-reason")
    )
    XCTAssertEqual(windowError?.code, "E_CL_WINDOW")
    XCTAssertEqual(windowError?.details as? String, "underlying-reason")

    let screenError = CursorLocatorErrorMapping.flutterError(for: .noAvailableScreen)
    XCTAssertEqual(screenError?.code, "E_CL_SCREEN")
  }

  /// T2.E-06（場景 20 成功回傳）：對應函式輸入為「無錯誤」情形時回傳 nil，
  /// 對應 `result(nil)` 語意。
  func testErrorMappingReturnsNilForSuccess() {
    XCTAssertNil(CursorLocatorErrorMapping.flutterError(for: nil))
  }
}

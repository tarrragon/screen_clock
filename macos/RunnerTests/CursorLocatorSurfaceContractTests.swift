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
}

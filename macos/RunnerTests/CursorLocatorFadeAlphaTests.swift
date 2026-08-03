import XCTest

@testable import screen_clock

/// `CursorLocatorEffectController.fadeAlpha(elapsed:duration:)` 純函式覆蓋。
///
/// 對應 1.4.0-W3-009：淡出計算自 `handleFrame` 外提為純函式，acceptance 第 2
/// 條要求成為「可獨立測試的數學」。既有 `CursorLocatorEffectControllerLifecycleTests`
/// 的 `testFadeWindow_*` 群組經控制器整體驅動覆蓋同一計算的行為面；本檔補上
/// 純函式邊界值的直接覆蓋，兩者互補、不互相取代。
final class CursorLocatorFadeAlphaTests: XCTestCase {

  private func assertAlpha(
    elapsed: TimeInterval,
    duration: TimeInterval,
    equals expected: CGFloat,
    accuracy: CGFloat = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let alpha = CursorLocatorEffectController.fadeAlpha(elapsed: elapsed, duration: duration) else {
      XCTFail("expected non-nil alpha", file: file, line: line)
      return
    }
    XCTAssertEqual(alpha, expected, accuracy: accuracy, file: file, line: line)
  }

  /// 淡出窗定義：`min(fadeDurationCap, duration * fadeDurationRatio)`。
  /// duration=1.0 時窗為 `min(0.2, 0.4) = 0.2`，fadeStart = 0.8。
  func testFadeAlpha_beforeFadeWindow_returnsNil() {
    let alpha = CursorLocatorEffectController.fadeAlpha(elapsed: 0.5, duration: 1.0)
    XCTAssertNil(alpha)
  }

  func testFadeAlpha_atFadeWindowStart_returnsOne() {
    assertAlpha(elapsed: 0.8, duration: 1.0, equals: 1.0)
  }

  func testFadeAlpha_midFadeWindow_returnsProportionalValue() {
    // remaining = 1.0 - 0.9 = 0.1；fadeDuration = 0.2；0.1/0.2 = 0.5
    assertAlpha(elapsed: 0.9, duration: 1.0, equals: 0.5)
  }

  func testFadeAlpha_atDurationEnd_returnsZero() {
    assertAlpha(elapsed: 1.0, duration: 1.0, equals: 0.0)
  }

  func testFadeAlpha_pastDurationEnd_clampsToZero() {
    // elapsed 超過 duration 時 remaining 為負，須 clamp 不回傳負值。
    assertAlpha(elapsed: 1.5, duration: 1.0, equals: 0.0)
  }

  /// 短 duration：fadeDurationRatio 主導（duration * 0.4 < fadeDurationCap）。
  /// duration=0.3 → fadeDuration = min(0.2, 0.12) = 0.12，fadeStart = 0.18。
  func testFadeAlpha_shortDuration_usesProportionalWindowNotCap() {
    let beforeWindow = CursorLocatorEffectController.fadeAlpha(elapsed: 0.1, duration: 0.3)
    XCTAssertNil(beforeWindow)

    // remaining = 0.06；fadeDuration = 0.12；0.06/0.12 = 0.5
    assertAlpha(elapsed: 0.24, duration: 0.3, equals: 0.5)
  }

  /// duration <= 0 時 fadeDuration <= 0，不進入淡出窗，回傳 nil（呼叫端維持
  /// 既有 alpha，不設定為異常值）。此為 handleFrame 抽取前隱含於
  /// `fadeDuration > 0` 守衛的邊界，抽取後獨立覆蓋。
  func testFadeAlpha_zeroDuration_returnsNil() {
    let alpha = CursorLocatorEffectController.fadeAlpha(elapsed: 0.0, duration: 0.0)
    XCTAssertNil(alpha)
  }

  func testFadeAlpha_negativeDuration_returnsNil() {
    let alpha = CursorLocatorEffectController.fadeAlpha(elapsed: 0.0, duration: -1.0)
    XCTAssertNil(alpha)
  }
}

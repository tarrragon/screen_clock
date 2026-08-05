import XCTest

@testable import screen_clock

/// `ButtonEventConsumption` 的 Hotkey down/up 消費配對覆蓋（SPEC-007 FR-03，
/// 1.4.0-W1-020 判定的缺口修正，ticket 1.4.0-W1-028 acceptance 1/3）。
///
/// 依 Phase 2 慣例（`CursorLocatorErrorMappingTests` 先例）：測試 class 不
/// 持有 `static var` 可變狀態，fixture 一律於 `setUp` 重建。
final class ButtonEventConsumptionTests: XCTestCase {

  private var subject: ButtonEventConsumption!

  override func setUp() {
    super.setUp()
    subject = ButtonEventConsumption()
  }

  override func tearDown() {
    subject = nil
    super.tearDown()
  }

  /// 未記錄任何 Hotkey down 時，任意 button 的 mouseUp 都不應被消費
  /// （放行是預設行為，對齊未綁定側鍵的既有語意）。
  func testUnrecordedButtonUpIsNotConsumed() {
    XCTAssertFalse(subject.consumeHotkeyUpIfMatched(button: 3))
  }

  /// acceptance 1：記錄某 button 的 Hotkey down 已消費後，同一 button 的
  /// mouseUp 應被消費（回傳 true）。
  func testMatchedButtonUpIsConsumedAfterDownRecorded() {
    subject.recordHotkeyDownConsumed(button: 3)

    XCTAssertTrue(subject.consumeHotkeyUpIfMatched(button: 3))
  }

  /// 消費是一次性配對：同一 button 的 up 被消費後，狀態即清除，之後同一
  /// button 若再出現 up（無對應新 down）不應再次消費。
  func testConsumptionIsOneShotPerButton() {
    subject.recordHotkeyDownConsumed(button: 3)

    XCTAssertTrue(subject.consumeHotkeyUpIfMatched(button: 3))
    XCTAssertFalse(subject.consumeHotkeyUpIfMatched(button: 3))
  }

  /// 記錄的是特定 button，不應誤消費其他未記錄 button 的 mouseUp（多鍵
  /// 綁定情境下彼此獨立）。
  func testRecordedButtonDoesNotConsumeDifferentButtonUp() {
    subject.recordHotkeyDownConsumed(button: 3)

    XCTAssertFalse(subject.consumeHotkeyUpIfMatched(button: 4))
    // 原記錄不受影響，button 3 仍應在後續被正確消費。
    XCTAssertTrue(subject.consumeHotkeyUpIfMatched(button: 3))
  }

  /// 多個 button 可同時記錄（容忍多側鍵近乎同時按下），各自獨立消費。
  func testMultipleButtonsAreTrackedIndependently() {
    subject.recordHotkeyDownConsumed(button: 3)
    subject.recordHotkeyDownConsumed(button: 4)

    XCTAssertTrue(subject.consumeHotkeyUpIfMatched(button: 4))
    XCTAssertTrue(subject.consumeHotkeyUpIfMatched(button: 3))
  }
}

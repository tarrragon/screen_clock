import XCTest

@testable import screen_clock

/// 螢幕判定純函式（`CursorScreenLocator.resolve`）的 XCTest 覆蓋。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計群組 A（T1.A-01 ~ A-15），
/// 覆蓋 Phase 1 GWT 場景 1、2、3、3b、3c、3d。案例編號與母票 Test Design
/// 保持一致，方便交叉核對。
final class CursorScreenLocatorTests: XCTestCase {

  // MARK: - 場景 1：正常判定

  /// T1.A-01：兩個不重疊 entry，游標落在第二個 frame 內 -> 命中該螢幕。
  /// 以整個 enum 做等值比較，確保回傳的是 `.matched` 而非 `.fellBackToMain(1)`。
  func testResolve_cursorInsideSecondScreen_returnsMatchedAtIndexOne() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 2000, y: 500),
      in: ScreenSnapshotFixtures.sideBySide
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  // MARK: - 場景 2：間隙退回

  /// T1.A-02：游標落在兩螢幕間的未涵蓋間隙 -> 退回 main。
  /// index 必須等於 mainIndex（1）而非 0（fixture 刻意將 main 設在非 0 索引）。
  func testResolve_cursorInGap_fallsBackToMainIndex() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 2000, y: 500),
      in: ScreenSnapshotFixtures.withGap
    )

    XCTAssertEqual(result, .fellBackToMain(index: 1))
  }

  // MARK: - 場景 3：邊界座標（半開區間語意）

  /// T1.A-03：游標恰在共用邊界 x=1920 -> 命中右側螢幕。
  /// 鎖定 `NSRect.contains(_:)` 的半開區間語意（minX 為閉端、maxX 為開端）。
  func testResolve_cursorAtSharedBoundary_matchesRightScreen() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 1920, y: 500),
      in: ScreenSnapshotFixtures.sideBySide
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  /// T1.A-04：驗證邊界座標不會同時命中兩個螢幕，也不會兩個都不命中。
  /// 與 T1.A-03 分開：前者驗「命中誰」，本案驗「命中數恰為 1」。
  func testResolve_cursorAtSharedBoundary_matchesExactlyOneScreen() {
    let cursor = NSPoint(x: 1920, y: 500)
    let hitCount = ScreenSnapshotFixtures.sideBySide.entries
      .filter { $0.frame.contains(cursor) }
      .count

    XCTAssertEqual(hitCount, 1)
  }

  /// T1.A-05：游標恰在 maxY -> 不屬任何螢幕（上邊界為開端），退回 main。
  /// 驗證半開區間語意在 y 軸同樣成立。
  func testResolve_cursorAtMaxY_isExcludedAndFallsBackToMain() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 500, y: 1080),
      in: ScreenSnapshotFixtures.sideBySide
    )

    XCTAssertEqual(result, .fellBackToMain(index: 0))
  }

  /// T1.A-06：游標恰在 (0, 0)（minX/minY）-> 命中該螢幕（下／左邊界為閉端）。
  func testResolve_cursorAtMinXMinY_matchesFirstScreen() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 0, y: 0),
      in: ScreenSnapshotFixtures.sideBySide
    )

    XCTAssertEqual(result, .matched(index: 0))
  }

  // MARK: - 場景 3b：負座標排列

  /// T1.A-07：第二螢幕位於主螢幕左方（負 x），游標落於第二螢幕內 -> 命中。
  func testResolve_secondaryScreenAtNegativeX_matchesCorrectly() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: -960, y: 540),
      in: ScreenSnapshotFixtures.secondaryLeft
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  /// T1.A-08：第二螢幕位於主螢幕下方（負 y），游標落於第二螢幕內 -> 命中。
  func testResolve_secondaryScreenAtNegativeY_matchesCorrectly() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 960, y: -540),
      in: ScreenSnapshotFixtures.secondaryBelow
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  /// T1.A-09：第二螢幕位於主螢幕上方（正 y）對照組。
  /// 與 T1.A-08 成對，證明判定對 y 正負皆正確而非湊巧命中。
  func testResolve_secondaryScreenAtPositiveY_matchesCorrectly() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 960, y: 1620),
      in: ScreenSnapshotFixtures.secondaryAbove
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  /// T1.A-10：負座標上的 minX 邊界（閉端）。防止實作以 `abs` 或非負假設處理座標。
  func testResolve_negativeMinXBoundary_isInclusive() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: -1920, y: 0),
      in: ScreenSnapshotFixtures.secondaryLeft
    )

    XCTAssertEqual(result, .matched(index: 1))
  }

  // MARK: - 場景 3c：無可用螢幕

  /// T1.A-11：entries 為空、mainIndex 為 nil -> 無可用螢幕。
  func testResolve_emptyEntriesAndNilMain_returnsUnavailable() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 0, y: 0),
      in: ScreenSnapshotFixtures.empty
    )

    XCTAssertEqual(result, .unavailable)
  }

  /// T1.A-12：entries 非空但 mainIndex 為 nil、游標落於間隙 -> 無可用螢幕。
  /// 與 T1.A-11 分開：驗「unavailable 的條件是 mainIndex 為 nil」而非「entries 為空」。
  func testResolve_noMainIndexWithEntriesPresent_returnsUnavailable() {
    let snapshot = CursorScreenSnapshot(
      entries: [
        .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
        .init(frame: NSRect(x: 2400, y: 0, width: 1920, height: 1080), displayID: 2),
      ],
      mainIndex: nil
    )

    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 2000, y: 500),
      in: snapshot
    )

    XCTAssertEqual(result, .unavailable)
  }

  // MARK: - 場景 3d：重疊排列

  /// T1.A-13：兩螢幕重疊，游標落於重疊區 -> 取索引最小者，不做面積或距離仲裁。
  func testResolve_overlappingScreens_matchesSmallestIndex() {
    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 1200, y: 500),
      in: ScreenSnapshotFixtures.overlapping
    )

    XCTAssertEqual(result, .matched(index: 0))
  }

  /// T1.A-14：重疊排列但 entries 順序對調 -> 仍為陣列首位命中者（索引 0）。
  /// 證明判定「取索引最小」而非「取某個固定螢幕」。
  func testResolve_overlappingScreensReordered_matchesFirstInArrayOrder() {
    let reordered = CursorScreenSnapshot(
      entries: [
        ScreenSnapshotFixtures.overlapping.entries[1],
        ScreenSnapshotFixtures.overlapping.entries[0],
      ],
      mainIndex: 0
    )

    let result = CursorScreenLocator.resolve(
      cursorLocation: NSPoint(x: 1200, y: 500),
      in: reordered
    )

    XCTAssertEqual(result, .matched(index: 0))
  }

  // MARK: - §六：純度

  /// T1.A-15：連續呼叫 `resolve` 三次，回傳值皆相同。
  /// 純度的結構性保證來自函式簽章不含 `NSScreen`；本案例只做冪等回歸。
  func testResolve_calledRepeatedly_isIdempotent() {
    let cursor = NSPoint(x: 2000, y: 500)

    let first = CursorScreenLocator.resolve(cursorLocation: cursor, in: ScreenSnapshotFixtures.sideBySide)
    let second = CursorScreenLocator.resolve(cursorLocation: cursor, in: ScreenSnapshotFixtures.sideBySide)
    let third = CursorScreenLocator.resolve(cursorLocation: cursor, in: ScreenSnapshotFixtures.sideBySide)

    XCTAssertEqual(first, second)
    XCTAssertEqual(second, third)
  }
}

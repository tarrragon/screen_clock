import Cocoa

@testable import screen_clock

/// 螢幕判定測試用的固定排列常數。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計 §二 2.6 節。全域 AppKit 座標
/// （左下原點、y 軸向上為正）。
///
/// 本檔案僅收錄純資料的螢幕快照 fixture，不含 spy surface / spy 工廠 / 手動
/// driver / 手動 deadline scheduler——那些型別依賴 `CursorLocatorSurface`、
/// `CursorLocatorFrameDriving`、`CursorLocatorDeadlineScheduling` 三個協定
/// /函式型別，皆屬子票 1.4.0-W2-006.2「定義注入介面」的交付範圍（母票 Phase
/// 3a §四 步驟 1），本子票明確不建立特效視窗控制器，故不在此提前宣告。
enum ScreenSnapshotFixtures {

  /// 兩螢幕左右並排，無間隙。場景 1、3。
  static let sideBySide = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: 1920, y: 0, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 0
  )

  /// 兩螢幕之間存在未涵蓋間隙。mainIndex 刻意設為 1（而非 0），避免實作把
  /// `.fellBackToMain` 誤寫成固定回傳 index 0 也能通過。場景 2、20。
  static let withGap = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: 2400, y: 0, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 1
  )

  /// 第二螢幕位於主螢幕左方（負 x）。場景 3b。
  static let secondaryLeft = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: -1920, y: 0, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 0
  )

  /// 第二螢幕位於主螢幕下方（負 y）。場景 3b。
  static let secondaryBelow = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: 0, y: -1080, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 0
  )

  /// 第二螢幕位於主螢幕上方（正 y），作為負座標對照組。場景 3b。
  static let secondaryAbove = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: 0, y: 1080, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 0
  )

  /// 兩螢幕重疊排列，用於驗證取索引最小者、不做面積或距離仲裁。場景 3d。
  static let overlapping = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1),
      .init(frame: NSRect(x: 960, y: 0, width: 1920, height: 1080), displayID: 2),
    ],
    mainIndex: 0
  )

  /// 無任何螢幕，且無 main。場景 3c、21。
  static let empty = CursorScreenSnapshot(entries: [], mainIndex: nil)

  /// 單一主螢幕。場景 12 前態、預設情形。
  static let singleMain = CursorScreenSnapshot(
    entries: [
      .init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
    ],
    mainIndex: 0
  )
}

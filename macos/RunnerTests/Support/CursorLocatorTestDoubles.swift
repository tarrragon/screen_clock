import Cocoa
import QuartzCore

@testable import screen_clock

/// 螢幕判定測試用的固定排列常數。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計 §二 2.6 節。全域 AppKit 座標
/// （左下原點、y 軸向上為正）。
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

/// 可變的單值容器，供測試以 closure 形式注入「可於測試過程中被替換」的
/// 螢幕快照或游標座標（如 T2.D-06/D-07 於第 N 幀起換掉快照內容）。
///
/// 對應 1.4.0-W2-006 母票 TDD Phase 2 測試設計 §二。命名為泛型容器而非
/// 針對單一用途，因快照與游標座標共用同一「可變值」需求。
final class MutableValueBox<Value> {
  var value: Value

  init(_ value: Value) {
    self.value = value
  }
}

// MARK: - 特效視窗控制器測試替身（子票 1.4.0-W2-006.2.1）

/// 記錄所有 surface / driver 呼叫的共享日誌。
///
/// 設計要點（母票 Phase 2 §二 2.1 + Phase 3a §二）：日誌必須由測試強持有，
/// spy 與 driver 只持有其參照——如此 spy dealloc 後計數仍可斷言，這是
/// acceptance 5 洩漏斷言（S1 呼叫面 + S2 記憶體面）能同時成立的前提。
///
/// 計數與衍生值一律由 `events` 導出，不另存欄位，避免兩份真相不同步。
final class SurfaceCallLog {
  enum Event: Equatable {
    case made(NSRect)
    case move(NSRect)
    case setAlpha(CGFloat)
    case close
    case retarget(CGDirectDisplayID)
  }

  private(set) var events: [Event] = []

  func record(_ event: Event) {
    events.append(event)
  }

  var makeCount: Int {
    events.filter {
      if case .made = $0 { return true }
      return false
    }.count
  }

  var closeCount: Int {
    events.filter {
      if case .close = $0 { return true }
      return false
    }.count
  }

  var moveCount: Int {
    events.filter {
      if case .move = $0 { return true }
      return false
    }.count
  }

  var alphaValues: [CGFloat] {
    events.compactMap {
      if case .setAlpha(let value) = $0 { return value }
      return nil
    }
  }

  var retargetedDisplayIDs: [CGDirectDisplayID] {
    events.compactMap {
      if case .retarget(let id) = $0 { return id }
      return nil
    }
  }
}

/// 實作 `CursorLocatorSurface`。不記錄自身狀態（狀態即事件），也不被工廠
/// 強持有——這兩點是洩漏斷言 S2（weak 為 nil）成立的前提。
final class SpyCursorLocatorSurface: CursorLocatorSurface {
  let contentLayer: CALayer = CALayer()

  private let log: SurfaceCallLog

  init(log: SurfaceCallLog) {
    self.log = log
  }

  func move(toScreenFrame frame: NSRect) {
    log.record(.move(frame))
  }

  func setAlpha(_ value: CGFloat) {
    log.record(.setAlpha(value))
  }

  func close() {
    log.record(.close)
  }
}

/// 提供 `CursorLocatorSurfaceMaking`。持有 `weakBoxes` 與 `requestedFrames`
/// 供接線與洩漏斷言使用；不得持有 spy 的強參照。
final class SpySurfaceFactory {
  final class WeakBox {
    weak var value: AnyObject?

    init(_ value: AnyObject) {
      self.value = value
    }
  }

  enum Behavior {
    case succeed
    case throwOnCall(Int)
  }

  struct FactoryError: Error, Equatable {
    let reason: String
  }

  private let log: SurfaceCallLog
  private let behavior: Behavior

  private(set) var weakBoxes: [WeakBox] = []
  private(set) var requestedFrames: [NSRect] = []

  init(log: SurfaceCallLog, behavior: Behavior = .succeed) {
    self.log = log
    self.behavior = behavior
  }

  func make(_ frame: NSRect) throws -> CursorLocatorSurface {
    requestedFrames.append(frame)

    if case .throwOnCall(let n) = behavior, requestedFrames.count == n {
      throw FactoryError(reason: "spy factory 依設定於第 \(n) 次呼叫拋出")
    }

    let surface = SpyCursorLocatorSurface(log: log)
    weakBoxes.append(WeakBox(surface))
    log.record(.made(frame))
    return surface
  }
}

/// 實作 `CursorLocatorFrameDriving`。`stop()` 只標記狀態、刻意保留
/// `onFrame` 閉包不清除——場景 17 需要在 `stop()` 之後仍能人為送出一幀，
/// 模擬 CVDisplayLink 在途回呼。
final class ManualFrameDriver: CursorLocatorFrameDriving {
  private let log: SurfaceCallLog

  private(set) var onFrame: ((CFTimeInterval) -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init(log: SurfaceCallLog) {
    self.log = log
  }

  func start(displayID: CGDirectDisplayID, onFrame: @escaping (CFTimeInterval) -> Void) {
    startCount += 1
    self.onFrame = onFrame
  }

  func retarget(displayID: CGDirectDisplayID) {
    log.record(.retarget(displayID))
  }

  func stop() {
    stopCount += 1
  }

  /// 送一幀，`timestamp` 為單調遞增絕對時間戳（對應 production 的
  /// `CACurrentMediaTime()`），非幀間隔。
  func emit(at timestamp: CFTimeInterval) {
    onFrame?(timestamp)
  }
}

/// 實作 `CursorLocatorDeadlineScheduling`。以 `schedule(delay:callback:)`
/// 綁定實例方法作為要注入的 closure，型別與 `CursorLocatorDeadlineScheduling`
/// 完全相符。
final class ManualDeadlineScheduler {
  private(set) var scheduledDelays: [TimeInterval] = []
  private(set) var cancelCount = 0
  private var pendingCallback: (() -> Void)?

  func schedule(delay: TimeInterval, callback: @escaping () -> Void) -> () -> Void {
    scheduledDelays.append(delay)
    pendingCallback = callback

    var isCancelled = false
    return { [weak self] in
      guard !isCancelled else { return }
      isCancelled = true
      self?.cancelCount += 1
      self?.pendingCallback = nil
    }
  }

  /// 手動觸發最後一筆已排程的回呼；若已被取消則為 no-op。
  func fire() {
    pendingCallback?()
  }
}

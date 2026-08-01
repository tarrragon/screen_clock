import Cocoa
import QuartzCore

/// 特效層目標螢幕判定與視窗生命週期。
///
/// 對應規格：SPEC-008 FR-02（目標螢幕判定與跨螢幕跟隨）、UC-06 主成功步驟
/// 2/3/5、替代場景 06a/06b、例外 EX-06-02/EX-06-03。
///
/// 螢幕判定部分（子票 1.4.0-W2-006.1）交付「決定在哪播」的純資料運算：值型別
/// 快照、判定結果型別、單一靜態判定函式。
///
/// 控制器狀態機部分（子票 1.4.0-W2-006.2.1）交付播放/重置/每幀跟隨/停止的
/// 生命週期邏輯，四個外部依賴（螢幕快照、游標取樣、surface 建立、逾時排程）
/// 一律經建構子注入，本檔不建立 production 的 surface 與 driver 實作、不碰
/// `MainFlutterWindow.swift`、不建立錯誤對應檔——三者屬子票 1.4.0-W2-006.2.2。
///
/// 本檔刻意只依賴 AppKit／QuartzCore，不引入任何 Flutter 型別：混入 Flutter
/// 型別會使本檔的生命週期測試群組被迫連帶引入 Flutter 依賴，違反測試獨立
/// 執行的設計前提（母票 Phase 3a §一「落點與理由」）。

/// 一次判定所需的螢幕幾何快照。
///
/// 播放期間每幀重新建構，顯示器熱插拔因此即時反映，不需另訂閱
/// `didChangeScreenParametersNotification`。
struct CursorScreenSnapshot: Equatable {
  struct Entry: Equatable {
    /// 全域座標（AppKit 左下原點，y 軸向上為正）。
    ///
    /// 第二螢幕位於主螢幕左方時 x 為負、位於下方時 y 為負；
    /// 位於上方時 y 為正。判定不得假設非負。
    let frame: NSRect

    /// 供 frame driver 綁定螢幕更新率用（SPEC-008 FR-03）。子票 .1 不使用此欄位。
    let displayID: CGDirectDisplayID
  }

  /// 依 `NSScreen.screens` 原始順序；命中取「第一個」依賴此順序。
  let entries: [Entry]

  /// `NSScreen.main` 在 `entries` 中的索引；取不到 main 時為 nil。
  /// `entries` 為空時必為 nil。
  let mainIndex: Int?
}

/// 螢幕判定結果。
///
/// 以型別區分三條語意不同的路徑，呼叫端無須再比對回傳值即可決定是否記
/// `E_CL_SCREEN`、是否可播放。`index` 為 `CursorScreenSnapshot.entries` 的索引。
enum CursorScreenResolution: Equatable {
  /// 找到 frame 涵蓋游標的螢幕（SPEC-008 FR-02 正常路徑）。
  case matched(index: Int)

  /// 無涵蓋螢幕，退回 main（EX-06-02 復原路徑，呼叫端須記 `E_CL_SCREEN`）。
  case fellBackToMain(index: Int)

  /// 連 main 都取不到（無可用螢幕）。呼叫端視為不可播放。
  case unavailable
}

/// 目標螢幕判定單元。
enum CursorScreenLocator {
  /// 純函式：不讀取任何全域狀態（不接觸 `NSScreen` / `NSEvent`），
  /// 輸出只由 `cursorLocation` 與 `snapshot` 兩個參數決定。取樣責任在呼叫端。
  ///
  /// 判定邏輯：
  /// 1. 依 `entries` 索引由小至大依序檢查，取「第一個」frame 以半開區間
  ///    （`minX <= x < maxX`、`minY <= y < maxY`）涵蓋 `cursorLocation` 的螢幕，
  ///    回傳 `.matched(index:)`；多個 entry 重疊時同樣取索引最小者，不做
  ///    面積或距離仲裁。
  /// 2. 無涵蓋者時，若 `mainIndex` 存在則退回該索引，回傳 `.fellBackToMain(index:)`。
  /// 3. 無涵蓋者且 `mainIndex` 為 nil（含 `entries` 為空）時回傳 `.unavailable`。
  ///
  /// 涵蓋判定直接使用 `NSRect.contains(_:)` 的半開區間語意，不自行以四則
  /// 運算重寫比較式——自行重寫是邊界歸屬出錯的主要來源。
  static func resolve(
    cursorLocation: NSPoint,
    in snapshot: CursorScreenSnapshot
  ) -> CursorScreenResolution {
    for (index, entry) in snapshot.entries.enumerated() {
      if entry.frame.contains(cursorLocation) {
        return .matched(index: index)
      }
    }

    if let mainIndex = snapshot.mainIndex {
      return .fellBackToMain(index: mainIndex)
    }

    return .unavailable
  }
}

// MARK: - 特效視窗控制器（子票 1.4.0-W2-006.2.1）

/// 一次播放的請求參數。由 bridge 從 channel 參數轉換而來（子票 .2.2 職責）。
struct CursorLocatorPlayRequest: Equatable {
  let duration: TimeInterval
  let tint: NSColor
}

/// 控制器對外可觀測的播放狀態。surface 是否存活由本型別唯一表示：
/// `.idle` 等價於「無 surface」，`.playing` 等價於「恰有一個 surface」。
enum CursorLocatorPlaybackState: Equatable {
  case idle

  /// `screenFrame` 為 surface 當下所在螢幕的 frame，使「判定結果是否真的被
  /// 拿去開視窗」可被斷言（母票 Phase 1.5 P0-5）。
  case playing(elapsed: TimeInterval, duration: TimeInterval, screenFrame: NSRect)
}

/// 播放失敗的錯誤型別。與 `FlutterError` 的對應屬子票 .2.2（`CursorLocatorErrorMapping.swift`）職責，
/// 本檔只負責拋出。
enum CursorLocatorError: Error, Equatable {
  /// 特效視窗建立失敗（EX-06-03）。錯誤碼字面 `E_CL_WINDOW`。
  case windowCreationFailed(underlying: String)

  /// 無任何可用螢幕（`CursorScreenResolution.unavailable`）。錯誤碼字面 `E_CL_SCREEN`。
  case noAvailableScreen
}

/// 取得當下螢幕幾何快照。production 讀 `NSScreen.screens` / `NSScreen.main`（.2.2 職責）。
typealias CursorScreenSnapshotProviding = () -> CursorScreenSnapshot

/// 取得當下游標位置。production 讀 `NSEvent.mouseLocation`（.2.2 職責）。
typealias CursorLocationSampling = () -> NSPoint

/// 建立 surface。production 實作建立 `NSWindow` 並套用視窗屬性契約（.2.2 職責）；
/// 建立失敗時 throw，觸發 `E_CL_WINDOW` 路徑。
typealias CursorLocatorSurfaceMaking = (NSRect) throws -> CursorLocatorSurface

/// 逾時保險：安排一次性回呼，回傳取消用的 closure。
/// production 為 `DispatchQueue.main.asyncAfter`（.2.2 職責），測試為手動觸發樁。
typealias CursorLocatorDeadlineScheduling =
  (TimeInterval, @escaping () -> Void) -> () -> Void

/// 特效視窗的最小抽象。隔開 AppKit 視窗伺服器，使生命週期可在無視窗環境下測。
protocol CursorLocatorSurface: AnyObject {
  /// renderer 繪製的目標圖層。renderer 只碰這一層（renderer 本身屬 1.4.0-W3-001）。
  var contentLayer: CALayer { get }

  func move(toScreenFrame frame: NSRect)

  /// 整個視窗的不透明度（production 對應 `NSWindow.alphaValue`，非圖層屬性）。
  func setAlpha(_ value: CGFloat)

  func close()
}

/// 逐幀驅動。production 以 CVDisplayLink 實作（.2.2 職責），綁定指定 displayID
/// 以對齊該螢幕更新率（SPEC-008 FR-03）。測試以手動 driver 推進時間，不使用
/// wall clock、不使用 expectation 等待。
protocol CursorLocatorFrameDriving: AnyObject {
  /// `onFrame` 保證於 main thread 呼叫；production 實作自行從 display link
  /// 執行緒派回，呼叫端不需知道底層是 CVDisplayLink。參數為單調遞增的絕對
  /// 時間戳（production 用 `CACurrentMediaTime()`）。
  func start(displayID: CGDirectDisplayID, onFrame: @escaping (CFTimeInterval) -> Void)

  /// 跨螢幕搬遷後重綁 `CGDirectDisplayID`。未重綁則更新率仍對齊舊螢幕，違反
  /// FR-03。播放中可多次呼叫。
  func retarget(displayID: CGDirectDisplayID)

  /// 盡力停止。返回後仍可能有一幀在途，由控制器的世代序號攔下。
  func stop()
}

/// 特效播放的計時常數。原生層自保門檻，不對使用者可見、不進 `SettingsModel`
/// （母票 Phase 1 §六）。
enum CursorLocatorTimingConstants {
  /// 淡出窗秒數上限。
  static let fadeDurationCap: TimeInterval = 0.2

  /// 淡出窗佔總時長的比例上限。
  static let fadeDurationRatio: Double = 0.4

  /// 逾時保險相對於 `duration` 的寬限秒數。
  static let deadlineMargin: TimeInterval = 0.5
}

/// 特效視窗控制器：播放/重置/每幀跨螢幕跟隨/停止的狀態機。
///
/// 對應規格：SPEC-008 FR-02、UC-06 主場景 3/4/5、替代場景 06a/06b、
/// EX-06-02、EX-06-03。四個外部依賴一律經建構子注入，測試以替身替換全部
/// 四者、`CursorScreenLocator` 用真貨（母票 Phase 2 §一 1.1 Mock 策略）。
///
/// 執行緒契約：所有公開方法與 `onFrame` 皆於 main thread 呼叫；本類別不做鎖。
final class CursorLocatorEffectController {

  private let snapshotProvider: CursorScreenSnapshotProviding
  private let locationSampler: CursorLocationSampling
  private let surfaceMaker: CursorLocatorSurfaceMaking
  private let frameDriver: CursorLocatorFrameDriving
  private let deadlineScheduler: CursorLocatorDeadlineScheduling

  private(set) var state: CursorLocatorPlaybackState = .idle

  /// 過期幀攔截用的世代序號。於「建立新 surface」與「結束子程序」時遞增，
  /// 使已停止／已結束的舊 driver 產生的在途幀在比對時被過濾。
  ///
  /// 重置（播放中再次 `play`）刻意**不**遞增此序號：driver 於重置時不重啟
  /// （只 `retarget`，不重呼 `start`），`onFrame` 閉包仍是同一個、捕捉的仍是
  /// 同一世代值；若重置也遞增，會使該閉包捕捉的世代永久落後於
  /// `self.generation`，導致重置後所有後續幀被誤判為過期而永久停止推進。
  private var generation: UInt64 = 0

  private var surface: CursorLocatorSurface?
  private var duration: TimeInterval = 0
  private var startTimestamp: CFTimeInterval?
  private var currentScreenFrame: NSRect?
  private var currentDisplayID: CGDirectDisplayID?
  private var cancelDeadline: (() -> Void)?

  init(
    snapshotProvider: @escaping CursorScreenSnapshotProviding,
    locationSampler: @escaping CursorLocationSampling,
    surfaceMaker: @escaping CursorLocatorSurfaceMaking,
    frameDriver: CursorLocatorFrameDriving,
    deadlineScheduler: @escaping CursorLocatorDeadlineScheduling
  ) {
    self.snapshotProvider = snapshotProvider
    self.locationSampler = locationSampler
    self.surfaceMaker = surfaceMaker
    self.frameDriver = frameDriver
    self.deadlineScheduler = deadlineScheduler
  }

  /// 觸發或重置播放。
  ///
  /// - `.idle` 時建立 surface 並開始播放。
  /// - `.playing` 時「重置」既有 surface：elapsed 起點清除、tint/duration
  ///   換為新請求、alpha 復位為 1、必要時搬遷至新目標螢幕；不建立第二個
  ///   surface（UC-06 替代場景 06b）。
  /// - 無任何可用螢幕時拋出 `.noAvailableScreen`，不建立 surface、不啟動
  ///   驅動、不排程逾時。
  /// - surface 建立失敗時拋出 `.windowCreationFailed`；此路徑結束後狀態
  ///   仍為 `.idle`，且無殘留的排程與驅動。
  func play(_ request: CursorLocatorPlayRequest) throws {
    let snapshot = snapshotProvider()
    let cursorLocation = locationSampler()
    let resolution = CursorScreenLocator.resolve(cursorLocation: cursorLocation, in: snapshot)

    let targetIndex: Int
    switch resolution {
    case .matched(let index):
      targetIndex = index
    case .fellBackToMain(let index):
      NSLog("[cursor-locator] E_CL_SCREEN: 螢幕解析退回 main，續行播放")
      targetIndex = index
    case .unavailable:
      NSLog("[cursor-locator] E_CL_SCREEN: 無任何可用螢幕，無法播放")
      throw CursorLocatorError.noAvailableScreen
    }

    let targetEntry = snapshot.entries[targetIndex]

    if case .playing = state {
      resetExistingPlayback(request: request, targetEntry: targetEntry)
      return
    }

    try startNewPlayback(request: request, targetEntry: targetEntry)
  }

  /// 立即結束播放並釋放 surface（app 結束或測試 teardown 用）。
  /// `.idle` 時為 no-op，不 throw。
  func stop() {
    guard case .playing = state else { return }
    endPlayback()
  }

  private func startNewPlayback(
    request: CursorLocatorPlayRequest,
    targetEntry: CursorScreenSnapshot.Entry
  ) throws {
    let newSurface: CursorLocatorSurface
    do {
      newSurface = try surfaceMaker(targetEntry.frame)
    } catch {
      NSLog("[cursor-locator] E_CL_WINDOW: 特效視窗建立失敗: \(error)")
      throw CursorLocatorError.windowCreationFailed(underlying: String(describing: error))
    }

    surface = newSurface
    duration = request.duration
    startTimestamp = nil
    currentScreenFrame = targetEntry.frame
    currentDisplayID = targetEntry.displayID
    generation += 1
    let capturedGeneration = generation

    frameDriver.start(displayID: targetEntry.displayID) { [weak self] timestamp in
      self?.handleFrame(timestamp: timestamp, generation: capturedGeneration)
    }

    cancelDeadline = deadlineScheduler(
      request.duration + CursorLocatorTimingConstants.deadlineMargin
    ) { [weak self] in
      self?.handleDeadline(generation: capturedGeneration)
    }

    state = .playing(elapsed: 0, duration: request.duration, screenFrame: targetEntry.frame)
  }

  private func resetExistingPlayback(
    request: CursorLocatorPlayRequest,
    targetEntry: CursorScreenSnapshot.Entry
  ) {
    duration = request.duration
    startTimestamp = nil

    if targetEntry.frame != currentScreenFrame {
      surface?.move(toScreenFrame: targetEntry.frame)
      frameDriver.retarget(displayID: targetEntry.displayID)
      currentScreenFrame = targetEntry.frame
      currentDisplayID = targetEntry.displayID
    }

    surface?.setAlpha(1.0)

    cancelDeadline?()
    let capturedGeneration = generation
    cancelDeadline = deadlineScheduler(
      request.duration + CursorLocatorTimingConstants.deadlineMargin
    ) { [weak self] in
      self?.handleDeadline(generation: capturedGeneration)
    }

    state = .playing(elapsed: 0, duration: request.duration, screenFrame: targetEntry.frame)
  }

  /// 每幀行為（母票 Phase 1 §2.8 五步）：世代攔截 -> 重判定螢幕 -> 計算
  /// elapsed -> 淡出窗內設定 alpha -> elapsed 達 duration 即走結束子程序。
  private func handleFrame(timestamp: CFTimeInterval, generation frameGeneration: UInt64) {
    guard frameGeneration == generation else { return }
    guard case .playing(_, let currentDuration, _) = state else { return }

    let snapshot = snapshotProvider()
    let cursorLocation = locationSampler()
    let resolution = CursorScreenLocator.resolve(cursorLocation: cursorLocation, in: snapshot)

    switch resolution {
    case .unavailable:
      NSLog("[cursor-locator] E_CL_SCREEN: 播放中螢幕數歸零，結束播放")
      endPlayback()
      return
    case .matched(let index):
      updateTargetScreenIfNeeded(snapshot.entries[index])
    case .fellBackToMain(let index):
      NSLog("[cursor-locator] E_CL_SCREEN: 播放中退回 main，續行播放")
      updateTargetScreenIfNeeded(snapshot.entries[index])
    }

    if startTimestamp == nil {
      startTimestamp = timestamp
    }
    guard let start = startTimestamp else { return }
    let elapsed = timestamp - start

    let fadeDuration = min(
      CursorLocatorTimingConstants.fadeDurationCap,
      currentDuration * CursorLocatorTimingConstants.fadeDurationRatio
    )
    let fadeStart = currentDuration - fadeDuration
    if fadeDuration > 0 && elapsed >= fadeStart {
      let remaining = currentDuration - elapsed
      let alpha = max(0, min(1, remaining / fadeDuration))
      surface?.setAlpha(alpha)
    }

    if elapsed >= currentDuration {
      endPlayback()
      return
    }

    state = .playing(
      elapsed: elapsed,
      duration: currentDuration,
      screenFrame: currentScreenFrame ?? targetFallbackFrame(from: snapshot)
    )
  }

  private func targetFallbackFrame(from snapshot: CursorScreenSnapshot) -> NSRect {
    guard let mainIndex = snapshot.mainIndex, snapshot.entries.indices.contains(mainIndex) else {
      return .zero
    }
    return snapshot.entries[mainIndex].frame
  }

  private func updateTargetScreenIfNeeded(_ entry: CursorScreenSnapshot.Entry) {
    guard entry.frame != currentScreenFrame else { return }
    surface?.move(toScreenFrame: entry.frame)
    frameDriver.retarget(displayID: entry.displayID)
    currentScreenFrame = entry.frame
    currentDisplayID = entry.displayID
  }

  private func handleDeadline(generation deadlineGeneration: UInt64) {
    guard deadlineGeneration == generation else { return }
    guard case .playing = state else { return }
    NSLog("[cursor-locator] 逾時保險觸發，強制結束播放")
    endPlayback()
  }

  /// 結束子程序（單一出口，供自然結束 / 螢幕歸零 / 逾時 / 主動停止四條路徑
  /// 共用）：停驅動 -> 取消逾時 -> 關閉 surface -> 釋放持有 -> 狀態設為
  /// 閒置 -> 遞增世代序號。
  ///
  /// 四條結束路徑共用同一子程序，是「十次觸發無洩漏」在所有路徑上一致成立
  /// 的結構前提；若各路徑各自收尾，必有某條路徑漏掉其中一步。
  private func endPlayback() {
    frameDriver.stop()
    cancelDeadline?()
    cancelDeadline = nil
    surface?.close()
    surface = nil
    startTimestamp = nil
    currentScreenFrame = nil
    currentDisplayID = nil
    state = .idle
    generation += 1
  }
}

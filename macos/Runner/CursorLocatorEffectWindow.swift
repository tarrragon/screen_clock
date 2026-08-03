import Cocoa
import CoreVideo
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

  /// 特效顏色（SPEC-008 FR-06 主色調，經 channel 以 ARGB int 傳入）。
  ///
  /// 控制器於播放開始時交給 renderer（`attach(to:tint:duration:)`），並逐幀
  /// 組進 `CursorLocatorEffectFrame` 一併交付；實際著色由 renderer 實作負責
  /// （聚光燈／邊框閃爍／波紋分屬子票 `1.4.0-W3-001.2`／`.3`／`.4`）。
  let tint: NSColor
}

/// 控制器對外可觀測的播放狀態。`.idle` 表示無 surface，`.playing` 表示恰有
/// 一個 surface。本型別為投影值、不持有 surface；產生它的控制器負責維持
/// 兩者一致。
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

/// 特效繪製數值的單一集中處（子票 `1.4.0-W3-001.1`）。
///
/// 與 `CursorLocatorTimingConstants` 的分界：後者是視窗生命週期的原生自保
/// 門檻（淡出窗、逾時寬限），不對使用者可見也不來自 SPEC-008 的視覺約束；
/// 本列舉則收納「畫出來會被看到」的規格數值。三張特效子票
/// （`1.4.0-W3-001.2` 聚光燈、`.3` 邊框閃爍、`.4` 波紋）的半徑、寬度、週期
/// 一律新增於此，不得散落於各自的 renderer 實作內。
enum CursorLocatorEffectConstants {
  /// normalized progress 的下界。
  static let progressLowerBound: Double = 0

  /// normalized progress 的上界。播放自然結束該幀的 progress 即為此值。
  static let progressUpperBound: Double = 1

  /// 聚光燈壓暗層的不透明度（SPEC-008 FR-03 上限 55%，取用上限值以達成
  /// 「目標螢幕明顯變暗」的驗收標準）。
  static let spotlightDimOpacity: Double = 0.55

  /// 聚光燈亮區半徑（點，SPEC-008 FR-03 指定 120 px）。此半徑內完全不壓暗。
  static let spotlightBrightRadius: CGFloat = 120

  /// 亮區邊緣的羽化帶寬度（點）。自 `spotlightBrightRadius` 起往外，壓暗度由
  /// 0 漸增到滿值；沒有這段寬度時邊緣為鋸齒硬邊，違反 FR-03。
  static let spotlightEdgeFeather: CGFloat = 40

  /// 亮區加羽化帶的總半徑，即壓暗完全生效的距離。
  static let spotlightOuterRadius: CGFloat = spotlightBrightRadius + spotlightEdgeFeather

  /// 亮區邊界在漸層中的位置比例（0 為圓心、1 為 `spotlightOuterRadius`）。
  static let spotlightBrightStopRatio: Double =
    Double(spotlightBrightRadius / spotlightOuterRadius)
}

/// 單一幀交付給 renderer 的全部資訊。
///
/// 三種特效共用同一份實例：`cursorPointInLayer` 每幀只取樣一次（FR-03
/// 「圓心更新以 CVDisplayLink 對齊螢幕更新率取樣 `NSEvent.mouseLocation`」、
/// FR-05「與 FR-03 共用同一組游標位置取樣」）。若各 renderer 自行呼叫
/// `NSEvent.mouseLocation`，兩次取樣之間游標可能已移動，聚光燈亮區與波紋
/// 圓心會在快速移動時偶發可見偏移。
struct CursorLocatorEffectFrame: Equatable {
  /// 0..1 的播放進度，由 CVDisplayLink 時間戳推導（非牆鐘）。
  let progress: Double

  /// 自首幀起算的秒數；需要絕對時間軸的特效（如 FR-04 三次 200 ms 週期、
  /// FR-05 三圈 150 ms 間隔）用此值，不必自行還原 `progress * duration`。
  let elapsed: TimeInterval

  /// 本次播放的總時長（SPEC-008 FR-06 設定值，含淡出）。
  let duration: TimeInterval

  /// 游標於 `contentLayer` 座標系的位置（左下原點，y 軸向上為正）。
  let cursorPointInLayer: CGPoint

  /// 使用者設定的主色調（FR-06）。
  let tint: NSColor
}

/// 特效繪製單元。控制器只認得本協定，不認得任何具體特效。
///
/// 生命週期：`attach` -> 每幀 `render` -> `detach`。播放中再次觸發（重置）
/// 會重新 `attach`：時長與主色調可能已隨設定變更，重置等同換一組參數重播。
protocol CursorLocatorEffectRendering: AnyObject {
  /// 綁定繪製目標並接收本次播放的參數。`layer` 的幾何、`contentsScale` 與
  /// 隱含動畫停用已由 `LayerHostingView` 處理（子票 `1.4.0-W3-018`），
  /// 實作不需重複處理。
  func attach(to layer: CALayer, tint: NSColor, duration: TimeInterval)

  /// 逐幀更新。呼叫於 main thread。
  func render(_ frame: CursorLocatorEffectFrame)

  /// 播放結束（自然結束／螢幕歸零／逾時／主動停止四條路徑共用），移除自己
  /// 加到 `layer` 上的一切。
  func detach()
}

/// 把一次播放廣播給多個 renderer。
///
/// 三種特效各自獨立成一個 renderer 而非合寫一支，使
/// `1.4.0-W3-001.2`／`.3`／`.4` 可分別交付、分別測試；本型別是它們的接線點。
final class CursorLocatorCompositeRenderer: CursorLocatorEffectRendering {
  private let renderers: [CursorLocatorEffectRendering]

  /// production 目前傳入空陣列：本子票只建時間軸與取樣基礎，不繪製任何可見
  /// 內容。三張特效子票各自把自己的 renderer 加進 `MainFlutterWindow.swift`
  /// 的接線處。
  init(renderers: [CursorLocatorEffectRendering]) {
    self.renderers = renderers
  }

  func attach(to layer: CALayer, tint: NSColor, duration: TimeInterval) {
    renderers.forEach { $0.attach(to: layer, tint: tint, duration: duration) }
  }

  func render(_ frame: CursorLocatorEffectFrame) {
    renderers.forEach { $0.render(frame) }
  }

  func detach() {
    renderers.forEach { $0.detach() }
  }
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

  /// 繪製層。`nil` 表示只跑生命週期不繪製（既有生命週期測試群組即為此形態）。
  private let renderer: CursorLocatorEffectRendering?

  /// playing 期間持有的全部狀態（`generation` 除外，理由見其註解）。`surface`
  /// 為 non-optional，故此結構存在即等價於「恰有一個 surface」，不存在需並行
  /// 維護的第二份欄位。`duration`／`elapsed`／`screenFrame` 為 `state` 的計算
  /// 來源，不另存一份。
  private struct PlayingSession {
    let surface: CursorLocatorSurface
    var duration: TimeInterval
    var elapsed: TimeInterval
    var startTimestamp: CFTimeInterval?
    var screenFrame: NSRect
    var cancelDeadline: () -> Void

    /// 本次播放的主色調。與 `duration` 同樣可在重置時換新，故隨 session 走
    /// 而非隨控制器；逐幀組進 `CursorLocatorEffectFrame` 交付 renderer。
    var tint: NSColor
  }

  private var session: PlayingSession?

  /// 由 `session` 推導：`session == nil` 即 `.idle`，否則以 session 當下的
  /// elapsed／duration／screenFrame 組出 `.playing`。因此
  /// `CursorLocatorPlaybackState` 的不變式不需額外一致性檢查即成立。
  var state: CursorLocatorPlaybackState {
    guard let session = session else { return .idle }
    return .playing(elapsed: session.elapsed, duration: session.duration, screenFrame: session.screenFrame)
  }

  /// 過期幀攔截用的世代序號。於「建立新 surface」與「結束子程序」時遞增，
  /// 使已停止／已結束的舊 driver 產生的在途幀在比對時被過濾。
  ///
  /// 重置（播放中再次 `play`）刻意**不**遞增此序號：driver 於重置時不重啟
  /// （只 `retarget`，不重呼 `start`），`onFrame` 閉包仍是同一個、捕捉的仍是
  /// 同一世代值；若重置也遞增，會使該閉包捕捉的世代永久落後於
  /// `self.generation`，導致重置後所有後續幀被誤判為過期而永久停止推進。
  ///
  /// 獨立於 `session` 之外持有（不隨 playing/idle 收放）：世代比對在取出
  /// `session` 之前執行，且 idle 期間仍須保有最後世代值供已捕捉舊世代值的
  /// 在途幀比對，故不可隨 `session` 收放。
  private var generation: UInt64 = 0

  init(
    snapshotProvider: @escaping CursorScreenSnapshotProviding,
    locationSampler: @escaping CursorLocationSampling,
    surfaceMaker: @escaping CursorLocatorSurfaceMaking,
    frameDriver: CursorLocatorFrameDriving,
    deadlineScheduler: @escaping CursorLocatorDeadlineScheduling,
    renderer: CursorLocatorEffectRendering? = nil
  ) {
    self.renderer = renderer
    self.snapshotProvider = snapshotProvider
    self.locationSampler = locationSampler
    self.surfaceMaker = surfaceMaker
    self.frameDriver = frameDriver
    self.deadlineScheduler = deadlineScheduler
  }

  /// 觸發或重置播放。
  ///
  /// - `.idle` 時建立 surface 並開始播放。
  /// - `.playing` 時「重置」既有 surface：elapsed 起點清除、duration 換為
  ///   新請求、alpha 復位為 1、必要時搬遷至新目標螢幕；不建立第二個
  ///   surface（UC-06 替代場景 06b）；renderer 重新 `attach`，時長與主色調
  ///   換為新請求的值。
  /// - 無任何可用螢幕時拋出 `.noAvailableScreen`，不建立 surface、不啟動
  ///   驅動、不排程逾時。
  /// - surface 建立失敗時拋出 `.windowCreationFailed`；此路徑結束後狀態
  ///   仍為 `.idle`，且無殘留的排程與驅動。
  func play(_ request: CursorLocatorPlayRequest) throws {
    let target = resolveTarget()

    let targetIndex: Int
    switch target.resolution {
    case .matched(let index):
      targetIndex = index
    case .fellBackToMain(let index):
      NSLog("[cursor-locator] E_CL_SCREEN: 螢幕解析退回 main，續行播放")
      targetIndex = index
    case .unavailable:
      NSLog("[cursor-locator] E_CL_SCREEN: 無任何可用螢幕，無法播放")
      throw CursorLocatorError.noAvailableScreen
    }

    let targetEntry = target.snapshot.entries[targetIndex]

    if var currentSession = session {
      resetExistingPlayback(&currentSession, request: request, targetEntry: targetEntry)
      session = currentSession
      return
    }

    try startNewPlayback(request: request, targetEntry: targetEntry)
  }

  /// 立即結束播放並釋放 surface（app 結束或測試 teardown 用）。
  /// `.idle` 時為 no-op，不 throw。
  func stop() {
    guard session != nil else { return }
    endPlayback()
  }

  /// 一次判定所依據的三項值：快照、該次取樣到的游標位置、判定結果。
  ///
  /// 游標位置一併回傳而非只留在函式內，是為了讓每幀的螢幕判定與特效繪製
  /// 共用同一次 `NSEvent.mouseLocation` 取樣（FR-03／FR-05 共用取樣約束）。
  private struct TargetResolution {
    let snapshot: CursorScreenSnapshot
    let cursorLocation: NSPoint
    let resolution: CursorScreenResolution
  }

  /// 取當下螢幕快照與游標對應的判定結果。
  ///
  /// 由 `play` 與 `handleFrame` 共用；switch 分支與對應診斷 log 留在各自
  /// 呼叫端組裝，因為不同呼叫情境（觸發播放 / 播放中每幀）對同一判定結果
  /// 需要不同的處理與措辭，寫在此處會讓被呼叫者記住呼叫者的用詞，任一方
  /// 改動都需回頭同步。
  private func resolveTarget() -> TargetResolution {
    let snapshot = snapshotProvider()
    let cursorLocation = locationSampler()
    let resolution = CursorScreenLocator.resolve(cursorLocation: cursorLocation, in: snapshot)
    return TargetResolution(
      snapshot: snapshot, cursorLocation: cursorLocation, resolution: resolution)
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

    generation += 1
    let capturedGeneration = generation

    let cancelDeadline = scheduleDeadline(duration: request.duration, generation: capturedGeneration)

    let newSession = PlayingSession(
      surface: newSurface,
      duration: request.duration,
      elapsed: 0,
      startTimestamp: nil,
      screenFrame: targetEntry.frame,
      cancelDeadline: cancelDeadline,
      tint: request.tint
    )

    renderer?.attach(
      to: newSurface.contentLayer, tint: request.tint, duration: request.duration)

    frameDriver.start(displayID: targetEntry.displayID) { [weak self] timestamp in
      self?.handleFrame(timestamp: timestamp, generation: capturedGeneration)
    }

    session = newSession
  }

  private func resetExistingPlayback(
    _ currentSession: inout PlayingSession,
    request: CursorLocatorPlayRequest,
    targetEntry: CursorScreenSnapshot.Entry
  ) {
    currentSession.duration = request.duration
    currentSession.elapsed = 0
    currentSession.startTimestamp = nil
    currentSession.tint = request.tint

    updateTargetScreenIfNeeded(targetEntry, session: &currentSession)

    currentSession.surface.setAlpha(1.0)

    renderer?.attach(
      to: currentSession.surface.contentLayer,
      tint: request.tint,
      duration: request.duration
    )

    currentSession.cancelDeadline()
    currentSession.cancelDeadline = scheduleDeadline(duration: request.duration, generation: generation)
  }

  /// 排程一次逾時保險，回傳取消用的 closure。
  ///
  /// 世代由參數傳入而非讀取 `self.generation`：是否遞增、遞增後或現有值，
  /// 完全由呼叫端決定，本函式只負責排程與取消 closure 的組裝，不涉入世代
  /// 遞增的判斷。
  private func scheduleDeadline(duration: TimeInterval, generation: UInt64) -> () -> Void {
    deadlineScheduler(
      duration + CursorLocatorTimingConstants.deadlineMargin
    ) { [weak self] in
      self?.handleDeadline(generation: generation)
    }
  }

  /// 每幀行為（母票 Phase 1 §2.8 五步 + 子票 `1.4.0-W3-001.1` 的繪製交付）：
  /// 世代攔截 -> 重判定螢幕（同時取得該幀游標取樣）-> 計算 elapsed ->
  /// 淡出窗內設定 alpha -> 交付繪製層 -> elapsed 達 duration 即走結束子程序。
  private func handleFrame(timestamp: CFTimeInterval, generation frameGeneration: UInt64) {
    guard frameGeneration == generation else { return }
    guard var currentSession = session else { return }
    guard let cursorLocation = followCursorScreen(&currentSession) else {
      endPlayback()
      return
    }

    let start = currentSession.startTimestamp ?? timestamp
    currentSession.startTimestamp = start
    let elapsed = timestamp - start

    if let alpha = Self.fadeAlpha(elapsed: elapsed, duration: currentSession.duration) {
      currentSession.surface.setAlpha(alpha)
    }

    currentSession.elapsed = elapsed
    session = currentSession

    deliverFrame(session: currentSession, cursorLocation: cursorLocation)

    if elapsed >= currentSession.duration {
      endPlayback()
    }
  }

  /// 把該幀的進度、游標位置與播放參數交給繪製層。
  ///
  /// 游標位置由呼叫端傳入而非在此重新取樣：全幀共用單一次取樣是 FR-03 與
  /// FR-05 圓心同步的前提。
  private func deliverFrame(session: PlayingSession, cursorLocation: NSPoint) {
    guard let renderer = renderer else { return }

    renderer.render(
      CursorLocatorEffectFrame(
        progress: Self.normalizedProgress(
          elapsed: session.elapsed, duration: session.duration),
        elapsed: session.elapsed,
        duration: session.duration,
        cursorPointInLayer: Self.layerPoint(
          forCursorLocation: cursorLocation, screenFrame: session.screenFrame),
        tint: session.tint
      )
    )
  }

  /// 每幀螢幕重判定：回傳該幀取樣到的游標位置，`nil` 表示已無可用螢幕。
  /// 不做任何終結性副作用（無可用螢幕時是否結束播放由呼叫端決定）。回傳
  /// 非 `nil` 時已視需要將 surface 搬遷至判定結果對應的螢幕。
  private func followCursorScreen(_ currentSession: inout PlayingSession) -> NSPoint? {
    let target = resolveTarget()

    switch target.resolution {
    case .unavailable:
      NSLog("[cursor-locator] E_CL_SCREEN: 播放中螢幕數歸零，結束播放")
      return nil
    case .matched(let index):
      updateTargetScreenIfNeeded(target.snapshot.entries[index], session: &currentSession)
      return target.cursorLocation
    case .fellBackToMain(let index):
      NSLog("[cursor-locator] E_CL_SCREEN: 播放中退回 main，續行播放")
      updateTargetScreenIfNeeded(target.snapshot.entries[index], session: &currentSession)
      return target.cursorLocation
    }
  }

  /// 0..1 的 normalized progress，純函式、無副作用。
  ///
  /// `elapsed` 由 CVDisplayLink 送來的單調時間戳相減而得（見 `handleFrame`），
  /// 故進度推進對齊螢幕更新率而非牆鐘；分母為本次播放的 `duration`
  /// （SPEC-008 FR-06 使用者設定值）。
  ///
  /// `duration <= 0` 時視為已播畢，回傳上界：非正時長無可分割的區間，回傳
  /// 下界會讓特效停在起始狀態直到逾時保險介入。逾時保險或在途幀可能送來
  /// 超過 `duration` 的 `elapsed`，一律夾到上界。
  ///
  /// 宣告為 `internal`（非 `private`）僅為讓 RunnerTests 透過 `@testable
  /// import` 直接呼叫，不代表對外公開 API。
  static func normalizedProgress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0 else { return CursorLocatorEffectConstants.progressUpperBound }
    return min(
      CursorLocatorEffectConstants.progressUpperBound,
      max(CursorLocatorEffectConstants.progressLowerBound, elapsed / duration)
    )
  }

  /// 全域游標座標轉 `contentLayer` 座標，純函式、無副作用。
  ///
  /// 特效視窗的 frame 恆等於目標螢幕 frame，其 `contentLayer` 原點對齊視窗
  /// 左下角，故僅需減去螢幕原點。兩者皆為 AppKit 左下原點、y 軸向上為正，
  /// 不需翻轉 y。
  ///
  /// 宣告為 `internal` 的理由同 `normalizedProgress`。
  static func layerPoint(forCursorLocation location: NSPoint, screenFrame: NSRect) -> CGPoint {
    CGPoint(x: location.x - screenFrame.minX, y: location.y - screenFrame.minY)
  }

  private func updateTargetScreenIfNeeded(
    _ entry: CursorScreenSnapshot.Entry,
    session: inout PlayingSession
  ) {
    guard entry.frame != session.screenFrame else { return }
    session.surface.move(toScreenFrame: entry.frame)
    frameDriver.retarget(displayID: entry.displayID)
    session.screenFrame = entry.frame
  }

  /// 淡出窗內的 alpha 值計算，純函式、無副作用（SPEC-008 FR-02 播放結束前
  /// 的淡出視覺效果）。
  ///
  /// `duration <= 0` 或 `elapsed` 尚未進入淡出窗時回傳 `nil`，呼叫端不設定
  /// alpha（維持既有值，通常為 1.0）。淡出窗定義：`min(fadeDurationCap,
  /// duration * fadeDurationRatio)` 秒，於 `duration` 結束前展開。
  ///
  /// 宣告為 `internal`（非 `private`）僅為讓 RunnerTests 透過 `@testable
  /// import` 直接呼叫，不代表對外公開 API。
  static func fadeAlpha(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat? {
    let fadeDuration = min(
      CursorLocatorTimingConstants.fadeDurationCap,
      duration * CursorLocatorTimingConstants.fadeDurationRatio
    )
    let fadeStart = duration - fadeDuration
    guard fadeDuration > 0 && elapsed >= fadeStart else { return nil }

    let remaining = duration - elapsed
    return max(0, min(1, remaining / fadeDuration))
  }

  private func handleDeadline(generation deadlineGeneration: UInt64) {
    guard deadlineGeneration == generation else { return }
    guard session != nil else { return }
    NSLog("[cursor-locator] 逾時保險觸發，強制結束播放")
    endPlayback()
  }

  /// 結束子程序（單一出口，供自然結束 / 螢幕歸零 / 逾時 / 主動停止四條路徑
  /// 共用）：停驅動 -> 卸下繪製層 -> 取消逾時 -> 關閉 surface -> 釋放持有 ->
  /// 遞增世代序號。
  ///
  /// 四條結束路徑共用同一子程序，是「十次觸發無洩漏」在所有路徑上一致成立
  /// 的結構前提；若各路徑各自收尾，必有某條路徑漏掉其中一步。
  private func endPlayback() {
    frameDriver.stop()
    renderer?.detach()
    if let currentSession = session {
      currentSession.cancelDeadline()
      currentSession.surface.close()
    }
    session = nil
    generation += 1
  }
}

// MARK: - Production 接線（子票 1.4.0-W2-006.2.2）

/// production 特效視窗：覆寫 `canBecomeKey` 回傳 `false`，使 §2.5 契約「不搶
/// 焦點」在型別層級成立，不依賴呼叫端記得用 `orderFrontRegardless()`。
private final class NonKeyEffectWindow: NSWindow {
  override var canBecomeKey: Bool { false }
}

/// layer-hosted 承載視圖（子票 1.4.0-W3-018）。
///
/// `WindowCursorLocatorSurface` 自建 `contentLayer` 並指派給本視圖，使其成為
/// layer-hosted view。該模式消除了孤兒圖層，代價是 AppKit 不再視此 layer 為
/// 自己的產物，layer-backed 時代兩項自動行為隨之換走：
///
/// | 行為 | layer-backed | layer-hosted |
/// |------|-------------|-------------|
/// | resize 時 layer 幾何跟隨 view bounds | AppKit 自動 | 契約上由呼叫端負責 |
/// | contentsScale 對齊 backingScaleFactor | AppKit 自動 | 不設定，預設 1.0 |
///
/// 第一項在現行 macOS 上實測仍會跟隨（AppKit 由 view 幾何推導 hosted layer 的
/// bounds/position），但那是未見於文件的實作細節，不宜當契約倚賴；本視圖仍在
/// `setFrameSize` 顯式同步，使幾何正確與 AppKit 版本無關。第二項則確實不再發生：
/// 未同步時 Retina 上實際渲染解析度減半，畫面模糊而無錯誤無日誌。
///
/// 同步一律包在停用隱含動畫的 `CATransaction` 內：hosted layer 的 `delegate`
/// 為 nil，不像 layer-backed 那樣由 AppKit 回傳 `NSNull` 停用 action，直接改
/// frame 會啟動 0.25 秒隱含動畫，使搬遷期間圖層仍畫在舊位置。
private final class LayerHostingView: NSView {
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    synchronizeHostedLayer()
  }

  /// 視窗搬到不同 `backingScaleFactor` 的螢幕時由 AppKit 呼叫。
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    synchronizeHostedLayer()
  }

  /// 讓 hosted layer 的幾何與解析度重新對齊目前的視圖與視窗狀態。
  func synchronizeHostedLayer() {
    guard let hostedLayer = layer else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    hostedLayer.frame = bounds
    if let backingScaleFactor = window?.backingScaleFactor {
      hostedLayer.contentsScale = backingScaleFactor
    }
    CATransaction.commit()
  }
}

/// production 的 `CursorLocatorSurface` 實作：依 Phase 1 §2.5 十二項屬性契約
/// 建立真實 `NSWindow`。
final class WindowCursorLocatorSurface: CursorLocatorSurface {
  /// 底層真實 `NSWindow`，供 app-hosted XCTest（群組 F）直接斷言 §2.5
  /// 契約值；型別暴露為 `NSWindow`（非 `NonKeyEffectWindow`），呼叫端不需
  /// 知道 canBecomeKey 覆寫實作在子類別。
  let window: NSWindow
  private let hostView: LayerHostingView

  /// 繪製目標圖層。由本型別自建並在 `init` 掛上 `hostView`，故必然位於視窗的
  /// layer hierarchy 內；不採 `hostView.layer ?? CALayer()` 那種 fallback——
  /// 後者在 layer 為 nil 時會交出一個未接在任何視窗上的孤兒圖層，繪製全部
  /// 「成功」但畫面無輸出且無錯誤無日誌。
  let contentLayer: CALayer

  init(frame: NSRect) {
    window = NonKeyEffectWindow(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    hostView = LayerHostingView(frame: NSRect(origin: .zero, size: frame.size))
    // 先指派再開 wantsLayer，使 hostView 成為 layer-hosted view，其 `layer`
    // 即為此處持有的實例（AppKit 不會另行替換），兩者恆為同一物件。
    contentLayer = CALayer()
    contentLayer.frame = hostView.bounds
    hostView.layer = contentLayer
    hostView.wantsLayer = true

    window.contentView = hostView
    window.level = .screenSaver
    window.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    window.ignoresMouseEvents = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.alphaValue = 1.0
    window.isReleasedWhenClosed = false
    window.setFrame(frame, display: false)
    // 掛上視窗後才知道 backingScaleFactor，故 init 的對齊須留到此處；
    // 只在 CALayer 建立時設 frame 不足以涵蓋 contentsScale。
    hostView.synchronizeHostedLayer()

    // 依 §2.5「不得用 makeKeyAndOrderFront」：後者於全螢幕播放中觸發熱鍵會
    // 導致退出全螢幕，違反 UC-06 成功保證與 06d。
    window.orderFrontRegardless()
  }

  func move(toScreenFrame frame: NSRect) {
    window.setFrame(frame, display: true)
    // 同尺寸跨螢幕搬遷不會觸發 setFrameSize，而 backingScaleFactor 變更通知的
    // 送達時機由 AppKit 決定；此處顯式同步使搬遷回傳時幾何與 scale 皆已就位。
    hostView.synchronizeHostedLayer()
  }

  func setAlpha(_ value: CGFloat) {
    window.alphaValue = value
  }

  func close() {
    window.close()
  }
}

/// production 的 surface 工廠。NSWindow 建立本身在 AppKit 下無失敗路徑，但
/// 簽章維持 `throws` 以符合 `CursorLocatorSurfaceMaking`——失敗時應攜帶原因
/// 字串觸發 E_CL_WINDOW。
func makeProductionCursorLocatorSurface(frame: NSRect) throws -> CursorLocatorSurface {
  WindowCursorLocatorSurface(frame: frame)
}

/// production 的逐幀驅動：以 `CVDisplayLink` 實作，回呼一律派回 main thread
/// （呼叫端不需知道底層是 CVDisplayLink，Phase 1 §2.7）。
final class DisplayLinkCursorLocatorFrameDriving: CursorLocatorFrameDriving {
  private var displayLink: CVDisplayLink?
  private var onFrame: ((CFTimeInterval) -> Void)?

  func start(displayID: CGDirectDisplayID, onFrame: @escaping (CFTimeInterval) -> Void) {
    self.onFrame = onFrame

    var link: CVDisplayLink?
    let createStatus = CVDisplayLinkCreateWithCGDisplay(displayID, &link)
    guard createStatus == kCVReturnSuccess, let link = link else {
      NSLog("[cursor-locator] CVDisplayLink 建立失敗，displayID=\(displayID)，status=\(createStatus)")
      return
    }

    CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ in
      let timestamp = CACurrentMediaTime()
      DispatchQueue.main.async {
        self?.onFrame?(timestamp)
      }
      return kCVReturnSuccess
    }

    displayLink = link
    CVDisplayLinkStart(link)
  }

  func retarget(displayID: CGDirectDisplayID) {
    guard let link = displayLink else { return }
    CVDisplayLinkSetCurrentCGDisplay(link, displayID)
  }

  func stop() {
    guard let link = displayLink else { return }
    CVDisplayLinkStop(link)
    displayLink = nil
    onFrame = nil
  }
}

/// production 的逾時排程：`DispatchQueue.main.asyncAfter`。
func makeProductionCursorLocatorDeadlineScheduler() -> CursorLocatorDeadlineScheduling {
  { delay, callback in
    final class CancelFlag {
      var isCancelled = false
    }
    let flag = CancelFlag()
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard !flag.isCancelled else { return }
      callback()
    }
    return { flag.isCancelled = true }
  }
}

/// production 的螢幕幾何快照提供者：讀 `NSScreen.screens` / `NSScreen.main`。
/// 每次呼叫重新讀取，播放期間逐幀重建即涵蓋顯示器熱插拔（Phase 1 §2.8）。
func productionCursorScreenSnapshot() -> CursorScreenSnapshot {
  let screens = NSScreen.screens
  let entries = screens.map { screen -> CursorScreenSnapshot.Entry in
    let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
      .uint32Value ?? 0
    return CursorScreenSnapshot.Entry(frame: screen.frame, displayID: displayID)
  }
  let mainIndex = NSScreen.main.flatMap { main in
    screens.firstIndex { $0 === main }
  }
  return CursorScreenSnapshot(entries: entries, mainIndex: mainIndex)
}

/// production 的游標取樣：讀 `NSEvent.mouseLocation`（全域 AppKit 座標）。
func productionCursorLocation() -> NSPoint {
  NSEvent.mouseLocation
}

extension NSColor {
  /// 由 Dart 端傳入的 ARGB 整數建構顏色（`tintArgb` 參數，SPEC-008 FR-06）。
  convenience init(cursorLocatorArgb value: Int) {
    let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }
}

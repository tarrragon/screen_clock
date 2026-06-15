import ApplicationServices
import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // SPEC-001 FR-02：背景真透明。必須先讓 NSWindow 非不透明，再清掉背景色，
    // 否則 Flutter 端的 Colors.transparent 會被白底覆蓋。
    self.isOpaque = false
    self.backgroundColor = .clear
    // FlutterView backing layer 在 Flutter 3.7+ macOS 預設不透明，會自繪黑底蓋住透明 NSWindow；
    // 必須與 NSWindow 同步清背景，否則透明遮罩顯示為黑底（flutter/flutter #119132）。
    flutterViewController.backgroundColor = .clear

    // launch_at_startup 在 macOS 需手動接 channel handler（套件不自動註冊）。
    // 以 SMAppService（macOS 13+）實作開機登入項；channel 名稱與方法簽章對齊
    // launch_at_startup 套件的 macOS 實作，Dart 端無需改動。
    registerLaunchAtStartupChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // ticket 1.2.1-W2-001：偵測假全螢幕（影片/簡報/遊戲）覆蓋目標螢幕，
    // 經 method channel 通知 Dart 端讓位（隱藏時鐘）。原生視窗不動。
    self.fullscreenDetector = FullscreenCoverageDetector(
      hostWindow: self,
      messenger: flutterViewController.engine.binaryMessenger
    )
    self.fullscreenDetector?.start()

    // ticket 1.3.0-W2-001：滑鼠輸入綁定原生橋接（SPEC-007 FR-07）。
    // 提供輔助使用授權查詢 / 請求與綁定下傳骨架；本階段僅儲存綁定，
    // CGEventTap 建立留 W2-003。
    self.inputBindingBridge = InputBindingBridge(
      messenger: flutterViewController.engine.binaryMessenger
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 假全螢幕覆蓋偵測器（強參考持有，隨視窗生命週期存活）。
  private var fullscreenDetector: FullscreenCoverageDetector?

  /// 滑鼠輸入綁定原生橋接（強參考持有，隨視窗生命週期存活）。
  private var inputBindingBridge: InputBindingBridge?

  /// 接上 `launch_at_startup` method channel。
  ///
  /// 對應 Dart 端兩個方法（套件 macOS 約定）：
  /// - `launchAtStartupIsEnabled` → 回傳目前是否已設為登入啟動。
  /// - `launchAtStartupSetEnabled` → 依 `setEnabledValue` 參數註冊 / 取消登入項。
  ///
  /// 實作以 SMAppService（macOS 13+）為主；低於 13 的系統回傳安全預設（false /
  /// 不動作），確保 10.15 部署目標仍可編譯。
  private func registerLaunchAtStartupChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(Self.isLaunchAtStartupEnabled())

      case "launchAtStartupSetEnabled":
        let arguments = call.arguments as? [String: Any]
        let enabled = arguments?["setEnabledValue"] as? Bool ?? false
        Self.setLaunchAtStartupEnabled(enabled)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func isLaunchAtStartupEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    // macOS < 13：不支援 SMAppService，回傳 false（功能在舊系統停用）。
    return false
  }

  private static func setLaunchAtStartupEnabled(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          // 已註冊時重複 register 會拋錯，先檢查狀態避免噪音。
          if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
          }
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        NSLog("[launch_at_startup] setEnabled(\(enabled)) failed: \(error)")
      }
    } else {
      NSLog("[launch_at_startup] SMAppService 需要 macOS 13+，此系統略過")
    }
  }
}

/// 假全螢幕覆蓋偵測器（ticket 1.2.1-W2-001）。
///
/// native fullscreen（綠燈鈕）由 window_manager 的 fullScreenAuxiliary=false
/// 處理；假全螢幕（YouTube 全螢幕、Keynote 播放、遊戲）是一個鋪滿螢幕的
/// 「普通視窗」，不建獨立 Space，fullScreenAuxiliary 對其無效。
///
/// 方案（依 ANA 1.2.1-W1-001）：
/// - C：以 NSWorkspace active app / active space 變化作為觸發源（避免持續輪詢）。
/// - A：觸發時跑一次 CGWindowList 覆蓋判定（排除自身與系統層，
///   判斷是否有 normal-layer 視窗鋪滿遮罩視窗所在螢幕）。
/// 結論經 method channel 回報 Dart，由 Dart 端切換 `_clockVisible`。
final class FullscreenCoverageDetector {
  private weak var hostWindow: NSWindow?
  private let channel: FlutterMethodChannel
  private let ownerPID = ProcessInfo.processInfo.processIdentifier

  /// 上次回報的覆蓋狀態，僅在變化時推送，避免重複通知。
  private var lastCovered: Bool?

  init(hostWindow: NSWindow, messenger: FlutterBinaryMessenger) {
    self.hostWindow = hostWindow
    self.channel = FlutterMethodChannel(
      name: "screen_clock/fullscreen_detect",
      binaryMessenger: messenger
    )
  }

  /// 訂閱觸發源並做一次初始評估。
  func start() {
    let center = NSWorkspace.shared.notificationCenter
    let triggers: [NSNotification.Name] = [
      NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.didActivateApplicationNotification,
    ]
    for name in triggers {
      center.addObserver(
        self,
        selector: #selector(handleTrigger),
        name: name,
        object: nil
      )
    }
    // 螢幕參數變化（解析度 / menu bar 隱藏）也視為觸發源。
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTrigger),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    evaluate()
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func handleTrigger() {
    // 觸發後稍候再評估：active space 切換當下視窗清單可能尚未穩定。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.evaluate()
    }
  }

  /// 跑一次 CGWindowList 覆蓋判定並在狀態變化時回報 Dart。
  private func evaluate() {
    guard let screenFrame = targetScreenFrame() else { return }
    let covered = isScreenCoveredByForeignWindow(screenFrame: screenFrame)
    guard covered != lastCovered else { return }
    lastCovered = covered
    NSLog(
      "[fullscreen-detect] coverage changed: covered=\(covered) "
        + "screenFrame=\(NSStringFromRect(screenFrame))"
    )
    channel.invokeMethod("onCoverageChanged", arguments: ["covered": covered])
  }

  /// 取得遮罩視窗目前所在螢幕的 frame（全域座標，左下原點）。
  private func targetScreenFrame() -> NSRect? {
    return hostWindow?.screen?.frame ?? NSScreen.main?.frame
  }

  /// 是否存在「非本 app、normal layer、且鋪滿目標螢幕」的視窗。
  ///
  /// 只讀取 bounds + layer + owner PID，不取 window title，故不需 Screen
  /// Recording 權限。座標轉換：CGWindowList 的 bounds 為左上原點（CG 座標系），
  /// 須與同為左上原點的目標螢幕 rect 比對。
  private func isScreenCoveredByForeignWindow(screenFrame: NSRect) -> Bool {
    let targetRect = cgRectForScreen(screenFrame)
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
      let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]]
    else {
      return false
    }

    for window in windows {
      // 排除本 app 自身視窗（遮罩時鐘）。
      if let pid = window[kCGWindowOwnerPID as String] as? pid_t,
        pid == ownerPID
      {
        continue
      }
      // 只看 normal layer（0）。Dock / menubar / 系統 UI 的 layer 非 0。
      guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0
      else {
        continue
      }
      guard
        let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
        let windowRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
      else {
        continue
      }
      if windowCoversScreen(windowRect: windowRect, targetRect: targetRect) {
        return true
      }
    }
    return false
  }

  /// 將 NSScreen frame（左下原點）轉為 CG 座標（左上原點）以對齊 CGWindowList。
  private func cgRectForScreen(_ screenFrame: NSRect) -> CGRect {
    let globalHeight = NSScreen.screens
      .map { $0.frame.maxY }
      .max() ?? screenFrame.maxY
    let flippedY = globalHeight - screenFrame.maxY
    return CGRect(
      x: screenFrame.origin.x,
      y: flippedY,
      width: screenFrame.width,
      height: screenFrame.height
    )
  }

  /// 視窗是否覆蓋整個目標螢幕（容忍數 px 誤差）。
  private func windowCoversScreen(windowRect: CGRect, targetRect: CGRect) -> Bool {
    let tolerance: CGFloat = 2
    return windowRect.minX <= targetRect.minX + tolerance
      && windowRect.minY <= targetRect.minY + tolerance
      && windowRect.maxX >= targetRect.maxX - tolerance
      && windowRect.maxY >= targetRect.maxY - tolerance
  }
}

/// 滑鼠輸入綁定原生橋接（ticket 1.3.0-W2-001 + W2-003，SPEC-007 FR-03/FR-07）。
///
/// 提供 Dart 端輔助使用授權查詢 / 請求與綁定下傳，並依綁定清單建立 CGEventTap
/// 攔截側鍵事件分派動作（拖曳滾動 / 快捷鍵）：
/// - queryPermission → 回傳 AXIsProcessTrusted()（是否已授權）。
/// - requestPermission → AXIsProcessTrustedWithOptions 觸發系統提示，回傳當下狀態。
/// - updateBindings → 收下綁定清單快照；已授權時即時建立 / 更新 CGEventTap。
///
/// 分派規則（依 buttonNumber 比對綁定）：
/// - DragScroll 綁定 → down 進入拖曳並消費；move 依方向 / 靈敏度合成滾輪；up 離開並消費。
/// - Hotkey 綁定 → 本階段先消費 + log（HotkeyAction 執行留 W3）。
/// - 未綁定 → 放行。
///
/// 授權狀態變化以 onPermissionChanged 回報 Dart。channel 與方法名須與
/// lib/app_constants.dart 的 AppInputBinding 字面一致。
final class InputBindingBridge {
  private let channel: FlutterMethodChannel

  /// 已下傳的綁定快照：buttonNumber → 動作描述（type + 參數）。
  private var bindingsByButton: [Int64: [String: Any]] = [:]

  /// CGEventTap 與 run loop source（已授權時建立；綁定變更時沿用同一 tap）。
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let scrollSource = CGEventSource(stateID: .hidSystemState)

  /// 拖曳滾動狀態：目前正在拖曳的綁定（nil 表示未拖曳）。
  private var draggingAction: [String: Any]?
  private var lastDragY: CGFloat = 0

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "screen_clock/input_binding",
      binaryMessenger: messenger
    )
    self.channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handle(call: call, result: result)
    }
  }

  deinit {
    teardownTap()
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "queryPermission":
      result(AXIsProcessTrusted())

    case "requestPermission":
      let options =
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
      result(AXIsProcessTrustedWithOptions(options))

    case "updateBindings":
      let arguments = call.arguments as? [String: Any]
      let bindings = arguments?["bindings"] as? [[String: Any]] ?? []
      applyBindings(bindings)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 收下綁定快照並在已授權時建立 / 更新 CGEventTap。
  ///
  /// 無綁定時拆除 tap（避免無謂攔截）；有綁定但未授權時不建立（由 Dart 端
  /// 觸發授權提示後重新下傳）。
  private func applyBindings(_ bindings: [[String: Any]]) {
    bindingsByButton.removeAll()
    for binding in bindings {
      guard let button = binding["buttonNumber"] as? Int,
        let action = binding["action"] as? [String: Any]
      else { continue }
      bindingsByButton[Int64(button)] = action
    }
    NSLog("[input-binding] updateBindings: \(bindingsByButton.count) 筆綁定")

    if bindingsByButton.isEmpty {
      teardownTap()
      return
    }
    guard AXIsProcessTrusted() else {
      NSLog("[input-binding] 尚未授權，CGEventTap 暫不建立")
      return
    }
    ensureTap()
  }

  /// 建立 CGEventTap（沿用 spike 的 mask + 消費邏輯）；已存在則沿用。
  private func ensureTap() {
    if eventTap != nil { return }
    let mask: CGEventMask =
      (1 << CGEventType.otherMouseDown.rawValue)
      | (1 << CGEventType.otherMouseUp.rawValue)
      | (1 << CGEventType.mouseMoved.rawValue)
      | (1 << CGEventType.otherMouseDragged.rawValue)
      | (1 << CGEventType.leftMouseDragged.rawValue)
      | (1 << CGEventType.rightMouseDragged.rawValue)

    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
          guard let refcon = refcon else {
            return Unmanaged.passUnretained(event)
          }
          let bridge = Unmanaged<InputBindingBridge>
            .fromOpaque(refcon).takeUnretainedValue()
          return bridge.handleTapEvent(type: type, event: event)
        },
        userInfo: userInfo
      )
    else {
      NSLog("[input-binding] CGEventTap 建立失敗（確認授權）")
      return
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTap = tap
    runLoopSource = source
    NSLog("[input-binding] CGEventTap 已啟用")
  }

  /// 拆除 CGEventTap 並釋放 run loop source。
  private func teardownTap() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    runLoopSource = nil
    eventTap = nil
    draggingAction = nil
  }

  /// CGEventTap 回呼：依綁定分派側鍵事件（回呼維持輕量，NFR-01）。
  private func handleTapEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    // tap 被系統因逾時 / 使用者輸入停用時自動重新啟用。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }

    switch type {
    case .otherMouseDown:
      let button = event.getIntegerValueField(.mouseEventButtonNumber)
      return handleButtonDown(button: button, event: event)

    case .otherMouseUp:
      return handleButtonUp(event: event)

    case .mouseMoved, .otherMouseDragged, .leftMouseDragged, .rightMouseDragged:
      return handleDragMove(event: event)

    default:
      return Unmanaged.passUnretained(event)
    }
  }

  /// 側鍵按下：命中綁定則分派（DragScroll 進入拖曳 / Hotkey 消費 log），消費事件。
  private func handleButtonDown(
    button: Int64,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    guard let action = bindingsByButton[button] else {
      return Unmanaged.passUnretained(event)
    }
    let type = action["type"] as? String
    if type == "dragScroll" {
      draggingAction = action
      lastDragY = event.location.y
      return nil
    }
    if type == "hotkey" {
      // HotkeyAction 執行留 W3；本階段先消費並記錄，避免側鍵觸發瀏覽器上下頁。
      NSLog("[input-binding] hotkey 綁定觸發（執行留 W3），消費事件")
      return nil
    }
    return Unmanaged.passUnretained(event)
  }

  /// 側鍵放開：若正在拖曳則離開並消費，否則放行。
  private func handleButtonUp(event: CGEvent) -> Unmanaged<CGEvent>? {
    if draggingAction != nil {
      draggingAction = nil
      return nil
    }
    return Unmanaged.passUnretained(event)
  }

  /// 拖曳移動：拖曳中依方向 / 靈敏度合成滾輪並消費，否則放行。
  private func handleDragMove(event: CGEvent) -> Unmanaged<CGEvent>? {
    guard let action = draggingAction else {
      return Unmanaged.passUnretained(event)
    }
    let y = event.location.y
    let dy = y - lastDragY  // 螢幕座標 y 向下為正：往下拖 → dy > 0
    lastDragY = y
    if dy != 0 {
      postScroll(dy: dy, action: action)
    }
    // 拖曳期間移動事件一併消費，避免同時驅動游標位移。
    return nil
  }

  /// 依綁定方向 / 靈敏度合成垂直滾輪事件注入游標下方 app。
  private func postScroll(dy: CGFloat, action: [String: Any]) {
    let sensitivity = (action["sensitivity"] as? Double) ?? 1.0
    let inverted = (action["direction"] as? String) == "inverted"
    // natural：往下拖 = 往下捲（spike 驗證需對 dy 取負）。
    let directed = inverted ? dy : -dy
    var amount = Int32(directed * sensitivity)
    if amount == 0 { amount = directed > 0 ? 1 : -1 }
    let scroll = CGEvent(
      scrollWheelEvent2Source: scrollSource,
      units: .pixel,
      wheelCount: 1,
      wheel1: amount,
      wheel2: 0,
      wheel3: 0
    )
    scroll?.post(tap: .cghidEventTap)
  }
}

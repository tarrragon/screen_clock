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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 假全螢幕覆蓋偵測器（強參考持有，隨視窗生命週期存活）。
  private var fullscreenDetector: FullscreenCoverageDetector?

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

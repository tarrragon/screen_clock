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

    // ticket 1.4.0-W1-001.3：滑鼠定位器 method channel 橋接骨架（SPEC-008 FR-01）。
    // 收到 play 僅 NSLog 記錄；特效視窗管理留 1.4.0-W2-006、視覺特效繪製留
    // 1.4.0-W3-001，本階段刻意不做事以保留下游介面調整空間。
    self.cursorLocatorBridge = CursorLocatorBridge(
      messenger: flutterViewController.engine.binaryMessenger
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 假全螢幕覆蓋偵測器（強參考持有，隨視窗生命週期存活）。
  private var fullscreenDetector: FullscreenCoverageDetector?

  /// 滑鼠輸入綁定原生橋接（強參考持有，隨視窗生命週期存活）。
  private var inputBindingBridge: InputBindingBridge?

  /// 滑鼠定位器 method channel 橋接（強參考持有，隨視窗生命週期存活）。
  private var cursorLocatorBridge: CursorLocatorBridge?

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

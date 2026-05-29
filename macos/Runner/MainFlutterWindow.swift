import Cocoa
import FlutterMacOS

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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

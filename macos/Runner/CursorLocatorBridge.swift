import Cocoa
import FlutterMacOS

/// 滑鼠定位器 method channel 橋接骨架（ticket 1.4.0-W1-001.3，SPEC-008 FR-01）。
///
/// 僅註冊 channel 並處理 play 方法；不建立特效視窗、不繪製任何內容。特效
/// 視窗管理留 1.4.0-W2-006、視覺特效繪製留 1.4.0-W3-001（骨架階段脈絡供
/// 開發參考，不放進 runtime log——log 是長壽字串，階段完成後仍會誤導讀
/// log 的人，見 1.4.0-W2-016）。
///
/// channel 名 / 方法名 / 參數鍵字面須與 lib/app_constants.dart 的
/// AppCursorLocator 常數逐項一致（Swift 無法 import Dart 常數，故以下列
/// enum 承載相同字面）。
private enum CursorLocatorChannel {
  static let name = "screen_clock/cursor_locator"
  static let playMethod = "play"
  static let durationMsArgKey = "durationMs"
  static let tintArgbArgKey = "tintArgb"
}

/// 單一參數鍵的提取結果：成功 / 未帶參數 / 帶了但型別不符。
///
/// 與單純 `as? T` 相比，此區分讓失敗路徑能各自記錄具體原因（ticket
/// 1.4.0-W2-016：原本轉換失敗一律靜默變 nil，log 印出的 nil 無法分辨是
/// 「Dart 端沒帶這個參數」還是「帶了但型別不符」）。
private enum CursorLocatorArgument<T> {
  case success(T)
  case missing
  case typeMismatch(received: Any)
}

/// 從 `[String: Any]` 參數字典提取指定鍵並轉型，回報提取結果。
private func extractCursorLocatorArgument<T>(
  _ arguments: [String: Any]?,
  key: String
) -> CursorLocatorArgument<T> {
  guard let raw = arguments?[key] else { return .missing }
  guard let value = raw as? T else { return .typeMismatch(received: raw) }
  return .success(value)
}

final class CursorLocatorBridge {
  private let channel: FlutterMethodChannel

  /// 特效視窗控制器（子票 1.4.0-W2-006.2.2）。四個依賴皆傳 production 實作。
  private let controller: CursorLocatorEffectController

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: CursorLocatorChannel.name,
      binaryMessenger: messenger
    )
    self.controller = CursorLocatorEffectController(
      snapshotProvider: productionCursorScreenSnapshot,
      locationSampler: productionCursorLocation,
      surfaceMaker: makeProductionCursorLocatorSurface,
      frameDriver: DisplayLinkCursorLocatorFrameDriving(),
      deadlineScheduler: makeProductionCursorLocatorDeadlineScheduler(),
      // 特效 renderer 的接線點。陣列順序即 sublayer 疊加順序（先加者在下），
      // 三者的相對關係無法由任一子票單獨決定，於整併票 1.4.0-W3-001 定案：
      // 聚光燈（子票 .2）是覆蓋全螢幕的壓暗遮罩，必須墊底，否則會蓋住其餘兩者；
      // 波紋（.4）在游標處疊於壓暗之上；邊框閃爍（.3）位於最外層不受壓暗影響。
      renderer: CursorLocatorCompositeRenderer(renderers: [
        CursorLocatorSpotlightRenderer(),
        CursorLocatorRippleRenderer(),
        CursorLocatorBorderFlashRenderer()
      ])
    )
    self.channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handle(call: call, result: result)
    }
    NSLog("[cursor-locator] channel 已註冊: \(CursorLocatorChannel.name)")
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case CursorLocatorChannel.playMethod:
      handlePlay(call: call, result: result)

    default:
      NSLog("[cursor-locator] 未知方法: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }

  /// 解析 play 參數。兩個鍵皆成功轉型才視為合法呼叫；任一失敗則個別記錄
  /// 失敗原因（未帶參數 / 型別不符，各自帶上原始 arguments 內容），並以
  /// FlutterError 回覆——Dart 端既有的 catch-log 包裝
  /// （1.4.0-W2-007 invokeMethodSafely 已捕捉 PlatformException 並記錄）
  /// 會因此自動感知並留下訊號，取代原本「result(nil) 靜默視為成功」的行為。
  private func handlePlay(call: FlutterMethodCall, result: FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let durationResult: CursorLocatorArgument<Int> = extractCursorLocatorArgument(
      arguments, key: CursorLocatorChannel.durationMsArgKey
    )
    let tintResult: CursorLocatorArgument<Int> = extractCursorLocatorArgument(
      arguments, key: CursorLocatorChannel.tintArgbArgKey
    )

    guard case .success(let durationMs) = durationResult,
      case .success(let tintArgb) = tintResult
    else {
      logArgumentFailure(
        key: CursorLocatorChannel.durationMsArgKey,
        outcome: durationResult,
        rawArguments: call.arguments
      )
      logArgumentFailure(
        key: CursorLocatorChannel.tintArgbArgKey,
        outcome: tintResult,
        rawArguments: call.arguments
      )
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "cursor_locator play 參數缺失或型別不符",
          details: String(describing: call.arguments)
        )
      )
      return
    }

    NSLog("[cursor-locator] play 收到: durationMs=\(durationMs) tintArgb=\(tintArgb)")

    let request = CursorLocatorPlayRequest(
      duration: TimeInterval(durationMs) / 1000.0,
      tint: NSColor(cursorLocatorArgb: tintArgb)
    )
    do {
      try controller.play(request)
      result(nil)
    } catch let error as CursorLocatorError {
      result(CursorLocatorErrorMapping.flutterError(for: error))
    } catch {
      NSLog("[cursor-locator] play 未預期錯誤: \(error)")
      result(
        FlutterError(
          code: CursorLocatorErrorCode.windowCreationFailed,
          message: "特效播放發生未預期錯誤",
          details: String(describing: error)
        )
      )
    }
  }

  /// 記錄單一參數鍵的提取失敗原因；成功結果不記（呼叫端已在成功路徑統一記錄）。
  private func logArgumentFailure<T>(
    key: String,
    outcome: CursorLocatorArgument<T>,
    rawArguments: Any?
  ) {
    switch outcome {
    case .success:
      return
    case .missing:
      NSLog(
        "[cursor-locator] play 參數缺失: key=\(key), arguments=\(String(describing: rawArguments))"
      )
    case .typeMismatch(let received):
      NSLog(
        "[cursor-locator] play 參數型別不符: key=\(key), 收到型別=\(type(of: received)), "
          + "arguments=\(String(describing: rawArguments))"
      )
    }
  }
}

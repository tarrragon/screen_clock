import FlutterMacOS

/// `CursorLocatorError` -> `FlutterError` 的錯誤碼字面對應（母票 Phase 3a N-1
/// 裁定產物）。
///
/// 獨立於 `CursorLocatorEffectWindow.swift`（該檔刻意只依賴 AppKit）與
/// `MainFlutterWindow.swift`（836 行，已超 cognitive-load 閾值，Phase 1 §2.10
/// 明定只改一處）。三檔依賴方向單向：effect window（AppKit）<- mapping
/// （Flutter）<- bridge，無循環。
///
/// 抽為純函式使 acceptance 6「回報 Dart 側」在不啟動 channel／Flutter engine
/// 的情況下即可被 XCTest 逐字斷言錯誤碼（RunnerTests 群組 E：T2.E-05/E-06）。
enum CursorLocatorErrorMapping {

  /// 將 `CursorLocatorError?` 對應為 `FlutterError?`；輸入 `nil`（成功）時
  /// 回傳 `nil`，對應 `result(nil)` 語意。
  ///
  /// 測試端反向約束（母票 Phase 2 §四）：T2.E-05 以字串字面逐字斷言，不得
  /// 引用本檔的 `CursorLocatorErrorCode` 常數——常數改名時測試須同步改，
  /// 錯誤碼契約才有鎖定力。
  static func flutterError(for error: CursorLocatorError?) -> FlutterError? {
    guard let error = error else { return nil }

    switch error {
    case .windowCreationFailed(let underlying):
      return FlutterError(
        code: CursorLocatorErrorCode.windowCreationFailed,
        message: "特效視窗建立失敗",
        details: underlying
      )
    case .noAvailableScreen:
      return FlutterError(
        code: CursorLocatorErrorCode.noAvailableScreen,
        message: "無任何可用螢幕",
        details: nil
      )
    }
  }
}

/// SPEC-008 定義的錯誤碼字面。目前 Dart 側尚無對應常數——`AppCursorLocator`
/// 不含任何錯誤碼，全 Dart 樹亦無 `E_CL` 字面；此處為單一來源。待
/// `1.4.0-W2-026` 建立 Dart 側常數後，兩邊須逐項一致（Swift 無法 import Dart
/// 常數，屆時由各自列舉承載相同字面），該一致性的機械檢查屬 `1.4.0-W2-035`。
enum CursorLocatorErrorCode {
  /// 特效視窗建立失敗（EX-06-03）。
  static let windowCreationFailed = "E_CL_WINDOW"

  /// 無任何可用螢幕（`CursorScreenResolution.unavailable`）。
  static let noAvailableScreen = "E_CL_SCREEN"
}

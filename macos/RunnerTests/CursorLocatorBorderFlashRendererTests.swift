import XCTest

@testable import screen_clock

/// 螢幕邊框閃爍特效（SPEC-008 FR-04、子票 `1.4.0-W3-001.3`）。
///
/// 覆蓋三面：閃爍時間曲線（純函式 `flashAlpha`）、邊框幾何與顏色來源、
/// 圖層生命週期（attach/detach/重置）。
///
/// 本檔期望值皆由 `CursorLocatorEffectConstants` 的 `borderWidth`／
/// `flashCycleDuration`／`flashCycleCount` 推導；調整這三個常數需同步檢視本檔。
final class CursorLocatorBorderFlashRendererTests: XCTestCase {

  private let cycle = CursorLocatorEffectConstants.flashCycleDuration
  private var totalFlashDuration: TimeInterval {
    cycle * Double(CursorLocatorEffectConstants.flashCycleCount)
  }

  private func makeFrame(elapsed: TimeInterval, duration: TimeInterval = 1.5)
    -> CursorLocatorEffectFrame
  {
    CursorLocatorEffectFrame(
      progress: duration > 0 ? min(elapsed / duration, 1) : 1,
      elapsed: elapsed,
      duration: duration,
      cursorPointInLayer: .zero,
      tint: .red
    )
  }

  // MARK: - 閃爍時間曲線（純函式）

  /// 播放起點邊框不可見，避免首幀突然全亮。
  func testFlashAlpha_atStart_isInvisible() {
    XCTAssertEqual(CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: 0), 0, accuracy: 1e-9)
  }

  /// 每個週期的中點為全亮（淡入完成、淡出起點）。
  func testFlashAlpha_atEachCyclePeak_isFullyOpaque() {
    for index in 0..<CursorLocatorEffectConstants.flashCycleCount {
      let peak = cycle * Double(index) + cycle / 2
      XCTAssertEqual(
        CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: peak), 1, accuracy: 1e-9,
        "第 \(index + 1) 次閃爍的峰值應為全亮")
    }
  }

  /// 每個週期的邊界為全暗，三次閃爍因此彼此分離而可數。
  func testFlashAlpha_atEachCycleBoundary_isInvisible() {
    for index in 0...CursorLocatorEffectConstants.flashCycleCount {
      let boundary = cycle * Double(index)
      XCTAssertEqual(
        CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: boundary), 0, accuracy: 1e-9,
        "第 \(index) 個週期邊界應為全暗")
    }
  }

  /// 前半淡入、後半淡出：同一週期內對稱的兩點不透明度相同且非端點值。
  func testFlashAlpha_withinCycle_fadesInThenOut() {
    let quarter = cycle / 4
    let fadingIn = CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: quarter)
    let fadingOut = CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: cycle - quarter)

    XCTAssertEqual(fadingIn, 0.5, accuracy: 1e-9)
    XCTAssertEqual(fadingOut, 0.5, accuracy: 1e-9)
  }

  /// 三次閃爍結束後恆為 0：總時長長於 600 ms 時邊框不再出現第四次。
  func testFlashAlpha_afterAllCycles_staysInvisible() {
    XCTAssertEqual(
      CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: totalFlashDuration), 0, accuracy: 1e-9)
    XCTAssertEqual(
      CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: totalFlashDuration + cycle / 2), 0,
      accuracy: 1e-9)
    XCTAssertEqual(
      CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: 10), 0, accuracy: 1e-9)
  }

  /// 在途幀或時鐘倒退可能送來負的 elapsed，不得回傳負不透明度。
  func testFlashAlpha_negativeElapsed_isInvisible() {
    XCTAssertEqual(CursorLocatorBorderFlashRenderer.flashAlpha(elapsed: -1), 0, accuracy: 1e-9)
  }

  /// 總時長短於三次週期時採截斷：曲線不隨總時長壓縮，週期固定 200 ms。
  /// 播放於 duration 結束，故實際看到的閃爍次數不足三次。
  func testFlashAlpha_isIndependentOfDuration() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    renderer.attach(to: layer, tint: .red, duration: 0.3)
    renderer.render(makeFrame(elapsed: cycle / 2, duration: 0.3))
    let shortDurationPeak = renderer.borderLayer?.opacity

    renderer.attach(to: layer, tint: .red, duration: 3.0)
    renderer.render(makeFrame(elapsed: cycle / 2, duration: 3.0))
    let longDurationPeak = renderer.borderLayer?.opacity

    XCTAssertEqual(shortDurationPeak, 1)
    XCTAssertEqual(longDurationPeak, 1)
  }

  // MARK: - 邊框幾何與顏色

  func testAttach_drawsBorderHuggingLayerBoundsWithSpecifiedWidth() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    renderer.attach(to: layer, tint: .red, duration: 1.5)

    let border = try? XCTUnwrap(renderer.borderLayer)
    XCTAssertEqual(border?.frame, layer.bounds)
    XCTAssertEqual(border?.borderWidth, CursorLocatorEffectConstants.borderWidth)
  }

  /// 邊框僅佔四周邊緣：內部不得填色，否則整個螢幕會被覆蓋。
  func testAttach_leavesCenterUncovered() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    renderer.attach(to: layer, tint: .red, duration: 1.5)

    XCTAssertNil(renderer.borderLayer?.backgroundColor)
    XCTAssertNil(renderer.borderLayer?.contents)
  }

  /// 顏色取自 `request.tint`（FR-06），非硬編碼。
  func testAttach_usesProvidedTintAsBorderColor() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .green, duration: 1.5)
    XCTAssertEqual(renderer.borderLayer?.borderColor, NSColor.green.cgColor)

    renderer.attach(to: layer, tint: .blue, duration: 1.5)
    XCTAssertEqual(renderer.borderLayer?.borderColor, NSColor.blue.cgColor)
  }

  // MARK: - 圖層生命週期

  func testAttach_addsExactlyOneSublayer() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .red, duration: 1.5)

    XCTAssertEqual(layer.sublayers?.count, 1)
  }

  /// 重置（播放中再次觸發）重新 attach，不得在同一 layer 上疊出第二條邊框。
  func testReattach_doesNotAccumulateSublayers() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .red, duration: 1.5)
    renderer.attach(to: layer, tint: .green, duration: 3.0)

    XCTAssertEqual(layer.sublayers?.count, 1)
    XCTAssertEqual(renderer.borderLayer?.borderColor, NSColor.green.cgColor)
  }

  func testDetach_removesBorderFromLayer() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .red, duration: 1.5)
    renderer.detach()

    XCTAssertNil(renderer.borderLayer)
    XCTAssertTrue(layer.sublayers?.isEmpty ?? true)
  }

  func testDetach_beforeAttach_isNoOp() {
    let renderer = CursorLocatorBorderFlashRenderer()
    renderer.detach()
    XCTAssertNil(renderer.borderLayer)
  }

  /// detach 後仍可能有一幀在途，render 不得崩潰或復活邊框。
  func testRender_afterDetach_isNoOp() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .red, duration: 1.5)
    renderer.detach()
    renderer.render(makeFrame(elapsed: cycle / 2))

    XCTAssertNil(renderer.borderLayer)
    XCTAssertTrue(layer.sublayers?.isEmpty ?? true)
  }

  /// attach 與首幀之間邊框不可見。
  func testAttach_beforeFirstFrame_isInvisible() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()

    renderer.attach(to: layer, tint: .red, duration: 1.5)

    XCTAssertEqual(renderer.borderLayer?.opacity, 0)
  }

  /// 逐幀 render 把時間曲線寫入圖層不透明度。
  func testRender_appliesFlashAlphaToBorderOpacity() {
    let renderer = CursorLocatorBorderFlashRenderer()
    let layer = CALayer()
    renderer.attach(to: layer, tint: .red, duration: 1.5)

    renderer.render(makeFrame(elapsed: cycle / 2))
    XCTAssertEqual(renderer.borderLayer?.opacity, 1)

    renderer.render(makeFrame(elapsed: cycle))
    XCTAssertEqual(renderer.borderLayer?.opacity, 0)

    renderer.render(makeFrame(elapsed: totalFlashDuration + 0.5))
    XCTAssertEqual(renderer.borderLayer?.opacity, 0)
  }
}

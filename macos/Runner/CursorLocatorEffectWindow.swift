import Cocoa

/// 特效層目標螢幕判定。
///
/// 對應規格：SPEC-008 FR-02（目標螢幕判定與跨螢幕跟隨）、UC-06 主成功步驟 2/3/5、
/// 例外 EX-06-02（螢幕解析失敗）。
///
/// 本檔（子票 1.4.0-W2-006.1）只交付「決定在哪播」的純資料運算：值型別快照、
/// 判定結果型別、單一靜態判定函式。特效視窗生命週期（NSWindow 建立、
/// CVDisplayLink 驅動、淡出釋放）屬子票 1.4.0-W2-006.2，不在本檔範圍。

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

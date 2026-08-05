/// Hotkey 綁定按鍵 down/up 消費配對狀態（SPEC-007 FR-03，1.4.0-W1-020 判定的
/// 缺口修正）。
///
/// `InputBindingBridge.handleButtonDown` 對 Hotkey 綁定的側鍵一律消費
/// mouseDown（合成鍵盤事件後 `return nil`），但既有 `handleButtonUp` 只在
/// DragScroll 拖曳中（`draggingAction != nil`）才消費，Hotkey 綁定的
/// mouseUp 因此穿透至底層應用，與 SPEC-007 FR-03「otherMouseDown 與
/// otherMouseUp 皆消費」不符。
///
/// 本型別把「記錄 Hotkey down 已消費」與「比對對應 up 是否應一併消費」
/// 抽為獨立可測狀態機，供 `InputBindingBridge` 持有一個實例。抽出理由與
/// `CursorLocatorErrorMapping` 等既有先例相同：`MainFlutterWindow.swift`
/// 依賴實例化即建立 CGEventTap，無人值守測試環境可能觸發輔助使用權限
/// 對話框而阻塞，故消費判定邏輯須獨立於 window 之外才能被 XCTest 覆蓋。
///
/// 以 `Set<Int64>`（而非單一 optional button number）儲存，容忍多個側鍵
/// 近乎同時按下的情境；DragScroll 的消費由既有 `draggingAction` 狀態機
/// 處理（呼叫端優先權更高，見 `InputBindingBridge.handleButtonUp`），本型
/// 別只處理 Hotkey 分支，兩者狀態互不干涉。
struct ButtonEventConsumption {
  private var consumedDownButtons: Set<Int64> = []

  /// 記錄一次 Hotkey 綁定的 mouseDown 已消費，供對應 mouseUp 比對。
  mutating func recordHotkeyDownConsumed(button: Int64) {
    consumedDownButtons.insert(button)
  }

  /// 判斷該 button 的 mouseUp 是否對應先前記錄的 Hotkey down；若是，消費
  /// 並清除記錄（一次性配對，避免重複消費同一 button 之後未綁定的 up）。
  mutating func consumeHotkeyUpIfMatched(button: Int64) -> Bool {
    guard consumedDownButtons.remove(button) != nil else { return false }
    return true
  }
}

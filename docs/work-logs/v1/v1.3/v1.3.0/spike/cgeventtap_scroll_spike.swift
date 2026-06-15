// CGEventTap 拖曳滾動可行性 spike（ticket 1.3.0-W1-001）
//
// 目的：在不動 app 本體的前提下，最小驗證 PROP-002 的四個假設：
//   假設 1：CGEventTap 能攔截滑鼠側鍵（otherMouseDown/Up）與移動，並讀到 buttonNumber。
//   假設 2：按住側鍵 + 垂直位移合成 CGScrollWheelEvent 能讓游標下方 app 實機捲動。
//   假設 3：取得「輔助使用」授權後 event tap 可建立（AXIsProcessTrusted）。
//   假設 4：回呼回傳 nil 消費側鍵事件，使原本的上一頁/下一頁不觸發，且系統滑鼠不卡頓。
//
// 執行：
//   swift docs/work-logs/v1/v1.3/v1.3.0/spike/cgeventtap_scroll_spike.swift
//
// 權限：以 swift 直譯執行時，需被授權的是「執行此命令的終端機 app」（Terminal / iTerm）。
//   首次執行會跳出系統提示，請到 系統設定 → 隱私權與安全性 → 輔助使用
//   把該終端機打勾，然後重跑。
//
// 操作：把游標移到瀏覽器/文件上，按住任一滑鼠側鍵並上下移動 → 觀察是否捲動。
//   終端機會印出每顆側鍵的 buttonNumber。Ctrl+C 結束。

import Cocoa
import CoreGraphics
import ApplicationServices

// ── 可調參數（spike 期間直接改這裡觀察手感）─────────────────
let sensitivity: Double = 1.0   // 位移→滾輪量倍率
let invertDirection = false     // true 時上下相反；先看預設是否「往下拖=往下捲」
// ───────────────────────────────────────────────────────

var dragging = false
var lastY: CGFloat = 0
let scrollSource = CGEventSource(stateID: .hidSystemState)
var tapRef: CFMachPort?

func handle(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  // tap 被系統因逾時/使用者輸入停用時自動重新啟用。
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let t = tapRef { CGEvent.tapEnable(tap: t, enable: true) }
    return Unmanaged.passUnretained(event)
  }

  switch type {
  case .otherMouseDown:
    let button = event.getIntegerValueField(.mouseEventButtonNumber)
    print("[down] 側鍵 buttonNumber=\(button) → 進入拖曳滾動，消費此事件（吃掉原動作）")
    dragging = true
    lastY = event.location.y
    // 假設 4：回傳 nil 消費事件，原本的上一頁/下一頁不應觸發。
    return nil

  case .otherMouseUp:
    if dragging {
      dragging = false
      print("[up] 離開拖曳滾動，消費此事件")
      return nil
    }
    return Unmanaged.passUnretained(event)

  case .mouseMoved, .otherMouseDragged, .leftMouseDragged, .rightMouseDragged:
    guard dragging else { return Unmanaged.passUnretained(event) }
    let y = event.location.y
    let dy = y - lastY          // 螢幕座標 y 向下為正：往下拖 → dy > 0
    lastY = y
    if dy != 0 {
      // 假設 2：合成垂直滾輪事件注入游標下方 app。
      var amount = Int32((invertDirection ? dy : -dy) * sensitivity)
      if amount == 0 { amount = dy > 0 ? -1 : 1 }
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
    // 拖曳期間的移動事件一併消費，避免同時驅動游標位移。
    return nil

  default:
    return Unmanaged.passUnretained(event)
  }
}

// 假設 3：檢查輔助使用授權；未授權則觸發系統提示後退出。
let trusted = AXIsProcessTrustedWithOptions(
  [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
)
if !trusted {
  print("""
  [權限] 尚未取得「輔助使用」授權。
  請到 系統設定 → 隱私權與安全性 → 輔助使用，
  把目前執行此指令的終端機 app（Terminal / iTerm）打勾，然後重新執行本 spike。
  """)
  exit(1)
}
print("[權限] 輔助使用已授權（假設 3 成立）。")

// 假設 1 + 4：建立可消費事件的 event tap（.cgSessionEventTap，非 listenOnly）。
let mask: CGEventMask =
  (1 << CGEventType.otherMouseDown.rawValue)
  | (1 << CGEventType.otherMouseUp.rawValue)
  | (1 << CGEventType.mouseMoved.rawValue)
  | (1 << CGEventType.otherMouseDragged.rawValue)
  | (1 << CGEventType.leftMouseDragged.rawValue)
  | (1 << CGEventType.rightMouseDragged.rawValue)

guard
  let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: handle,
    userInfo: nil
  )
else {
  print("[失敗] event tap 建立失敗（假設 1/3 不成立，請確認授權）。")
  exit(1)
}
tapRef = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("""
[就緒] event tap 已啟用（假設 1 成立）。
  操作：把游標移到瀏覽器/文件上，按住任一滑鼠側鍵並上下移動 → 觀察是否捲動。
  觀察重點：
    1) 印出的 buttonNumber，對照你的後側鍵/前側鍵各是幾號。
    2) 往下拖時頁面是否往下捲（不對就把上方 invertDirection 設 true）。
    3) 按住側鍵期間有沒有誤觸上一頁/下一頁（假設 4）。
    4) 滑鼠操作整體有沒有卡頓/異常。
  Ctrl+C 結束。
""")
CFRunLoopRun()

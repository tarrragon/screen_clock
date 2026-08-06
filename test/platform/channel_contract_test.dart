// Dart 與 Swift method channel 契約字面守衛（ticket 1.4.0-W2-009）。
//
// 問題：Dart 側常數（lib/app_constants.dart）與 Swift 側
// macos/Runner/FullscreenCoverageDetector.swift、
// macos/Runner/CursorLocatorBridge.swift 各自宣告同一組 channel 名 /
// 方法名 / 參數鍵字面，兩者之間沒有任何自動化關聯。任一側字面被改動時
// 編譯期全過、單元測試全綠（mock handler 不碰 Swift）、執行期才拋
// MissingPluginException（且被 catch-log 吞掉）。三層都不會產生阻斷性
// 訊號。
//
// 對策：不需 Swift toolchain，改以純 Dart 測試讀取 Swift 原始碼檔案的
// 純文字內容，斷言 Dart 側常數字面以「完整雙引號字串字面」形式存在其中
// （即 `"字面"`，非單純子字串包含）。任一側字面被改動（Dart 端改常數
// 值，或 Swift 端改對應字面），兩側字面即不再逐字相等，測試轉紅。
//
// 為何不能用單純的字串包含（String.contains）：若僅斷言子字串存在，
// 將原字面改為其超集（例如 Swift 端把 "tintArgb" 改成 "tintArgbX"）
// 時，原字面仍是新字串的子字串，`contains` 會誤判為仍相符而維持綠燈，
// 守衛失效。故改為比對「被雙引號完整包住的字面」，任一側只要不是逐字
// 相等即會斷開雙引號邊界而轉紅。
//
// 涵蓋範圍（本票判準第 4 項）：cursor_locator 為必要範圍（Swift 側已用
// enum 集中宣告，四個字面對應清楚）。一併涵蓋 fullscreen_detect——其
// Swift 側三個字面（channelName / onCoverageChangedMethod /
// coveredArgKey）雖未集中於單一宣告處，仍各自以獨立字串字面存在於呼叫
// 點，斷言「檔案內容含此字面」的驗證方式不要求集中宣告，故納入不增加
// 額外成本。
//
// ticket 1.4.0-W2-047：補齊 input_binding 守衛。梳理後 AppInputBinding
// 的字面分兩類——(a) method channel 名稱與方法名（跨語言呼叫點字面，
// 明確跨邊界）；(b) updateBindings 下傳的 binding JSON map 鍵與
// action type 字串（Dart 序列化、Swift 解析同一組鍵，同樣跨邊界，非
// 純 Dart 內部序列化鍵，先前註解的推測不成立）。兩類共 18 個字面，皆已
// 逐一確認以獨立字串字面存在於 InputBindingBridge.swift。
// onPermissionChangedMethod（'onPermissionChanged'）與
// grantedArgKey（'granted'）兩個常數為 Dart 側預先定義、Swift 端尚未
// 實作 invokeMethod 呼叫的未來功能（授權狀態變化通知，見
// lib/app_constants.dart 297-301 行註解），非既有不一致，故不列入本測試
// 斷言範圍——待該功能於 Swift 端實作後另行補上對應斷言。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';

void main() {
  // 取得專案根目錄下 Swift 檔案內容：測試以 flutter test 執行時，
  // 工作目錄固定為專案根目錄，故用相對路徑組出絕對路徑，不依賴
  // Swift toolchain 或建置產物。不引入 package:path（非本專案既有
  // 直接依賴），改以 dart:io 內建 path 串接。
  //
  // ticket 1.4.0-W2-015：MainFlutterWindow.swift 拆分為多檔後，
  // cursor_locator 字面移至 CursorLocatorBridge.swift、
  // fullscreen_detect 字面移至 FullscreenCoverageDetector.swift、
  // input_binding 字面移至 InputBindingBridge.swift。三檔內容合併比對，
  // 維持本測試「跨越 channel 邊界必須守衛」的原意。
  final String runnerDir = '${Directory.current.path}/macos/Runner';
  late String swiftSource;

  setUpAll(() {
    swiftSource = <String>[
      File('$runnerDir/CursorLocatorBridge.swift').readAsStringSync(),
      File('$runnerDir/FullscreenCoverageDetector.swift').readAsStringSync(),
      File('$runnerDir/InputBindingBridge.swift').readAsStringSync(),
    ].join('\n');
  });

  // 斷言 [literal] 以完整雙引號字串字面（`"literal"`）出現在 Swift
  // 原始碼中，避免子字串包含造成的漏判（見檔頭說明）。
  void expectExactLiteralInSwift(String literal) {
    expect(swiftSource, contains('"$literal"'));
  }

  group('AppCursorLocatorChannel 字面須存在於 Swift 端', () {
    test('channelName', () {
      expectExactLiteralInSwift(AppCursorLocatorChannel.channelName);
    });

    test('playMethod', () {
      expectExactLiteralInSwift(AppCursorLocatorChannel.playMethod);
    });

    test('durationMsArgKey', () {
      expectExactLiteralInSwift(AppCursorLocatorChannel.durationMsArgKey);
    });

    test('tintArgbArgKey', () {
      expectExactLiteralInSwift(AppCursorLocatorChannel.tintArgbArgKey);
    });
  });

  group('AppFullscreenDetect 字面須存在於 Swift 端', () {
    test('channelName', () {
      expectExactLiteralInSwift(AppFullscreenDetect.channelName);
    });

    test('onCoverageChangedMethod', () {
      expectExactLiteralInSwift(AppFullscreenDetect.onCoverageChangedMethod);
    });

    test('coveredArgKey', () {
      expectExactLiteralInSwift(AppFullscreenDetect.coveredArgKey);
    });
  });

  group('AppInputBinding 字面須存在於 Swift 端', () {
    test('channelName', () {
      expectExactLiteralInSwift(AppInputBinding.channelName);
    });

    test('queryPermissionMethod', () {
      expectExactLiteralInSwift(AppInputBinding.queryPermissionMethod);
    });

    test('requestPermissionMethod', () {
      expectExactLiteralInSwift(AppInputBinding.requestPermissionMethod);
    });

    test('updateBindingsMethod', () {
      expectExactLiteralInSwift(AppInputBinding.updateBindingsMethod);
    });

    test('beginCaptureButtonMethod', () {
      expectExactLiteralInSwift(AppInputBinding.beginCaptureButtonMethod);
    });

    test('endCaptureButtonMethod', () {
      expectExactLiteralInSwift(AppInputBinding.endCaptureButtonMethod);
    });

    test('onButtonCapturedMethod', () {
      expectExactLiteralInSwift(AppInputBinding.onButtonCapturedMethod);
    });

    test('bindingsArgKey', () {
      expectExactLiteralInSwift(AppInputBinding.bindingsArgKey);
    });

    test('capturedButtonNumberArgKey', () {
      expectExactLiteralInSwift(AppInputBinding.capturedButtonNumberArgKey);
    });

    test('buttonNumberKey', () {
      expectExactLiteralInSwift(AppInputBinding.buttonNumberKey);
    });

    test('actionKey', () {
      expectExactLiteralInSwift(AppInputBinding.actionKey);
    });

    test('actionTypeKey', () {
      expectExactLiteralInSwift(AppInputBinding.actionTypeKey);
    });

    test('dragScrollType', () {
      expectExactLiteralInSwift(AppInputBinding.dragScrollType);
    });

    test('hotkeyType', () {
      expectExactLiteralInSwift(AppInputBinding.hotkeyType);
    });

    test('directionKey', () {
      expectExactLiteralInSwift(AppInputBinding.directionKey);
    });

    test('sensitivityKey', () {
      expectExactLiteralInSwift(AppInputBinding.sensitivityKey);
    });

    test('keyCodeKey', () {
      expectExactLiteralInSwift(AppInputBinding.keyCodeKey);
    });

    test('modifiersKey', () {
      expectExactLiteralInSwift(AppInputBinding.modifiersKey);
    });
  });
}

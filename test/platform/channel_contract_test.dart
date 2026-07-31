// Dart 與 Swift method channel 契約字面守衛（ticket 1.4.0-W2-009）。
//
// 問題：Dart 側常數（lib/app_constants.dart）與 Swift 側
// macos/Runner/MainFlutterWindow.swift 各自宣告同一組 channel 名 /
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
// 額外成本。input_binding 則不納入：其 Swift 側除 channelName 外，另有
// 5 個方法字面（queryPermission / requestPermission / updateBindings /
// beginCaptureButton / endCaptureButton）與多個資料模型 JSON 鍵
// （buttonNumber / action / type 等）交錯在同一組字串常數命名空間，
// 何者屬「跨越 channel 邊界必須守衛」、何者屬「純 Dart 內部序列化鍵」
// 需先梳理才能精準斷言，屬既有技術債（見票 how 段與 Solution），不在
// 本票必要範圍內硬做。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:screen_clock/app_constants.dart';

void main() {
  // 取得專案根目錄下 Swift 檔案內容：測試以 flutter test 執行時，
  // 工作目錄固定為專案根目錄，故用相對路徑組出絕對路徑，不依賴
  // Swift toolchain 或建置產物。不引入 package:path（非本專案既有
  // 直接依賴），改以 dart:io 內建 path 串接。
  final String swiftFilePath =
      '${Directory.current.path}/macos/Runner/MainFlutterWindow.swift';
  late String swiftSource;

  setUpAll(() {
    swiftSource = File(swiftFilePath).readAsStringSync();
  });

  // 斷言 [literal] 以完整雙引號字串字面（`"literal"`）出現在 Swift
  // 原始碼中，避免子字串包含造成的漏判（見檔頭說明）。
  void expectExactLiteralInSwift(String literal) {
    expect(swiftSource, contains('"$literal"'));
  }

  group('AppCursorLocator 字面須存在於 Swift 端', () {
    test('channelName', () {
      expectExactLiteralInSwift(AppCursorLocator.channelName);
    });

    test('playMethod', () {
      expectExactLiteralInSwift(AppCursorLocator.playMethod);
    });

    test('durationMsArgKey', () {
      expectExactLiteralInSwift(AppCursorLocator.durationMsArgKey);
    });

    test('tintArgbArgKey', () {
      expectExactLiteralInSwift(AppCursorLocator.tintArgbArgKey);
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
}

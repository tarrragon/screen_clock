#!/usr/bin/env bash
# 1.4.0-W2-033：統一測試執行入口 — flutter test（Dart）+ xcodebuild test（Swift/RunnerTests）
#
# 涵蓋範圍：
#   1. Dart 側單元/widget/整合測試（flutter test）
#   2. Swift 側 XCTest（xcodebuild test -scheme Runner，Runner scheme 的 TestAction
#      已固定綁定 RunnerTests target，不需額外 -only-testing）
#
# 兩段皆會完整執行、不因前段失敗而跳過後段：目的是取得完整失敗全貌（哪些 Dart 測試
# 掛了、哪些 Swift 測試掛了），而非「Dart 先掛就不知道 Swift 側狀態」。任一段失敗，
# 整體視為失敗（exit code 合併）。
#
# 已知限制（1.4.0-W2-033 acceptance 3，機制面評估，非實測排除）：
#   RunnerTests 目前僅含純函式判定測試（來源 1.4.0-W2-006.1，CursorScreenLocatorTests，
#   不啟動宿主 app、不觸發輔助使用權限彈窗，本腳本本次執行已實測確認）。
#   1.4.0-W2-006.2 若加入 app-hosted 測試群組（啟動 MainFlutterWindow 進而註冊
#   CGEventTap），該群組尚未存在，無人值守執行時是否彈出權限對話框而阻塞，本腳本
#   無法提前實測，只能預留因應：屆時可在下方 XCODEBUILD_TEST_ARGS 加入
#   -skip-testing:RunnerTests/<AppHostedTestClass>，或另立 CI 專用 test plan
#   排除該群組。本腳本現況不內建排除機制，因該測試群組尚未存在（YAGNI 邊界，非遺漏）。
#
# 用法：
#   scripts/run-tests.sh
#
# 退出碼：
#   0    flutter test 與 xcodebuild test 皆通過
#   非 0 至少一段失敗；若兩段皆失敗，回傳 flutter test 的 exit code

set -uo pipefail
# 不用 -e：兩段測試必須完整跑完並各自記錄結果，不可在第一段失敗時就中止腳本

WORKSPACE="macos/Runner.xcworkspace"
SCHEME="Runner"

echo "=== [1/2] flutter test (Dart) ==="
flutter test
DART_EXIT=$?
if [ "$DART_EXIT" -ne 0 ]; then
  echo "ERROR: flutter test 失敗（exit ${DART_EXIT}）" >&2
fi

echo ""
echo "=== [2/2] xcodebuild test (Swift, RunnerTests) ==="
xcodebuild test \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS'
SWIFT_EXIT=$?
if [ "$SWIFT_EXIT" -ne 0 ]; then
  echo "ERROR: xcodebuild test 失敗（exit ${SWIFT_EXIT}）" >&2
fi

echo ""
if [ "$DART_EXIT" -eq 0 ] && [ "$SWIFT_EXIT" -eq 0 ]; then
  echo "=== 全部測試通過 (flutter test + xcodebuild test) ==="
  exit 0
fi

echo "=== 測試失敗摘要 ===" >&2
if [ "$DART_EXIT" -ne 0 ]; then
  echo "  flutter test:    FAILED (exit $DART_EXIT)" >&2
else
  echo "  flutter test:    passed" >&2
fi
if [ "$SWIFT_EXIT" -ne 0 ]; then
  echo "  xcodebuild test: FAILED (exit $SWIFT_EXIT)" >&2
else
  echo "  xcodebuild test: passed" >&2
fi

if [ "$DART_EXIT" -ne 0 ]; then
  exit "$DART_EXIT"
fi
exit "$SWIFT_EXIT"

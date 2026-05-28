#!/usr/bin/env bash
# v1.0.0-W4-003：codesign + notarize 對 .app bundle
#
# 用法：
#   scripts/sign-and-notarize.sh <path-to-app-bundle>
#
# 必要環境變數：
#   DEVELOPER_ID           例：'Developer ID Application: Your Name (TEAMID)'
#   APPLE_ID               Apple Developer 帳號 email
#   APPLE_APP_PASSWORD     App-specific password
#   APPLE_TEAM_ID          Team ID（10 碼）
#   SKIP_NOTARIZE          非空字串 → 只簽署不送 notarize（dev build）

set -euo pipefail

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Usage: $0 <path-to-app-bundle>" >&2
  exit 1
fi

if [ -z "${DEVELOPER_ID:-}" ]; then
  echo "ERROR: DEVELOPER_ID not set" >&2
  exit 1
fi

echo "=== codesign --deep ==="
codesign \
  --force \
  --options runtime \
  --deep \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  "$APP_PATH"

echo "=== codesign --verify ==="
codesign --verify --deep --verbose=2 "$APP_PATH"

if [ -n "${SKIP_NOTARIZE:-}" ]; then
  echo "=== notarize SKIPPED (SKIP_NOTARIZE set) ==="
  exit 0
fi

if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ] || \
   [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "ERROR: APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID required for notarize" >&2
  exit 1
fi

# notarize 走 .zip 上傳
ZIP_PATH="${APP_PATH}.zip"
echo "=== ditto -c -k -> $ZIP_PATH ==="
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "=== xcrun notarytool submit ==="
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "=== xcrun stapler staple ==="
xcrun stapler staple "$APP_PATH"
rm -f "$ZIP_PATH"

echo "=== notarize done ==="
spctl --assess --type execute --verbose=4 "$APP_PATH"

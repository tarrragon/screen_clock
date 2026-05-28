#!/usr/bin/env bash
# v1.0.0-W4-004：release build + 打包 .dmg
#
# 預期環境變數（簽署 / notarize 需要；只想做 unsigned build 可不設）：
#   DEVELOPER_ID          Apple Developer ID Application 簽署證書名稱
#                         例：'Developer ID Application: Your Name (TEAMID)'
#   APPLE_ID              Apple Developer 帳號電子郵件
#   APPLE_APP_PASSWORD    App-specific password（appleid.apple.com 產生）
#   APPLE_TEAM_ID         Team ID（10 碼）
#   SKIP_NOTARIZE         非空字串 → 跳過 notarize（unsigned dev build）
#
# 用法：
#   scripts/build-release.sh [version]

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="screen_clock"
APP_BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="build/macos/Build/Products/Release"
DIST_DIR="dist"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "=== [1/5] flutter clean + pub get ==="
flutter clean
flutter pub get

echo "=== [2/5] flutter build macos --release ==="
flutter build macos --release

APP_PATH="${BUILD_DIR}/${APP_BUNDLE_NAME}"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: build output not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
DIST_APP="${DIST_DIR}/${APP_BUNDLE_NAME}"
rm -rf "$DIST_APP"
cp -R "$APP_PATH" "$DIST_APP"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "=== [3/5] codesign (Developer ID: $DEVELOPER_ID) ==="
  ./scripts/sign-and-notarize.sh "$DIST_APP"
else
  echo "=== [3/5] codesign SKIPPED (DEVELOPER_ID not set) ==="
fi

echo "=== [4/5] build .dmg ==="
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"

# 建立暫存資料夾並放入 .app + Applications 拖曳捷徑
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$DIST_APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "=== [5/5] done ==="
echo "Output: $DMG_PATH"
echo ""
echo "To verify Gatekeeper:"
echo "  spctl --assess --type execute --verbose=4 \"$DIST_APP\""
echo ""
echo "To install locally:"
echo "  open \"$DMG_PATH\""

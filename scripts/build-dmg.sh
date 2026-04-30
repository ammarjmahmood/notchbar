#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
APP_NAME="${APP_NAME:-NotchBar}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME.dmg}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchbar-dmg-stage.XXXXXX")"

cleanup() {
  rm -rf "$STAGE_DIR"
}

trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/NotchBar.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$STAGE_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH"

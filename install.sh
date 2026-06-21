#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/CursorPopup.xcodeproj"
SCHEME="CursorPopup"
APP_NAME="Cursor Popup"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
INSTALL_DIR="${1:-/Applications}"

echo "Building ${APP_NAME}..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build failed: app bundle not found at $BUILT_APP" >&2
  exit 1
fi

TARGET="$INSTALL_DIR/$APP_NAME.app"
echo "Installing to ${TARGET}..."
mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET"
ditto "$BUILT_APP" "$TARGET"

echo "Done. Press F5 (default) to open the chat box."
echo "Installed: $TARGET"
echo "Launch the app once from Applications if login item registration needs approval."

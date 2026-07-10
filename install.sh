#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/UmbrellaHelper.xcodeproj"
SCHEME="UmbrellaHelper"
APP_NAME="Umbrella Helper"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
INSTALL_DIR="${1:-/Applications}"

echo "Building ${APP_NAME}..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
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

# Re-sign with a STABLE identity so TCC grants (Screen Recording, Microphone)
# survive rebuilds. Ad-hoc signatures change their code hash every build, which
# makes macOS silently drop the existing permission grant (symptom:
# "could not create image from rect"). Using the same Apple Development cert
# keeps the designated requirement constant across rebuilds.
SIGN_IDENTITY="${UMBRELLA_SIGN_IDENTITY:-Apple Development: Kevin Wolfrom (P9P8J8ZVF9)}"
ENTITLEMENTS="$ROOT/UmbrellaHelper/UmbrellaHelper.entitlements"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "Re-signing with stable identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --identifier "com.kevinwolfrom.umbrella" \
    --sign "$SIGN_IDENTITY" \
    "$TARGET"
  codesign --verify --deep --strict --verbose=2 "$TARGET" || {
    echo "Warning: code signature verification reported issues." >&2
  }
else
  echo "Warning: stable signing identity not found; leaving ad-hoc signature." >&2
  echo "         Screen Recording/Microphone grants may reset on each rebuild." >&2
fi

echo "Done. Open Settings to configure shortcuts and features."
echo "Installed: $TARGET"
echo "Launch the app once from Applications if login item registration needs approval."

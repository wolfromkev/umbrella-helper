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
# Prefer full Xcode (beta or stable) over Command Line Tools when present.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
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

# Re-sign with a stable identity when UMBRELLA_SIGN_IDENTITY is set so TCC
# grants (Screen Recording, Microphone) survive rebuilds. Ad-hoc signatures
# change their code hash every build, which makes macOS drop the grant.
SIGN_IDENTITY="${UMBRELLA_SIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/UmbrellaHelper/UmbrellaHelper.entitlements"
if [[ -n "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
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
  if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Warning: UMBRELLA_SIGN_IDENTITY not found in the keychain; leaving ad-hoc signature." >&2
  else
    echo "Leaving ad-hoc signature. Set UMBRELLA_SIGN_IDENTITY to keep TCC grants across rebuilds." >&2
  fi
fi

echo "Done. Open Settings to configure shortcuts and features."
echo "Installed: $TARGET"
echo "Launch the app once from Applications if login item registration needs approval."

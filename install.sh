#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/UmbrellaHelper.xcodeproj"
SCHEME="UmbrellaHelper"
APP_NAME="Umbrella Helper"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
INSTALL_DIR="${1:-/Applications}"
IDENTITY_FILE="$ROOT/.signing-identity"

# Pick a codesigning identity whose designated requirement stays the same
# across rebuilds. Remember the choice so a later certificate does not
# silently replace it and reset TCC.
resolve_sign_identity() {
  local identities saved name
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  identity_is_valid() {
    printf '%s\n' "$identities" | grep -F -q "\"$1\""
  }

  if [[ -n "${UMBRELLA_SIGN_IDENTITY:-}" ]]; then
    if identity_is_valid "$UMBRELLA_SIGN_IDENTITY"; then
      printf '%s\n' "$UMBRELLA_SIGN_IDENTITY"
      return 0
    fi
    echo "Warning: UMBRELLA_SIGN_IDENTITY is not a valid codesigning identity: ${UMBRELLA_SIGN_IDENTITY}" >&2
    return 1
  fi

  if [[ -f "$IDENTITY_FILE" ]]; then
    saved="$(tr -d '\n' < "$IDENTITY_FILE")"
    if [[ -n "$saved" ]] && identity_is_valid "$saved"; then
      printf '%s\n' "$saved"
      return 0
    fi
  fi

  name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "$name" ]]; then
    name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Mac Developer:[^"]*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -z "$name" ]]; then
    name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -n "$name" ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  return 1
}

sign_installed_app() {
  local target="$1"
  local identity entitlements
  entitlements="$ROOT/UmbrellaHelper/UmbrellaHelper.entitlements"

  if ! identity="$(resolve_sign_identity)"; then
    echo "Warning: no stable codesigning identity found. Leaving the ad-hoc signature, so macOS will ask for Screen Recording, Microphone, and Accessibility again after the next rebuild." >&2
    echo "Install an Apple Development certificate in Xcode, or set UMBRELLA_SIGN_IDENTITY." >&2
    return 0
  fi

  printf '%s\n' "$identity" > "$IDENTITY_FILE"
  echo "Signing with stable identity: $identity"
  codesign --force --deep --options runtime \
    --entitlements "$entitlements" \
    --identifier "com.kevinwolfrom.umbrella" \
    --sign "$identity" \
    "$target"
  codesign --verify --deep --strict "$target"
  codesign -dv "$target" 2>&1 | awk -F= '/^TeamIdentifier=|^Signature=/{ print }'
}

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

# Ad-hoc signatures change every build, so macOS drops Screen Recording,
# Microphone, and Accessibility. A stable keychain identity keeps those grants.
sign_installed_app "$TARGET"

echo "Done. Open Settings to configure shortcuts and features."
echo "Installed: $TARGET"
echo "Launch the app once from Applications if login item registration needs approval."

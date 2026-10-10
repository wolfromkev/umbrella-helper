#!/usr/bin/env bash
# Build a Release app and pack it into a DMG for another Mac.
# The other Mac does not need Xcode. First launch needs one Gatekeeper approval.
# Usage: ./make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/UmbrellaHelper.xcodeproj"
SCHEME="UmbrellaHelper"
APP_NAME="Umbrella Helper"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
ENTITLEMENTS="$ROOT/UmbrellaHelper/UmbrellaHelper.entitlements"
STAGING=""

cleanup() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

build_release() {
  local archs="$1"
  echo "Building ${APP_NAME} (${archs})..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="$archs" \
    build
}

if ! build_release "arm64 x86_64"; then
  echo "Universal build failed. Building for this Mac (arm64) only..." >&2
  build_release "arm64"
fi

BUILT_APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build failed: app bundle not found at $BUILT_APP" >&2
  exit 1
fi

echo "Signing for another Mac (ad-hoc). An Apple Development certificate is not trusted off this Mac."
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier "com.kevinwolfrom.umbrella" \
  --sign - \
  "$BUILT_APP"
codesign --verify --deep --strict "$BUILT_APP"

EXECUTABLE="$BUILT_APP/Contents/MacOS/${APP_NAME}"
echo "Architectures: $(lipo -archs "$EXECUTABLE")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
DMG="$BUILD_DIR/Umbrella Helper ${VERSION}.dmg"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/umbrella-dmg.XXXXXX")"
ditto "$BUILT_APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me.txt" <<'EOF'
Umbrella Helper

1. Drag Umbrella Helper onto the Applications folder.
2. Eject this disk image.
3. In Applications, right-click Umbrella Helper and choose Open, then Open again.
   macOS blocks apps that did not come from the App Store the first time you open them.
4. If macOS says the app is damaged, open Terminal and run:

   xattr -cr "/Applications/Umbrella Helper.app"

   Then right-click the app and choose Open again.
5. Grant Screen Recording when asked (and Microphone if you record audio).

Requires macOS 14 or later. No Xcode needed.
EOF

mkdir -p "$BUILD_DIR"
rm -f "$DMG"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --format UDZO \
    --volumeName "Umbrella Helper" \
    "$STAGING" \
    "$DMG"
else
  hdiutil create \
    -volname "Umbrella Helper" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"
fi

STABLE="$BUILD_DIR/Umbrella-Helper.dmg"
cp -f "$DMG" "$STABLE"

echo ""
echo "DMG ready: $DMG"
echo "GitHub asset: $STABLE"
echo "Copy that file to the other Mac, open it, and drag the app to Applications."
echo "The first open needs the steps in Read Me.txt. Screen Recording must be granted again on that Mac."

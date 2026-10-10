#!/usr/bin/env bash
# Regenerate the app icon, menu-bar artwork stays in IconArtwork.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

OUT="$(mktemp -d)/umbrella-render-icons"
xcrun swiftc -framework AppKit -O -o "$OUT" \
  "$ROOT/UmbrellaHelper/Services/IconArtwork.swift" \
  "$ROOT/branding/render-icons.swift"
"$OUT" "$ROOT"
rm -rf "$(dirname "$OUT")"

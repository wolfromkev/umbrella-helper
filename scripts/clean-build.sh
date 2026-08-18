#!/usr/bin/env bash
# Remove local build caches (Xcode DerivedData) that can grow to hundreds of MB.
# Safe to run anytime; the next build regenerates whatever it needs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"

if [[ -d "$BUILD_DIR" ]]; then
  SIZE="$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)"
  rm -rf "$BUILD_DIR"
  echo "Removed $BUILD_DIR (was ${SIZE:-unknown})."
else
  echo "Nothing to clean: $BUILD_DIR does not exist."
fi

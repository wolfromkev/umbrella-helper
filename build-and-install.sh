#!/usr/bin/env bash
# Build Cursor Popup, install to /Applications, and relaunch.
# Usage: ./build-and-install.sh [--no-launch] [install-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Cursor Popup"
BUNDLE_ID="com.kevinwolfrom.CursorPopup"
LAUNCH_AFTER=true
INSTALL_DIR="/Applications"

for arg in "$@"; do
  case "$arg" in
    --no-launch)
      LAUNCH_AFTER=false
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--no-launch] [install-dir]

  --no-launch   Build and install without opening the app
  install-dir   Destination folder (default: /Applications)

Examples:
  $(basename "$0")
  $(basename "$0") --no-launch
  $(basename "$0") ~/Applications
EOF
      exit 0
      ;;
    *)
      INSTALL_DIR="$arg"
      ;;
  esac
done

quit_running_app() {
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    return 0
  fi

  echo "Quitting ${APP_NAME}..."
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null \
    || osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null \
    || true

  for _ in {1..50}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.1
  done

  echo "Force-quitting ${APP_NAME}..."
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
}

echo "==> Cursor Popup — build and install"
quit_running_app

"$ROOT/install.sh" "$INSTALL_DIR"

TARGET="${INSTALL_DIR%/}/${APP_NAME}.app"
if [[ "$LAUNCH_AFTER" == true ]]; then
  echo "Launching ${TARGET}..."
  open "$TARGET"
fi

echo ""
echo "All set."
echo "  Installed: ${TARGET}"
if [[ "$LAUNCH_AFTER" == true ]]; then
  echo "  App relaunched with the latest build."
else
  echo "  Open from Applications when ready."
fi

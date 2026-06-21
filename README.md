# Cursor Popup

<p align="center">
  <img src="branding/icon-1024.png" alt="Cursor Popup logo" width="128" height="128">
</p>

A native macOS floating chat bar (Claude-style) that sends general questions to your **Cursor Chat** workspace via the Cursor `agent` CLI.

## Features

- **Global hotkey:** `F5` toggles the chat box (customizable in Settings)
- **Claude-like UI:** dark pill input bar, orange send button, streaming response below
- **Cursor Chat workspace:** questions run in ask mode against `~/Cursor Chat`
- **New chat per popup:** each time you open the popup, you get a fresh session; follow-ups in the same popup continue that chat
- **Launch at login:** enabled by default on first run
- **Menu bar:** logo icon for Show Popup, Toggle Chat, Settings, Restart, and Quit
- **Shortcuts:** `F5` chat box toggle · `↑↓` browse chat history
- **Response modes (Settings):**
  - **Expand below input bar** — default; replies stream under the pill
  - **Floating chat window** — opens a separate draggable chat panel (bottom-right) with full message history and follow-ups

## Requirements

- macOS 13+
- Cursor agent CLI (`agent`) installed and logged in (`agent login`)
- Xcode (to build)

## Install

```bash
cd "~/path/to/umbrella-helper"
chmod +x install.sh
./install.sh
```

This builds the app, copies it to `/Applications/Cursor Popup.app`, and registers launch at login.

## Usage

1. Press **F5** (or your configured chat box shortcut) anywhere to open the chat box
2. Type your question and press **Return** or click the arrow button
3. Press **Escape** to dismiss
4. Open **Settings** from the menu bar logo to change the workspace path or toggle launch at login

## Branding

Open-source-ready assets live in `branding/`:

| File | Use |
|------|-----|
| `logo.svg` | README, docs, website |
| `icon-1024.png` | App Store–style master icon |

The in-app mark uses the same pill + orange send-button motif as the UI.

## How it works

The app spawns the Cursor agent in headless ask mode:

```bash
agent -p --mode ask --workspace "~/Cursor Chat" \
  --trust --approve-mcps --output-format stream-json --stream-partial-output "your question"
```

Your hub rules in `.cursor/rules/hub.mdc` and `instructions.md` apply automatically. Topic subfolders (Business, Karabiner Scripts, etc.) are available when questions relate to them.

## Development

Open `CursorPopup.xcodeproj` in Xcode, or run:

```bash
xcodebuild -project CursorPopup.xcodeproj -scheme CursorPopup -configuration Debug build
```

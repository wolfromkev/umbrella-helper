# Cursor Popup

<p align="center">
  <img src="branding/icon-1024.png" alt="Cursor Popup logo" width="128" height="128">
</p>

A native macOS menu bar app that opens a floating chat bar and sends prompts to the **Cursor `agent` CLI** in ask mode against a workspace folder you choose.

> **Disclaimer:** Unofficial companion app. Not affiliated with or endorsed by Cursor or Anysphere. “Cursor” is a trademark of its respective owner.

## Features

- **Global hotkey:** `F5` opens Cursor's Agents chat window (customizable in Settings)
- **Floating or inline chat:** stream replies in a separate panel or below the input bar
- **Workspace folders:** point at any project directory; use `←` / `→` in the chat bar to switch
- **Chat history:** `↑` / `↓` browse past sessions (loaded from Cursor agent transcripts)
- **Optional Notion quick task:** `F4` opens a compact task capture popup (integration token + database ID in Settings)
- **Menu bar:** show popup, toggle chat, settings, restart, quit
- **Markdown replies:** assistant messages render markdown; CLI status lines are hidden while thinking

## Requirements

- macOS 13 (Ventura) or later
- [Cursor](https://cursor.com) with the **`agent` CLI** installed and logged in (`agent login`)
- Xcode (to build from source)

## Install

```bash
git clone <your-repo-url>
cd CursorPopup
chmod +x install.sh
./install.sh
```

Or build, install, and relaunch in one step:

```bash
./build-and-install.sh
```

The script builds a Release app, copies it to `/Applications/Cursor Popup.app`, and uses ad-hoc code signing. On first launch, macOS may block an unsigned build — right-click the app → **Open**, or allow it in **Privacy & Security**.

## First-time setup

1. Launch **Cursor Popup** from Applications.
2. Open **Settings** (gear in the chat bar or menu bar icon).
3. Under **Workspace**, click **Add folder…** and choose the project directory you want the agent to use.
4. Under **Permissions**, enable **Accessibility** for Cursor Popup (needed for popup placement and click-outside dismiss).
5. *(Optional)* Under **Notion**, add an [integration token](https://www.notion.so/my-integrations) and your tasks database ID. See [docs/NOTION.md](docs/NOTION.md).

Default shortcuts: **F4** Notion task · **⌘⇧N** new popup chat (Cursor chat disabled by default; all configurable in Settings).

## Usage

1. Press **F5** (or your Cursor chat shortcut) to open Cursor's Agents window, or use **Toggle popup chat** from the menu bar for the built-in chat box.
2. Type a question and press **Return**, or click the send button.
3. Press **Escape** to dismiss.
4. Use **↑** / **↓** for chat history and **←** / **→** to change workspace when multiple folders are configured.

## How it works

The app runs the Cursor agent CLI in headless ask mode, for example:

```bash
agent -p --mode ask --workspace "/path/to/your/project" \
  --trust --approve-mcps --output-format stream-json --stream-partial-output "your question"
```

Chat history is read from Cursor’s agent transcript files under `~/.cursor/projects/<project-slug>/agent-transcripts/`. Prompts and replies go through the local `agent` process; optional Notion tasks call the Notion API when configured.

## Branding

Open-source assets live in `branding/`:

| File | Use |
|------|-----|
| `logo.svg` | README, docs |
| `icon-1024.png` | App icon master |

## Development

Open `CursorPopup.xcodeproj` in Xcode, or:

```bash
xcodebuild -project CursorPopup.xcodeproj -scheme CursorPopup -configuration Debug build
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Before your first public GitHub push, run [scripts/pre-publish-check.sh](scripts/pre-publish-check.sh) and read [docs/PUBLISHING.md](docs/PUBLISHING.md).

## License

MIT — see [LICENSE](LICENSE).

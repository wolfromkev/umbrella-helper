# Umbrella Helper

<p align="center">
  <img src="branding/icon-1024.png" alt="Umbrella Helper logo" width="128" height="128">
</p>

A native macOS menu bar app for quick Notion tasks, screen capture/recording, display warmth/brightness (including Film Mode), and Neewer light control via NeewerLite.

## Features

- **Notion quick task:** global hotkey (default `F4`) opens a compact task popup
- **SimpleSnip:** area / window / full-screen screenshots, area recording, and OCR text copy
- **Brightness:** warmth + brightness controls, presets, Film Mode (dims external displays), optional auto schedule
- **Neewer light:** menu-bar controls for a NeewerLite-connected light (localhost API)
- **Menu bar:** click for controls; right-click for Settings / Restart / Quit
- **Launch at login** and customizable global hotkeys

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 27 (or Xcode 26 on macOS Tahoe) to build from source
- Optional: **NeewerLite** running locally for light control
- Optional: Notion integration for the task popup — see [docs/NOTION.md](docs/NOTION.md)

## Install

```bash
git clone https://github.com/wolfromkev/umbrella-helper.git
cd umbrella-helper
chmod +x install.sh
./install.sh
```

Or build, install, and relaunch:

```bash
./build-and-install.sh
```

The script builds a Release app, copies it to `/Applications/Umbrella Helper.app`, and uses ad-hoc code signing. On first launch, macOS may block an unsigned build — right-click the app → **Open**, or allow it in **Privacy & Security**.

## First-time setup

1. Launch **Umbrella Helper** from Applications.
2. Open **Settings** (menu bar → right-click → Settings, or `⌘,`).
3. Under **Permissions**, grant **Screen Recording** (and Microphone if you record with mic).
4. *(Optional)* Under **Notion**, add an [integration token](https://www.notion.so/my-integrations) and tasks database ID. See [docs/NOTION.md](docs/NOTION.md).
5. *(Optional)* Start **NeewerLite** if you use the light controls.

Default shortcuts (all configurable): **F4** Notion · **⌘⇧S** area snip · **⌘⇧W** window · **⌘⇧A** full screen · **⌘⇧R** record · **⌘⇧T** text OCR · **F1/F2** brightness · **⇧F1/⇧F2** warmth.

## Branding

Open-source assets live in `branding/`:

| File | Use |
|------|-----|
| `logo.svg` | README, docs |
| `icon-1024.png` | App icon master |

## License

MIT — see [LICENSE](LICENSE).

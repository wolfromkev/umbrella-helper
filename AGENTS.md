# AGENTS.md — Umbrella Helper

## Stack
- Native macOS 14+ menu-bar app (SwiftUI + AppKit)
- Xcode project: `UmbrellaHelper.xcodeproj`
- Bundle ID: `com.kevinwolfrom.umbrella`

## Verify
- Build in Xcode (scheme **UmbrellaHelper**), or `./build-and-install.sh`
- Manual smoke: Notion popup, area snip, menu-bar brightness/Neewer, Film Mode toggle + quit restore

## Layout
- `UmbrellaHelper/AppModel.swift` — app shell, hotkeys, Notion panel orchestration
- `UmbrellaHelper/Features/` — Brightness, Neewer, SimpleSnip (+ recorder/overlays)
- `UmbrellaHelper/Services/` — Keychain, Notion API, panels, menu bar
- `UmbrellaHelper/Views/` — Settings, Notion UI, menu controls

## Anti-patterns
- Do not put Cursor `agent` CLI / chat flows back without updating README + ROADMAP
- Do not delete Keychain items before a successful write/read-back
- Do not dismiss the Notion panel before create succeeds (keep draft on failure)
- Do not fall back to `lights.first` when the named Neewer light is missing
- Do not block the menu-bar popover on NeewerLite HTTP — show first, refresh in background
- Prefer splitting Features further over growing `AppModel.swift` again

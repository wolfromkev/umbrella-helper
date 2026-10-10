# AGENTS.md — Umbrella Helper

## Stack
- Native macOS 14+ menu-bar app (SwiftUI + AppKit)
- Xcode project: `UmbrellaHelper.xcodeproj`
- Bundle ID: `com.kevinwolfrom.umbrella`

## Verify
- Build in Xcode (scheme **UmbrellaHelper**), or `./build-and-install.sh`
- Manual smoke: area snip, menu-bar brightness, Film Mode toggle + quit restore

## Layout
- `UmbrellaHelper/AppModel.swift` — app shell, hotkeys, feature ownership
- `UmbrellaHelper/Features/` — Brightness, SimpleSnip (+ recorder/overlays)
- `UmbrellaHelper/Services/` — panels, menu bar, permissions
- `UmbrellaHelper/Views/` — Settings and menu controls

## Anti-patterns
- Do not put Cursor `agent` CLI / chat flows back without updating README + ROADMAP
- Prefer splitting Features further over growing `AppModel.swift` again

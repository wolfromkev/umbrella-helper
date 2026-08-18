# ROADMAP

**What:** macOS menu-bar helper for Notion tasks, SimpleSnip, display brightness/Film Mode, and NeewerLite lights.

## Next
1. Optional: split SimpleSnip overlays/recorder out of `UmbrellaSimpleSnipFeature.swift`
2. Optional: wire automated `xcodebuild` once full Xcode is available in CI
3. Optional: notarized release packaging (see `docs/PUBLISHING.md`)

## Decisions
- Localhost-only personal tool — no cloud backend
- Notion token in Keychain; database ID in UserDefaults
- NeewerLite via `http://localhost:18486` (exact light name `NEEWER-GL1 PRO`)
- Film Mode dirty-flag: unclean exit restores gamma and leaves Film Mode off

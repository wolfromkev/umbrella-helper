# ROADMAP

**What:** macOS menu-bar helper for SimpleSnip and display brightness/Film Mode.

## Next
1. Optional: split SimpleSnip overlays/recorder out of `UmbrellaSimpleSnipFeature.swift`
2. Optional: wire automated `xcodebuild` once full Xcode is available in CI
3. Optional: notarize the GitHub DMG so the first open does not need a right-click (see `docs/PUBLISHING.md`)

## Decisions
- Localhost-only personal tool — no cloud backend
- Local installs sign with a stable keychain identity so Screen Recording, Microphone, and Accessibility survive rebuilds
- Film Mode dirty-flag: unclean exit restores gamma and leaves Film Mode off
- Auto brightness follows a sine curve (night floor → midday peak → night) between sunrise/sunset; twilight minutes pad the rise/fall; location can replace manual sun times

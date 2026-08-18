# Contributing

Thanks for your interest in Umbrella Helper.

## Build

```bash
./install.sh
# or
./build-and-install.sh
```

Open `UmbrellaHelper.xcodeproj` in Xcode for debugging. Read `AGENTS.md` and `ROADMAP.md` before larger changes.

## Pull requests

- Keep changes focused; match existing Swift and SwiftUI style.
- Test on macOS 14+: Notion popup, snip/record, brightness/Film Mode, Neewer menu controls (if NeewerLite is running).
- Do not commit tokens, database IDs, or personal paths.

## Before publishing forks

Change `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project if you distribute builds under your own name. Run `./scripts/pre-publish-check.sh` to catch accidental secrets.

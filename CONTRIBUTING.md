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
- Test on macOS 14+: snip/record and brightness/Film Mode.
- Do not commit tokens or personal paths.

## Before publishing forks

Change `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project if you distribute builds under your own name. Run `./scripts/pre-publish-check.sh` to catch accidental secrets.

# Contributing

Thanks for your interest in Umbrella Helper.

## Build

```bash
./install.sh
# or
./build-and-install.sh
```

Open `UmbrellaHelper.xcodeproj` in Xcode for debugging.

## Pull requests

- Keep changes focused; match existing Swift and SwiftUI style in the file you edit.
- Test on macOS 13+ with a real `agent` CLI login.
- Do not commit tokens, database IDs, personal paths, or `.cursor/` editor rules.

## Before publishing forks

Change `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project if you distribute builds under your own name. Run `./scripts/pre-publish-check.sh` to catch accidental secrets.

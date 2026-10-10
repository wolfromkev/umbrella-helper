# Publishing

Scan the working tree before you push:

```bash
./scripts/pre-publish-check.sh
```

Do not commit:

- Home directory paths
- API keys
- Cursor audit files under `.cursor/`

Local-only data (never in git):

| Data | Where it lives |
|------|----------------|
| Hotkeys, folders, presets | UserDefaults |

Forks that distribute their own build should change `PRODUCT_BUNDLE_IDENTIFIER` and set `UMBRELLA_SIGN_IDENTITY` when installing.

`install.sh` signs with a stable keychain identity so privacy permissions survive rebuilds. It prefers `UMBRELLA_SIGN_IDENTITY`, then the identity saved in `.signing-identity`, then Apple Development. Ad-hoc signing is only the fallback when no certificate is available.

## GitHub download

Ship the installable app as a Release asset named `Umbrella-Helper.dmg`. That name matches the README download link. Do not commit the DMG into the repository.

```bash
./make-dmg.sh
gh release create "v<version>" "build/Umbrella-Helper.dmg" \
  --title "Umbrella Helper <version>" \
  --notes "See the README install steps."
```

Bump `MARKETING_VERSION` on the Release configuration before cutting the release. `Info.plist` reads that setting. Check for Updates compares that version with the GitHub tag, so a new disk image published under the same version is treated as already installed.

`./make-dmg.sh` writes `build/Umbrella-Helper.dmg` for that upload, plus a versioned copy next to it. It ad-hoc signs the app so it can launch on a Mac that does not have this machine’s Apple Development certificate. The first open on another Mac still needs the right-click Open step in the README. Notarization needs a Developer ID Application certificate, which this project does not use yet.

## Mac App Store

The `AppStore` configuration is a separate sandboxed build. Release, `install.sh`, and the GitHub disk image stay unsandboxed and keep Check for Updates. Do not install the App Store build over `/Applications` on a machine that uses the GitHub app: both use `com.kevinwolfrom.umbrella`.

Archive with the shared scheme **UmbrellaHelper App Store**. `DEVELOPMENT_TEAM` stays empty in the project; pass the team when signing the archive. [`ExportOptions-AppStore.plist`](../ExportOptions-AppStore.plist) uploads with `method` = `app-store-connect`.

```bash
xcodebuild -project UmbrellaHelper.xcodeproj \
  -scheme "UmbrellaHelper App Store" \
  -configuration AppStore \
  -archivePath build/UmbrellaHelper-AppStore.xcarchive \
  DEVELOPMENT_TEAM=RTKZ7MF6UZ \
  archive

xcodebuild -exportArchive \
  -archivePath build/UmbrellaHelper-AppStore.xcarchive \
  -exportPath build/AppStoreExport \
  -exportOptionsPlist ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

Create the Mac app in App Store Connect for `com.kevinwolfrom.umbrella` before that export. Until that record exists, export stops with “App record … not found.” Screenshots, the description, privacy answers, and submitting for review stay in App Store Connect.

The store build saves screenshots under Pictures and recordings under Movies until a folder is chosen. Chosen folders are security-scoped bookmarks. It has no GitHub updater. Full-screen snip uses the in-app capture path.

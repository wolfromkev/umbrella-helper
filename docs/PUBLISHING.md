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

`./make-dmg.sh` writes `build/Umbrella-Helper.dmg` for that upload, plus a versioned copy next to it. It ad-hoc signs the app so it can launch on a Mac that does not have this machine’s Apple Development certificate. The first open on another Mac still needs the right-click Open step in the README. Notarization needs a Developer ID Application certificate, which this project does not use yet.

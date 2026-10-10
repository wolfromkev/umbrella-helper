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

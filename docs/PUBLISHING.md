# Publishing to GitHub

Use this checklist before making the repository **public**.

## 1. Scan the working tree

```bash
./scripts/pre-publish-check.sh
```

Fix anything it reports. Common items:

- Home directory paths (paths under your Mac user folder)
- Notion database IDs (32-character hex)
- Integration tokens or API keys
- Personal project names in defaults or README

## 2. Clean git history (if needed)

If a personal path, Notion ID, or token ever landed in a commit, scrub history **before** (or right after) going public — `main` alone is not enough; old SHAs stay cloneable.

Pick one approach before the first public push:

### Option A — Fresh history (simplest)

Creates one clean initial commit with no old secrets in history:

```bash
git checkout --orphan public-main
git add -A
git commit -m "Initial public release"
git branch -M main
# When ready: git push -u origin main --force  # only if repo was never public
```

Keep your old branch locally if you want: `git branch private-backup main` before rewriting.

### Option B — Rewrite existing history

Replace strings across all commits (install [git-filter-repo](https://github.com/newren/git-filter-repo) first):

```bash
git filter-repo --replace-text <(cat <<'EOF'
literal:OLD_WORKSPACE_PATH==>/path/to/your/workspace
literal:OLD_NOTION_DATABASE_ID===REDACTED
EOF
)
```

Adjust patterns to match anything `./scripts/pre-publish-check.sh` finds in **git history** (use `git log -p -S 'pattern'` to search).

### Option C — New empty GitHub repo

Push only after Option A or B. Do not push first and scrub later — GitHub retains reachable objects for a while.

## 3. What stays local (never in git)

| Data | Where it lives |
|------|----------------|
| Notion integration token | macOS Keychain |
| Workspace folders, hotkeys | UserDefaults |
| Chat content | Cursor agent transcripts under `~/.cursor/projects/` |

## 4. What is OK in the repo

- Bundle ID `com.kevinwolfrom.umbrella` (author identifier; forks can change it)
- Generic build scripts and MIT license with your name

## 5. After push

- Add a short **Disclaimer** (already in README) about Cursor trademark.
- Optional: add screenshots under `docs/screenshots/` and link from the README.

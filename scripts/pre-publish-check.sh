#!/usr/bin/env bash
# Scan tracked and common source files for values that should not go public.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

issues=0

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  issues=$((issues + 1))
}

pass() {
  echo -e "${GREEN}OK${NC}: $1"
}

echo "Pre-publish check — $(basename "$ROOT")"
echo ""

# Patterns that often indicate personal or secret data
PATTERNS=(
  '/Users/[^/[:space:]"'\''`]+'
  'secret_[A-Za-z0-9]{20,}'
  'ntn_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  '[redacted-notion-id]'
  'kevinwolfrom/Cursor Chat'
  'project-obsidian-vault'
)

SEARCH_PATHS=(
  README.md
  CONTRIBUTING.md
  LICENSE
  install.sh
  build-and-install.sh
  UmbrellaHelper
  docs
)

for pattern in "${PATTERNS[@]}"; do
  if rg -n --glob '!.git' --glob '!build/**' --glob '!DerivedData/**' --glob '!scripts/**' "$pattern" "${SEARCH_PATHS[@]}" 2>/dev/null; then
    fail "Matched pattern: $pattern"
  else
    pass "No match for: $pattern"
  fi
done

echo ""

if git ls-files --error-unmatch .cursor 2>/dev/null; then
  fail ".cursor/ is tracked — remove from git and add to .gitignore"
elif git ls-files '.cursor/*' 2>/dev/null | grep -q .; then
  fail ".cursor/ files are tracked: $(git ls-files '.cursor/*' | tr '\n' ' ')"
else
  pass ".cursor/ not tracked"
fi

echo ""
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}Working tree looks clean.${NC}"
  echo "Still read docs/PUBLISHING.md — old commits may contain scrubbed values."
  exit 0
else
  echo -e "${RED}$issues issue(s) found.${NC} Fix before making the repo public."
  exit 1
fi

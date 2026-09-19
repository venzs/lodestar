#!/usr/bin/env bash
# Verify the suite: regenerate the Forever API surface from Blizzard's UI source, then run
# luacheck, the API existence check and the stub smoke test.
#   tools/check.sh              full run
#   tools/check.sh --fetch-only just (re)generate tools/wow-api
# Needs: git, python3, lua5.1, luacheck. On Windows use Git Bash or WSL.
set -euo pipefail
cd "$(dirname "$0")/.."
BRANCH="${WOW_UI_BRANCH:-forever}"
CACHE="${WOW_UI_CACHE:-$HOME/.cache/wow-ui-source-$BRANCH}"

if [ ! -d "$CACHE/.git" ]; then
  echo "Cloning Gethe/wow-ui-source ($BRANCH) into $CACHE ..."
  git clone -q --depth 1 --branch "$BRANCH" https://github.com/Gethe/wow-ui-source "$CACHE"
else
  git -C "$CACHE" pull -q --ff-only || true
fi
echo "UI source version: $(cat "$CACHE/version.txt")"
python3 tools/extract_api.py "$CACHE/Interface" tools/wow-api camelot

if [ "${1:-}" = "--fetch-only" ]; then exit 0; fi

echo "--- luacheck ---"
luacheck . --no-color -q
echo "--- apicheck ---"
python3 tools/apicheck.py .
echo "--- tocs ---"
python3 tools/check_tocs.py
echo "--- events ---"
python3 tools/check_events.py
echo "--- protected calls ---"
python3 tools/check_protected.py
echo "--- guides ---"
python3 tools/router/lint_guides.py
echo "--- smoke ---"
lua5.1 tools/smoke/run.lua
echo "--- persistence across a logout ---"
lua5.1 tools/smoke/persist.lua

#!/usr/bin/env bash
# Re-pull All The Things' Camelot (Forever) database and rebuild Lodestar_Guide/Data/ATT.lua.
#
#     tools/att/refresh.sh
#
# ATT is crowd-sourced and moves fast on new content, so this is the cheapest coverage Lodestar
# gets: every run picks up whatever the rest of the world mapped since the last one, without anyone
# here walking a step. Worth running weekly through the beta and daily around launch.
#
# Only raw.githubusercontent.com is reachable from here (the API and codeload are blocked), so the
# file list comes from ATT's own Database.xml manifest rather than from a directory listing.
#
# ATT is MIT licensed; the notice ships in Lodestar_Guide/Data/LICENSE-ATT.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW="https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/master"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> manifest"
curl -fsS --max-time 30 "$RAW/db/Camelot/Database.xml" -o "$WORK/Database.xml"

# <Script file="Categories/Zones.lua"/> -> Categories/Zones.lua
FILES=$(grep -o 'file="[^"]*"' "$WORK/Database.xml" | sed 's/file="//;s/"$//')
if [ -z "$FILES" ]; then
  echo "no files in the manifest -- ATT may have restructured db/Camelot/" >&2
  exit 1
fi

echo "==> fetching $(echo "$FILES" | wc -l) file(s)"
mkdir -p "$WORK/db"
for f in $FILES; do
  # LocalizationDB is UI strings (menu labels, credits), not world data, and it builds them by
  # concatenating tables the converter has no reason to model. Nothing in it places a quest.
  case "$f" in LocalizationDB.lua) echo "    (skipping LocalizationDB.lua -- UI strings)"; continue ;; esac
  out="$WORK/db/$(echo "$f" | tr '/' '_')"
  if curl -fsS --max-time 120 "$RAW/db/Camelot/$f" -o "$out"; then
    printf '    %-44s %8s bytes\n' "$f" "$(stat -c%s "$out")"
  else
    echo "    $f -- FAILED" >&2
  fi
done

echo "==> converting"
mkdir -p "$ROOT/data/att"
lua5.1 "$ROOT/tools/att/att_to_json.lua" "$WORK"/db/*.lua > "$ROOT/data/att/att-camelot.json"

echo "==> importing"
python3 "$ROOT/tools/att/import_att.py" "$ROOT/data/att/att-camelot.json"

echo "==> verifying"
cd "$ROOT"
luacheck Lodestar_Guide/Data/ATT.lua >/dev/null && echo "    luacheck OK"
lua5.1 tools/smoke/run.lua 2>&1 | tail -1
echo
echo "Done. Review the diff on Lodestar_Guide/Data/ATT.lua before committing."

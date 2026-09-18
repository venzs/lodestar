#!/usr/bin/env bash
# Download the Vanilla pfQuest database files that tools/pfquest/import.py needs into tools/pfquest/src/
# (gitignored). Only raw.githubusercontent.com is used; the GitHub API and HTML pages are not needed.
#
#   tools/pfquest/fetch.sh            fetch from master
#   PFQUEST_REF=<sha|tag> tools/pfquest/fetch.sh
#
# pfQuest is MIT licensed, Copyright (c) 2017-2021 Eric Mauser (Shagu) — https://github.com/shagu/pfQuest
# The Vanilla database is generated from VMaNGOS. Only the vanilla files are fetched (no -tbc/-wotlk variants).
set -euo pipefail
cd "$(dirname "$0")"
REF="${PFQUEST_REF:-master}"
BASE="https://raw.githubusercontent.com/shagu/pfQuest/$REF"
OUT="src"
mkdir -p "$OUT/db/enUS"

FILES=(
  LICENSE
  db/quests.lua        # quest id -> lvl/min/race/class/skill/event/pre + start/end/obj lists (U units, O objects, I items, A areatriggers)
  db/units.lua         # creature id -> coords {x, y, areaID, respawn}, lvl "min-max", rnk, fac
  db/objects.lua       # gameobject id -> coords, fac
  db/items.lua         # item id -> U/O drop sources with chance, V vendors, R reference loot ids
  db/refloot.lua       # reference loot id -> U/O sources
  db/areatrigger.lua   # areatrigger id -> coords {x, y, areaID}
  db/zones.lua         # sub-area id -> { parentZone, width, height, centerX, centerY } (percent of parent)
  db/enUS/quests.lua   # quest id -> { T = title, O = objectives, D = description }
  db/enUS/units.lua    # creature names
  db/enUS/objects.lua  # gameobject names
  db/enUS/items.lua    # item names
  db/enUS/zones.lua    # areaID -> zone name (the bridge to uiMapIDs at runtime)
)

for f in "${FILES[@]}"; do
  echo "fetching $f"
  curl -sSf --retry 3 -o "$OUT/$f" "$BASE/$f"
done

{
  echo "repo=https://github.com/shagu/pfQuest"
  echo "ref=$REF"
  echo "fetched=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/VERSION.txt"
echo "done -> $OUT/  (now run: python3 tools/pfquest/import.py)"

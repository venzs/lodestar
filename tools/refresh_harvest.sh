#!/usr/bin/env bash
# Fold a play session's harvest back into the shipped database, and rebuild what depends on it.
#
#   tools/refresh_harvest.sh <SavedVariables/Lodestar_Guide.lua | a pasted export.txt> [more ...]
#
# Both are accepted and told apart by content. Most contributions arrive as a pasted `/lode export`
# string, because that costs the contributor a copy and a paste; a saved-variable file is the fuller
# version for anyone willing to go and find it.
#
# This is the loop that makes the suite better the more anyone plays. A session records NPC
# positions, quest givers and enders, objective spots, flight points and XP; the client writes that
# to disk at logout; this turns it into JSON, merges it with every earlier export into
# Data/Forever.lua, and regenerates the routes that were derived from it.
#
# Exports accumulate in data/beta/ on purpose. The merge is over ALL of them, not just the newest,
# so a position someone recorded in August still counts in September and no single bad session can
# quietly delete what everyone else contributed.
#
# On the beta the client does not appear to hand saved variables back at login, which makes this the
# only way a harvest survives at all -- the file is still written, it just never comes back. Run it
# after a session and the data is safe in the repo rather than in one player's WTF folder.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 1 ]; then
  echo "usage: tools/refresh_harvest.sh <SavedVariables/Lodestar_Guide.lua | pasted-export.txt> [more ...]" >&2
  exit 2
fi

mkdir -p data/beta
stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
n=0
for src in "$@"; do
  if [ ! -f "$src" ]; then
    echo "refresh_harvest: no such file: $src" >&2
    exit 1
  fi
  n=$((n + 1))
  out="data/beta/scan-${stamp}-${n}.json"
  # Two shapes arrive. A saved-variable file is what someone sends when they went and found it; a
  # pasted /lode export is what most people send, because it costs them a copy and a paste and no
  # file browsing at all. Tell them apart by looking, not by asking whoever runs this to remember.
  if head -c 4000 "$src" | grep -q "LODE[0-9]*:"; then
    echo "refresh_harvest: $src looks like a pasted export"
    python3 tools/pfquest/import_paste.py "$src" > "$out"
  else
    lua5.1 tools/pfquest/sv_to_json.lua "$src" > "$out"
  fi
  # Nothing worth keeping: a session that harvested nothing, or a saved-variable file the client
  # handed back empty. A pasted export may legitimately carry no quest links while still carrying
  # NPC positions, so both are checked.
  if ! grep -qE '"(quests|npcs)"' "$out"; then
    echo "refresh_harvest: $src carried no quests; dropping $out"
    rm -f "$out"
    n=$((n - 1))
    continue
  fi
  echo "refresh_harvest: $src -> $out ($(wc -c < "$out") bytes)"
done

if [ "$n" -eq 0 ]; then
  echo "refresh_harvest: nothing new to merge" >&2
  exit 1
fi

echo "--- merging $(ls data/beta/*.json | wc -l) export(s) into Data/Forever.lua ---"
python3 tools/pfquest/merge_scan.py data/beta/*.json

# Regenerate every route that was derived rather than hand-authored. A hand-written guide is left
# alone: the marker is the generator's own header line, so this can never overwrite someone's work.
#
# regen.sh rather than a copy of its loop. The copy that used to live here was subtly different in
# the two ways that mattered: it expanded the --regen-args line unquoted, so every guide whose name
# contains a space -- which is all of them -- reached the generator as mangled arguments and died,
# and it had no else branch, so it printed nothing when that happened. The result was a regeneration
# step that had never once regenerated anything and never said so. Two copies of one job, and the
# second copy was the one missing the rules; that is the third time this project has paid for it.
echo "--- regenerating derived routes ---"
tools/router/regen.sh

echo "--- verifying ---"
python3 tools/router/lint_guides.py
lua5.1 tools/smoke/run.lua
echo "refresh_harvest: done. Review the diff before committing."

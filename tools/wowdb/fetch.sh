#!/usr/bin/env bash
# Pull the client database tables the router needs, for one build, from wago.tools.
#
#   tools/wowdb/fetch.sh [build]        # default: the build tools/check.sh already targets
#
# This is Blizzard's own data for the Forever beta client, which is the authoritative answer to
# questions the community databases can only guess at: how big a map is, where the flight points
# are and what they cost, what a quest of a given level is worth. pfQuest and ATT are fifteen-year-old
# reconstructions of a different client; this is the client we are actually routing on.
#
# The files land in tools/wowdb/src/, which is gitignored -- the same arrangement as
# tools/pfquest/src/. What gets committed is what the importers generate from them.
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD="${1:-1.60.1.69913}"
OUT="tools/wowdb/src"
mkdir -p "$OUT"

# Only the tables something actually reads. QuestObjective and QuestV2CliTask are retail-only and
# 404 on a Classic build, which is why the objective data still comes from pfQuest.
TABLES="UiMap UiMapAssignment TaxiNodes TaxiPath TaxiPathNode QuestXP QuestPOIBlob QuestPOIPoint"

echo "build $BUILD"
for t in $TABLES; do
  url="https://wago.tools/db2/$t/csv?build=$BUILD"
  tmp="$(mktemp)"
  if ! curl -sfL -o "$tmp" "$url"; then
    echo "  $t: FAILED to fetch" >&2
    rm -f "$tmp"
    continue
  fi
  # A missing table answers 200 with a JSON error body rather than a 404, so check the content.
  if head -c 40 "$tmp" | grep -q '"errors"'; then
    echo "  $t: not in this build"
    rm -f "$tmp"
    continue
  fi
  mv "$tmp" "$OUT/$t.csv"
  printf '  %-16s %8s bytes  %6s rows\n' "$t" "$(wc -c < "$OUT/$t.csv")" "$(( $(wc -l < "$OUT/$t.csv") - 1 ))"
done
echo "wrote $OUT/"

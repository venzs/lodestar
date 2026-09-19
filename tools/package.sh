#!/usr/bin/env bash
# Build the installable zip, without CI and without a CurseForge account.
#
#   tools/package.sh [version]          # default: the version in Lodestar/Lodestar.toc
#
# The release workflow builds the same thing from a vX.Y.Z tag once the repo has a remote and the
# packager's API keys. This is the version for before that exists: one file to hand to a tester over
# Discord, which is how the first harvests come back.
#
# Structure matters. WoW loads AddOns/<Name>/<Name>.toc, so every addon folder has to sit at the top
# level of the zip -- not nested under a repo folder. Unzipping into Interface/AddOns has to Just
# Work, because a tester who has to move folders around is a tester who does not report back.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -m1 '^## Version:' Lodestar/Lodestar.toc | sed 's/## Version:[[:space:]]*//')}"
# Read the contact out of the addon rather than repeating it here: /lode share prints the same
# string in game, and two copies of an invite link is two chances for one of them to rot.
CONTACT="$(grep -m1 '^Lodestar.CONTACT' Lodestar/Core/Init.lua | sed 's/.*= *"//; s/"$//')"
# The contact has to be something a stranger can ACT on. A Discord server id is not: you cannot
# join a server by its id, and discord.com/channels/<id>/... only resolves for people who are
# already members, so a tester who reads it has nowhere to go. Same for a bare channel name or a
# username with no server. An invite link, an email address or a URL are all actionable; anything
# else is a dead end that would not be discovered until somebody tried to use it.
case "$CONTACT" in
  *"not set yet"*)
    echo "REFUSING TO PACKAGE: Lodestar.CONTACT is still the placeholder." >&2
    echo "  Testers would have nowhere to send their harvest, which is the whole point of the" >&2
    echo "  build. Set it in Lodestar/Core/Init.lua." >&2
    exit 1 ;;
  *discord.gg/*|*discord.com/invite/*|*@*|*http://*|*https://*) ;;
  *)
    echo "REFUSING TO PACKAGE: Lodestar.CONTACT is not something a tester can act on:" >&2
    echo "    $CONTACT" >&2
    echo "  It needs an invite link (discord.gg/...), an email address, or a URL. A Discord" >&2
    echo "  SERVER ID will not do -- nobody can join a server from its id." >&2
    exit 1 ;;
esac
OUT="dist/Lodestar-${VERSION}.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "packaging Lodestar $VERSION"
for dir in Lodestar Lodestar_Leveling Lodestar_Economy Lodestar_UI Lodestar_Guild \
           Lodestar_Guide Lodestar_Guides_Horde Lodestar_Guides_Alliance Lodestar_Character; do
  [ -d "$dir" ] || { echo "missing addon folder: $dir" >&2; exit 1; }
  # No .git, no editor droppings; the Libs are checked in on purpose and must travel.
  # cp rather than rsync: rsync is not on every machine and this needs to run anywhere.
  cp -r "$dir" "$STAGE/"
  find "$STAGE/$dir" \( -name '.*' -o -name '*.bak' \) -exec rm -rf {} + 2>/dev/null || true
  printf '  %-28s %s\n' "$dir" "$(find "$STAGE/$dir" -type f | wc -l) files"
done

cat > "$STAGE/INSTALL.txt" <<TXT
Lodestar $VERSION — a levelling suite for WoW: Forever
=======================================================

INSTALL

  1. Close WoW completely.
  2. Copy all of the Lodestar* folders in this zip into:

         World of Warcraft\\_classic_beta_\\Interface\\AddOns\\

     You should end up with AddOns\\Lodestar\\, AddOns\\Lodestar_Guide\\, and so on --
     NOT AddOns\\Lodestar\\Lodestar\\.
  3. Start WoW. At the character screen, click AddOns and make sure they are enabled.

FIRST RUN

  /lode            every command
  /lode guide      the route window: it picks a route for your race and level
  /lode guide why  what it decided and why, if it lands somewhere odd

HELPING WITH THE DATA
-----------------------------------------------------------------------

Lodestar builds its routes from positions players actually record. Forever's new
zones are not in any public database, so the only way they get covered is people
playing with this installed.

Your session is recorded automatically. To send it back:

  1. Type /lode share in game. It opens a window with these same steps in it,
     which you can select and copy.
  2. Type /reload. The file is only written on /reload or logout, so a copy
     taken before that is stale.
  3. Search your World of Warcraft folder for:  Lodestar_Guide.lua
     (it is under WTF\\Account\\<your account>\\SavedVariables\\ -- searching is
     easier than hunting, because the client will not tell an addon the
     account folder's name)
  4. Send that one file to:

         ${CONTACT}

It contains NPC and object positions, quest ids, titles, objective text, flight
points and XP per level. It does NOT contain your character name, gold, gear,
bags, guild, friends, chat, or anything you typed.

If you would rather not, /lode harvest off turns the recording off entirely and
everything else keeps working. /lode share also has a "remind me" toggle in the
Guide settings if you would rather it never mentioned this again.

KNOWN BETA ISSUE
-----------------------------------------------------------------------

The beta client does not hand addon saved variables back at login -- it writes
them correctly and ignores them on the way in. Lodestar keeps your window
positions and your place in the route in the client's own config so they
survive, but anything else resets each session. That is the client, not the
addon, and it is why sending the file after a session matters.
TXT

mkdir -p dist
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OLDPWD/$OUT" . -x '.*')
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"

# Lodestar

A suite of addons for **World of Warcraft: Forever**. One core, seven modules and guide packs — install what you want.

| Addon | What it does |
|---|---|
| **Lodestar** (required) | Settings panel, module toggles, minimap button, guild/party comms, `/lode` |
| **Lodestar_Leveling** | XP/hour + time-to-level readout with the XP waiting in completed quests ("turn-ins to ding") and a status strip (bag slots, durability, rested %, Well Fed) with bag-space and repair nags; quest auto-accept/turn-in, `/way` waypoints, time-per-level stats |
| **Lodestar_Economy** | Auto-sell greys, auto-repair, account-wide gold ledger, vendor + auction prices in tooltips |
| **Lodestar_UI** | Item/spell/NPC IDs and target-of-target in tooltips, map + minimap coordinates, clickable chat links, timestamps, copy-chat, fast loot |
| **Lodestar_Guild** | Live guild board: who is online, where, what level, who wants a group (`/lode guild`, `/lode lfg`). On realms that restrict addon messages (the Forever beta) it shows the guild roster and `/lode lfg` drafts a guild chat line for you to send |
| **Lodestar_Guide** | Navigation arrow that routes along known roads (learned from where you walk, seeded for the starting zones) with a minimap line to the target; guide window with sync-to-quest-log, speed-run/completionist modes and class trainer reminders; smart mode that lists turn-ins, objectives and pick-ups from the built-in Vanilla database plus what the addon has harvested on Forever; Questie-style quest tooltips on mobs, NPCs and items; a census/harvester (`/lode scan`) that records Forever's new quests and NPCs; a route recorder (`/lode record`) |
| **Lodestar_Guides_Horde** | Guide data pack: Horde routes 1-30 (Deathknell/Tirisfal, Durotar, Mulgore, Silverpine, the Barrens, Hillsbrad, Stonetalon, Ashenvale, Thousand Needles) — drafts from the Vanilla database and the route optimizer, to be verified in play. |
| **Lodestar_Guides_Alliance** | Guide data pack: Alliance routes (Elwynn, Dun Morogh, Teldrassil, Westfall, Loch Modan, Darkshore) — drafts from the Vanilla database and the route optimizer, to be verified in play. |
| **Lodestar_Character** | The character-sheet stats Blizzard hides, in a movable panel beside the character sheet (`/lode character`): melee/ranged/spell hit with miss tables vs +0..+3, crit and haste split, spell power per school, MP5/HP5, attack speed and DPS, weapon skills, enemy miss/crit/crush, block value, armor reduction, item level, durability, XP/rested, talent and Legacy points, PvP rank. It never writes to Blizzard's stats tables — that taints the character frame on Forever |

`/lode` opens settings. `/lode help` lists every command.

## Guides

Guides are plain text registered by a data-pack addon (see `Lodestar_Guides_Horde/Undead_Deathknell.lua`):

```
#guide Horde/Undead 1-5: Deathknell
#faction Horde
#race Undead
#levels 1-5
#next Horde/Undead 5-12: Tirisfal Glades

step
  .goto 18,30.8,66.2
  .accept 3901 >>Accept Rude Awakening from Shadow Priest Sarvis
step
  .goto 18,30.4,68.9
  .complete 364,1 >>Kill Mindless Zombies
step
  .goto 18,30.8,66.2
  .turnin 364
  .xp 3
```

Directives: `.goto map,x,y[,radius]` (map id or zone name), `.path x,y;x,y;...` (road waypoints), `.accept id`,
`.turnin id`, `.complete id[,objective]`, `.buy itemID[,count]`, `.xp level`, `.zone name`, `.train [NPC]`, `.hs name`,
`.fly name`, `.vendor`, `.repair`, `.profession A,B`, `.camp`, `.cook`, `.text >>...`, `.optional [>>reason]`
(completionist mode only), plus `.class` / `.race` / `.item` step filters. Steps auto-advance from the quest log;
goto-only steps complete on arrival. `/lode record start` logs your own play (accepts, objective completions,
turn-ins, hearth binds, trainers, mob levels) and `/lode record export` produces this format.

Useful commands: `/lode guide sync` (re-sync to your quest log), `/lode guide smart`, `/lode guide completionist on|off`,
`/lode quest <id|name>` (look up the database), `/lode scan quests <from> <to>` (quest census), `/lode scan status`,
`/lode trails`, `/lode arrow [auto|guide|waypoint|quest|off]`, `/lode guide diag` (what the client answers per quest).

## Status

Built against the Forever beta (client 1.60.1, Interface 16001). Forever runs the Mainline (retail 12.1.5-era)
addon API with the Midnight-era restrictions, not the Classic Era API; everything here targets that.

## Development

Requirements: git, Python 3, Lua 5.1, luacheck (`apt install lua5.1 lua-check` / `brew install lua@5.1 luacheck`).

```
tools/check.sh          # regenerate the Forever API surface from Blizzard's UI source, then luacheck + apicheck + smoke test
tools/dev-link.cmd      # Windows: junction each addon folder into the beta's Interface\AddOns
```

`tools/check.sh` clones the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)
(Blizzard's own UI code as exported from the beta client), works out which files actually load under the
Forever game type ("Camelot" internally) and writes `tools/wow-api/`. luacheck then flags any global that
doesn't exist in that client, and `tools/apicheck.py` verifies every `C_*` call, event name and `Enum` value
against the generated API docs. `tools/smoke/run.lua` loads the whole suite under a small WoW stub and drives
the main code paths.

### Layout

```
Lodestar/            core addon (Libs/ holds Ace3, LibDataBroker, LibDBIcon)
Lodestar_Leveling/   module addons depend on Lodestar and register with Lodestar:RegisterModule
Lodestar_Economy/
Lodestar_UI/
Lodestar_Guild/
Lodestar_Guide/      guide engine, arrow, trails, harvest, Data/ (Vanilla.lua from pfQuest, ATT.lua from All The Things, Forever.lua from the beta harvest)
Lodestar_Guides_*/   guide packs (text routes)
Lodestar_Character/  character-sheet stats
tools/               dev tooling (not shipped): smoke harness, API extractor, pfquest import, router, trails seeds
data/beta/           LodestarScanDB exports from the beta (JSON), input to tools/pfquest/merge_scan.py
docs/DESIGN.md       architecture, module contract, roadmap
```

### Releasing

Tag `vX.Y.Z` and push the tag. `.github/workflows/release.yml` runs the BigWigs packager, which replaces
`@project-version@` in the TOCs, zips the five folders and publishes to GitHub Releases (and CurseForge /
Wago / WoWInterface once the API-key secrets are set).

## Data sources

`Lodestar_Guide/Data/Vanilla.lua` is generated from the Vanilla database of
[pfQuest](https://github.com/shagu/pfQuest) by Shagu (MIT, Copyright (c) 2017-2021 Eric Mauser; the notice is in
`Lodestar_Guide/Data/LICENSE-pfQuest.txt`), itself built from [VMaNGOS](https://github.com/vmangos). It gives the
arrow and the router quest givers, turn-in NPCs, objective mobs/objects, quest-item drop sources and their positions
for every Vanilla quest ID. Regenerate with `tools/pfquest/fetch.sh && python3 tools/pfquest/import.py`.

`Lodestar_Guide/Data/ATT.lua` is generated from the Camelot (Forever) database of
[All The Things](https://github.com/ATTWoWAddon/AllTheThings) (MIT, Copyright (c) 2026 AllTheThings WoW Addon; the
notice is in `Lodestar_Guide/Data/LICENSE-ATT.txt`). It supplies quest-giver coordinates, objective providers and
the `sourceQuests` prerequisite graph for Forever, which is what lets a route be ordered by what a quest actually
needs first. It is merged *under* the harvest overlay (`Data.lua: MergeATTData`): ATT covers the old world densely
and Forever's new zones thinly, Lodestar's own harvest is the reverse, and anything a player recorded first-hand
wins over it. Regenerate with:

```
lua5.1 tools/att/att_to_json.lua <AllTheThings>/db/Camelot/*.lua <AllTheThings>/db/Camelot/Categories/*.lua \
    > data/att/att-camelot.json
python3 tools/att/import_att.py data/att/att-camelot.json
```

`Lodestar_Guide/Data/Forever.lua` is the Forever overlay: quests, NPCs, positions and XP harvested on the beta by
Lodestar itself (`LodestarScanDB`, see `Lodestar_Guide/Harvest.lua`). Export a SavedVariables file with
`lua5.1 tools/pfquest/sv_to_json.lua <WTF/.../SavedVariables/Lodestar_Guide.lua> > data/beta/scan-<date>.json`, then
`python3 tools/pfquest/merge_scan.py` regenerates the overlay from every export in `data/beta/`.

## Contributing data

Forever's new quests are not in any public database and the client gives addons no quest positions, so
Lodestar learns the world from people playing it: quest givers talked to, objectives finished, flight
points unlocked. `docs/CONTRIBUTING-DATA.md` is the page to hand a tester — in short, they play, type
`/reload`, run `tools\collect-harvest.cmd` and send the file it puts on their Desktop. Merge the
exports with `tools/pfquest/merge_scan.py` to regenerate `Lodestar_Guide/Data/Forever.lua`.

Players running Lodestar in the same guild or party also trade newly-learned positions directly over
the addon channel, which needs no files — dormant while a realm restricts addon messages (as the beta
does) and self-starting when that lifts.

## License

MIT for Lodestar. Bundled libraries keep their own licenses (see `LICENSE`).

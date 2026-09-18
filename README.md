# Lodestar

A suite of addons for **World of Warcraft: Forever**. One core, four modules, install what you want.

| Addon | What it does |
|---|---|
| **Lodestar** (required) | Settings panel, module toggles, minimap button, guild/party comms, `/lode` |
| **Lodestar_Leveling** | XP/hour + time-to-level readout, quest auto-accept/turn-in, `/way` waypoints, time-per-level stats |
| **Lodestar_Economy** | Auto-sell greys, auto-repair, account-wide gold ledger, vendor + auction prices in tooltips |
| **Lodestar_UI** | Item/spell/NPC IDs and target-of-target in tooltips, map + minimap coordinates, clickable chat links, timestamps, copy-chat, fast loot |
| **Lodestar_Guild** | Live guild board: who is online, where, what level, who wants a group (`/lode guild`, `/lode lfg`) |
| **Lodestar_Guide** | Navigation arrow (points at the guide step, your `/way` pin, or the nearest quest objective/turn-in), step-by-step guide window, and a route recorder that turns your playthrough into a guide (`/lode record`) |
| **Lodestar_Guides_Horde** | Guide data pack (routes in the text format below). Alliance pack to follow. |

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

Directives: `.goto map,x,y[,radius]` (map id or zone name), `.accept id`, `.turnin id`, `.complete id[,objective]`,
`.xp level`, `.zone name`, `.train`, `.hs name`, `.fly name`, `.vendor`, `.text >>...`, plus `.class` / `.race` step
filters. Steps auto-advance from the quest log; goto-only steps complete on arrival. `/lode record start` logs your
own play (accepts, objective completions, turn-ins, hearth binds, trainers, mob levels) and `/lode record export`
produces this format.

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
tools/               dev tooling (not shipped)
docs/DESIGN.md       architecture, module contract, roadmap
```

### Releasing

Tag `vX.Y.Z` and push the tag. `.github/workflows/release.yml` runs the BigWigs packager, which replaces
`@project-version@` in the TOCs, zips the five folders and publishes to GitHub Releases (and CurseForge /
Wago / WoWInterface once the API-key secrets are set).

## License

MIT for Lodestar. Bundled libraries keep their own licenses (see `LICENSE`).

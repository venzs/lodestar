# Lodestar — design notes

## The platform (what we learned on beta day, 2026-09-17)

- Forever is codename **Camelot** inside Blizzard's Mainline code family. Its TOC files gate content with
  `[AllowLoadGameType camelot]` / `mainline` / `standard`; `standard` is retail proper, `mainline` covers both.
  Blizzard confirmed it "shares Mainline WoW's UI architecture, including the vast majority of APIs
  available in 12.1.5". Classic Era addons do not load; Midnight-updated addons port easily.
- Client 1.60.1 (build 69893) → `## Interface: 16001`. `GetBuildInfo()` returns `"1.60.1"`, so the toc
  number sits between Classic Era (1.15.x → 11509) and TBC (2.x → 20506). `Lodestar.IsForever` is
  `16000 <= toc < 20000`.
- Retail-style API everywhere: `C_Item`, `C_Container`, `C_QuestLog`, `C_GossipInfo`, `C_Club` for the guild
  roster, `TooltipDataProcessor` (the old `OnTooltipSetItem` hooks are gone), `C_AuctionHouse` with the
  commodity/item split, `MenuUtil` context menus, `Settings` panel, `AddonCompartmentFrame`.
- Legacy globals that still exist as undocumented C functions (referenced by Blizzard's own loaded Lua):
  `AcceptQuest`, `CompleteQuest`, `GetQuestReward`, `GetNumQuestChoices`, `RepairAllItems`,
  `GetRepairAllCost`, `CanMerchantRepair`, `GetNumActiveQuests`/`GetActiveTitle`, `LootSlot`,
  `GetInventoryItemLink`. Gone: `GetItemInfo` (use `C_Item.GetItemInfo`), `GetContainerItemInfo`,
  `GetQuestLogTitle`, `GetGuildRosterInfo` (use `C_Club`), `GetCoinTextureString` (use `C_CurrencyInfo`).
- Midnight restrictions apply: secret values in combat, private auras, restricted computational combat
  addons. Blizzard ships its own damage meter (`Blizzard_DamageMeter`) and cooldown manager. The suite
  deliberately stays out of combat math.
- Ace3 added Forever compatibility on 2026-09-18 (TOC lists 16001); the suite embeds it.

## Architecture

```
Lodestar (core, AceAddon "Lodestar")
├── Init.lua      addon object, AceDB (LodestarDB), player info, lifecycle
├── Utils.lua     printing, formatting, class colors, version compare, tooltip providers, HasAPI
├── Errors.lua    chained error handler → LodestarProbeDB.errors  (/lode errors)
├── Modules.lua   RegisterModule: AceDB namespace + settings page + per-profile enable toggle
├── Config.lua    AceConfig tree (function-based, rebuilt on open) + Blizzard Settings categories
├── Comm.lua      "Lodestar" addon prefix, serialized {t=…} envelopes, version announce (t="V")
├── Minimap.lua   LDB launcher + LibDBIcon + addon compartment + MenuUtil module menu
├── Probe.lua     /lode probe → LodestarProbeDB (API availability snapshot for tracking beta changes)
└── Slash.lua     /lode <verb>; modules add verbs with Lodestar:RegisterSlashVerb
```

Module contract (see `Lodestar/Core/Modules.lua`):

```lua
local M = Lodestar:NewModule("Leveling", "AceEvent-3.0", ...)
M.displayName, M.description, M.order
M.defaults = { profile = {...}, char = {...} }   -- AceDB namespace defaults → M.db
M.options  = { ... }                              -- AceConfig args merged under the module's page
Lodestar:RegisterModule(M)
function M:OnEnable() / OnDisable() / OnProfileChanged()
```

Modules are separate addons with `## Dependencies: Lodestar` so users install only what they want and
each gets its own listing on CurseForge/Wago (more search surface for the brand). Enable/disable is live.

### Comms

One prefix (`Lodestar`), AceComm + AceSerializer, message = table with `t` (type) and `v` (sender's version).
Core handles `V`; Guild handles `P` (presence) and `Q` (query). Every message doubles as a version check, so
"a newer Lodestar is available" spreads through guilds on its own. `CanSendComm()` honours
`C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`.

### Saved variables

- `LodestarDB` — AceDB with profiles; modules live in namespaces (`LodestarDB.namespaces.Leveling…`).
  Economy's gold ledger is `global`, its price memory is `factionrealm`.
- `LodestarProbeDB` — dev/diagnostic only: probe output and caught errors.

## Verification without the game

`tools/extract_api.py` parses Blizzard's exported UI source, resolves the TOC gates for `camelot` and
emits the exact set of globals, `C_*` functions, events and enums that exist. luacheck runs with that
list as `read_globals`; `tools/apicheck.py` checks namespaced calls/events/enums; `tools/smoke/run.lua`
loads everything under a stub and exercises the handlers. In-game, `/lode probe` and `/lode errors`
close the loop (both write to `LodestarProbeDB`, flushed on `/reload`).

## Roadmap to launch (Nov 4, 2026 — beta ends Oct 21)

1. **Now:** load on beta, fix whatever the probe/error log shows, tune quest automation edge cases
   (gossip NPCs with vendor options, repeatable quests, level-gated trivial detection).
2. **Week 1:** CurseForge/Wago project pages (name reserved early), screenshots, Forever flavor as soon as
   the sites add it; GitHub Releases in the meantime. Auction house: confirm which `C_AuctionHouse` path the
   Forever AH uses and finish the tooltip price memory around it.
3. **Week 2–3:** the features that make people install it: quest reward XP-to-level estimate ("3 turn-ins
   to ding"), guild board polish (sorting, whisper/invite, LFG notifications), coordinates on the map
   pin tooltip, `/way` distance readout, chat improvements (class colors in guild board, URL copy).
4. **Week 4:** localization scaffolding (AceLocale already wired), profile import/export, options polish,
   a 1.0 tag before launch day so the version-announce message spreads a stable build.
5. **Post-launch:** the leveling data layer (per-zone quest hubs from the beta's new content), a
   companion "what's next" panel, and whatever the launch-day errors say.

Things deliberately not built: damage meters, cooldown tracking, aura/proc alerts, nameplate mods —
Blizzard is restricting or replacing all of these in the Midnight/Forever API.

# Changelog

## Unreleased

- **Saved variables renamed.** Forever's beta client writes a saved variable whose name ends in `DB`
  at logout and hands back `nil` at login, every session — which threw away the harvest, reset every
  frame to its default position and restarted guide progress on each relog. `LodestarDB`,
  `LodestarProbeDB`, `LodestarScanDB` and `LodestarShareDB` are now `LodestarCore`, `LodestarProbes`,
  `LodestarScans` and `LodestarHarvest`; the old names stay declared for one release and are adopted
  on first login. `tools/smoke/persist.lua` runs two real sessions in two Lua states and checks what
  survives the file; `tools/check_tocs.py` rejects a `DB` suffix.
- Economy: **bags and repairs** — `/lode bags` and a minimap tooltip line give free slots, what a
  vendor would pay for what you are carrying, and what a full repair would cost. The repair figure
  calibrates itself: the client only quotes a cost while a repair vendor is open, so the
  copper-per-durability-point rate is learned from your own repairs and applied everywhere else.
  Until one repair has been seen, nothing is claimed. The durability warning carries the figure too.
- Leveling: **camp** — how long each watched buff has left (on the strip and as a warning before it
  drops), food and drink counted in the bags with a low/empty warning, and `/lode camp`.
- Leveling: **professions** — rank and cap per profession, a warning when one hits its tier cap that
  names the rank which lifts it and the level that rank needs, points gained per character, capped
  professions on the status strip, and `/lode prof`. Uses harvested tradeskill trainers to say how
  far the nearest one is.

- Guide: built-in Vanilla quest database (pfQuest import) and a Forever overlay harvested on the beta; smart mode,
  the arrow and quest tooltips resolve turn-ins, objectives and pick-ups from them (Forever exposes no quest POIs).
- Guide: trails — walkable ground learned from where you walk plus seeded roads; the arrow routes along them (A*).
  Minimap line to the target. Own 256 px arrow art with size/style presets.
- Guide: sync to the quest log on load and on demand (Sync button); speed-run vs completionist mode with
  `.optional` steps; `.buy`, `.path`, `.profession`, `.camp`, `.cook`, `.train NPC`, `.item` directives; class
  trainer reminders from a per-class trainer table.
- Guide: quest census (`/lode scan quests`) and harvester (NPC positions, offered/ended quests, XP per quest,
  objective spots, flight nodes, XP per level) into LodestarScanDB; `tools/pfquest/merge_scan.py` turns exports
  into Data/Forever.lua.
- Guides: Horde 1-30 (Deathknell/Tirisfal, Durotar, Mulgore, Silverpine, Barrens, Hillsbrad, Stonetalon, Ashenvale,
  Thousand Needles) and Alliance 1-20 (Elwynn, Dun Morogh, Teldrassil, Westfall, Loch Modan, Darkshore) drafts.
- Lodestar_Character: hidden character-sheet stats in a panel of our own beside the character sheet.
  It does **not** touch `PAPERDOLL_STATCATEGORIES` / `PAPERDOLL_STATINFO`: writing into those taints
  Blizzard's character frame on Forever and opening the sheet threw
  `TextStatusBar.lua:110: attempt to compare a secret number value`. `/lode character` toggles the panel.
- Review fixes across core, leveling, economy, UI and guild (live module toggles, merchant auto-sell, item level,
  map coordinates layering, chat link handler, guild board in combat, comm query storms).

- Initial suite: Lodestar (core), Lodestar_Leveling, Lodestar_Economy, Lodestar_UI, Lodestar_Guild.
- Lodestar_Guide: navigation arrow with smart quest targeting, guide engine + text format, route recorder.
- Lodestar_Guides_Horde: draft Undead Deathknell route (verify with the recorder).
- Targets WoW: Forever beta 1.60.1 (Interface 16001).
- Guild: works without addon comms. When the realm restricts addon messages (`AreOutgoingAddonChatMessagesRestricted`, true everywhere on the beta) nothing is sent or queued, the heartbeat stays off, the board shows the C_Club roster with a notice, and `/lode lfg` puts `/g LFG: <text>` in the chat box for you to send. Comms resume automatically on `ADDON_RESTRICTION_STATE_CHANGED`.
- Leveling: status strip under the XP readout (free bag slots, lowest durability, rested % of level, resting state, watched buffs such as Well Fed) with chat nags at 2 free slots / 20 % durability, one per five minutes each, each with its own toggle.
- Leveling: "turn-ins to ding" — the XP readout, its tooltip and the minimap tooltip show the reward XP of quests ready to turn in and whether it covers the rest of the level.

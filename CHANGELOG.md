# Changelog

## Unreleased

- **Saved variables are not coming back on the beta client.** Lodestar's four, and four standalone
  probe addons alongside them, are written faithfully at logout and handed back `nil` at login —
  which threw away the harvest, reset every frame to its default position and restarted guide
  progress on each relog. The sessions where anything did survive were `/reload`s, where the client
  can keep the table in memory; every session that began after the game was actually closed got
  nothing back. Two probes are deployed to confirm that this build simply does not read addon saved
  variables from disk. Meanwhile `LodestarDB`, `LodestarProbeDB`, `LodestarScanDB` and
  `LodestarShareDB` are renamed to `LodestarCore`, `LodestarProbes`, `LodestarScans` and
  `LodestarHarvest` (the old names stay declared for one release and are adopted on first login),
  and Lodestar says so loudly, once, when a harvest comes back empty.
- `tools/smoke/persist.lua` runs two real sessions in two Lua states, serialising the saved
  variables to disk in the client's format and reloading them in the client's window — after the
  addon's files, before its `ADDON_LOADED`. It covers frame positions, settings, the harvest and the
  upgrade path, and is the test that would have caught the frame-position bug.
- Guide: the harvest now records **the client's own next-objective waypoint** for every quest in the
  log (`C_QuestLog.GetNextWaypoint`). Forever exposes no quest POIs, so until now an objective only
  got a position when a player was standing on the spot as a counter moved; a quest accepted in a
  village now knows roughly where to go the moment it is accepted. Ranked below a real sighting, and
  carried through `merge_scan.py` so generated routes benefit too.
- Guides: **Skyborne 1-12: Zephras Isle**, the first route generated end to end from the merged
  database rather than hand-authored — 17 quests, ordered by the prerequisite chains and by an
  estimated level so the route does not open with content a level 1 character cannot accept.
  `tools/router/lint_guides.py` now knows the Forever and ATT quest ids, so generated routes for new
  content can be checked at all.
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

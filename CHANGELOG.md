# Changelog

## Unreleased

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
- Lodestar_Character: hidden character-sheet stats inside Blizzard's stats pane.
- Review fixes across core, leveling, economy, UI and guild (live module toggles, merchant auto-sell, item level,
  map coordinates layering, chat link handler, guild board in combat, comm query storms).

- Initial suite: Lodestar (core), Lodestar_Leveling, Lodestar_Economy, Lodestar_UI, Lodestar_Guild.
- Lodestar_Guide: navigation arrow with smart quest targeting, guide engine + text format, route recorder.
- Lodestar_Guides_Horde: draft Undead Deathknell route (verify with the recorder).
- Targets WoW: Forever beta 1.60.1 (Interface 16001).
- Guild: works without addon comms. When the realm restricts addon messages (`AreOutgoingAddonChatMessagesRestricted`, true everywhere on the beta) nothing is sent or queued, the heartbeat stays off, the board shows the C_Club roster with a notice, and `/lode lfg` puts `/g LFG: <text>` in the chat box for you to send. Comms resume automatically on `ADDON_RESTRICTION_STATE_CHANGED`.
- Leveling: status strip under the XP readout (free bag slots, lowest durability, rested % of level, resting state, watched buffs such as Well Fed) with chat nags at 2 free slots / 20 % durability, one per five minutes each, each with its own toggle.
- Leveling: "turn-ins to ding" — the XP readout, its tooltip and the minimap tooltip show the reward XP of quests ready to turn in and whether it covers the rest of the level.

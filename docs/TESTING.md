# Testing Lodestar on the Forever beta

What to run, what to look at, and what to send back. Everything the addon learns is written to
`WTF/Account/<account>/SavedVariables/Lodestar_Guide.lua` (harvest, census, trails) and `Lodestar.lua`
(settings, probe, Lua errors) when you `/reload` or log out — so end every session with a `/reload`.

## Once per build

1. `/reload`, then `/lode errors` — should say none. If it lists something, that plus what you were doing is the report.
2. `/lode probe` then `/reload` — records the client's API answers for the diagnostics.
3. Open the character sheet: the Lodestar categories (Melee, Ranged, Spell, Regeneration, Defense detail,
   Weapon skills, Gear, Progress) should appear under Blizzard's. Hover a few rows: tooltips should make sense.

## Every session

- Arrow: does it point at the right thing, and does "via trail" ever route you into terrain? Note where.
- Guide window: after login, is the step the one you would have picked? If not, click **Sync** and say what it chose.
- Tooltips: hover a quest mob, a quest giver, a quest item. Wrong quest or missing line = report with the name.
- Smart mode (right-click the window): are the "Pick up" rows real quests you can take?
- Status strip under the XP line: bag count and durability right? "Well Fed" shows when you are?
- Guild board `/lode guild`: opens, closes, roster shows (comms are restricted on the beta, so no presence rows).

## Data runs (background, keep playing)

- `/lode scan quests 90000 100000` — Forever's new quest ids. Then `/lode scan retry` for the unanswered ones.
- `/lode scan status` — counts. `/lode scan npc` with a mob targeted prints what the harvest knows about it.
- Talk to every quest giver, trainer, vendor and flight master once; open the flight map; the harvest records them.
- `/lode record start` when you begin a zone, `/lode record export` at the end: the recording is the route draft.

## Reporting

One line per problem: what you did, what happened, what you expected, and the zone/coordinates (`/lode loc`).
Screenshots help for layout. For anything about the arrow, `/lode guide diag` then `/reload` saves the details.

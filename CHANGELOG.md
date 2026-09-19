# Changelog

## Unreleased

- **The beta client does not hand addon saved variables back, and that is now measured rather than
  inferred.** Lodestar writes a session counter at login that nothing ever resets. On this build it
  reads `sessions = 1` and `sawPreviousSession = false` every time — including across a plain
  `/reload`, where the previous session had already written `1` to the file sitting on disk. The
  file is written correctly and ignored on the way in. Every "it forgot where my window was" and
  "it restarted the guide" follows from that one fact, and none of it can be fixed by saving harder.
- **So the things you'd notice go through the client's own config instead.** `C_CVar.RegisterCVar`
  puts a value in `config-cache.wtf`, which demonstrably *does* survive a relaunch on the same
  machine where the saved variables do not. `Core/Vault.lua` keeps exactly three things there —
  where each window is, which guide you are on, and how far through it you are — and nothing else.
  It is not a second database and must not become one: the harvest, the settings and the history
  stay in the saved variables, where they belong and where they will start working again the day
  the client is fixed. A saved variable that *does* come back always wins over the vault, so on a
  healthy client this changes nothing at all.
- `tools/smoke/persist.lua` gained a fourth session, `forgetful`, which is the beta as measured: the
  saved-variable file is written and then deliberately withheld from the next login while the config
  file is carried across. It runs in its own process, which is the only way to tell the difference —
  the in-process suite shares a Lua state, so an in-memory cache makes the vault look like it works
  even when it cannot write a byte.
- **Guide: the client's "you have already done all of this" is no longer taken at face value.** On
  Abhi's character `SuggestStartIndex` returned 36 of 36 for a level 6 druid: every quest in a 1-12
  route reported as turned in. A route declares the levels it covers, and finishing it is what makes
  a character level 12 — so a level 6 character has not finished it, whatever the flag says. When the
  two contradict each other, the flag is dropped for that route's quests (turn-ins actually watched
  this session still count), the start is worked out from the quest log instead, and Lodestar says so
  in chat rather than silently disagreeing with the client. The distrust is reconsidered on every
  load, so levelling past the contradiction restores the client's answer. `/lode guide why` lists the
  quests involved, and cross-checks `IsQuestFlaggedCompleted` against `GetAllCompletedQuestIDs` so a
  client that contradicts itself is recorded precisely rather than guessed at.

- **Guide: the route was parking on its last step and then forgetting it existed.** Read out of a
  real WTF folder rather than reasoned about: a level 6 character had `progress` of 36 on the
  36-step Zephras Isle route, and the previous session's file still had `currentGuide` set while the
  newer one did not. Nothing had been finished. A start suggestion had run off the end of the route,
  `LoadGuide`'s clamp pinned it to the last step and wrote that back as progress, and the next login
  read `progress == #steps` as a finished guide, fell through to auto-pick and cleared
  `currentGuide`. From there the window was showing **smart mode**, not the route — which is what
  "it's telling me to pick up a quest I've already done" and "it's telling me to turn in a quest I
  haven't completed" actually were, and why four fixes to the route engine changed nothing.
  Completion is now recorded explicitly by `FinishGuide` and nothing else; saved progress sitting on
  the last step of a route that was never finished is treated as the clamp artifact it is and
  reconciled instead; and the clamp says so when it fires.
- **Guide: `/lode guide why`.** The engine now writes down what it decided and what it decided it
  from, at the moment it decides — every guide considered and the filter that rejected each one, the
  character as the filters see it, what the saved progress said and whether it was believed, what the
  quest log suggested, and whether the completed-quest list had arrived yet. It is mirrored into
  `LodestarProbes.guideDecisions`, so it survives to disk on the next `/reload` and can be read
  without anyone transcribing chat. Four rounds of this bug were debugged from saved files written
  *before* the fix under test had loaded; this is the thing that stops that.
- **Every movable window remembers where it was left.** A WoW anchor is four values, and two of the
  five movable frames — the XP tracker and the guild board — were saving three of them and throwing
  the `relativePoint` away. Restoring the same offsets against a different corner puts the window
  somewhere else; the player drags it back, that spot is saved, and it moves again next login. It
  reads exactly like "the addon doesn't save its position" while the saved variables look perfectly
  fine, which is why looking at them twice proved nothing. (In Abhi's file: the tracker saved at
  `TOPLEFT (271, -290)` and came back as `(-10, -47)` with no point at all.) There is now one
  implementation in `Core/Anchor.lua`, all five frames use it, `tools/check_anchors.py` fails the
  build if a sixth rolls its own, and the smoke suite round-trips a drag on each of them — the two
  frames that were broken were the two with no test.
- **A session counter, to settle the saved-variable question by measuring it.** One integer that
  nothing ever resets, written at login: reading 1 on every launch means the client is not handing
  saved variables back at all; climbing across `/reload` but resetting after a quit means they only
  survive in memory; climbing across a real relaunch means they work and any "it forgot" is
  Lodestar's bug. Everything claimed below about this client is inference from file sizes and from
  which addons happened to be installed when. This is the measurement instead.

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
- Leveling: **quest log hygiene** — a warning when the twenty-slot log is nearly full that names
  which quests have gone grey, `/lode log` for the full picture, and `/lode log drop <name>` to
  abandon one. Only grey quests are candidates and nothing is ever abandoned without a confirmation.
- Guide: **stopped calling a protected function on every creature you walk past.** The harvest used
  `CheckInteractDistance` to grade how close a sighting was. That function is protected on this
  client: calling it raises `ADDON_ACTION_BLOCKED` and taints the execution path, and the `pcall`
  around it did nothing, because a blocked call is not a Lua error. It fired from
  `NAME_PLATE_UNIT_ADDED`, `UPDATE_MOUSEOVER_UNIT` and `PLAYER_TARGET_CHANGED`. Passive sightings
  are now recorded at one grade and precision comes from `exact`, set when an interaction frame is
  genuinely open. `tools/check_protected.py` rejects the whole class.
- Guide: **saved progress pointing at a dead-end step is no longer trusted.** Saved progress is
  never stepped backwards over — that is what stops the guide dragging you back over work you
  skipped deliberately — but a saved step that hands in a quest you are carrying and have not
  finished is not a position, it is a dead end that nothing can ever advance. Those now reconcile
  instead. A quest that is not in your log at all still counts as a deliberate skip and is left be.
- Guide: **resuming never lands on a turn-in for a quest that is not finished.** Ranking candidate
  steps by distance put the turn-in ahead of the objective — the giver stands in the village, the
  mobs are out in the field — so resuming near town said "hand in The Mindless Ones" with three of
  eight zombies dead. A turn-in that is neither already done nor ready to hand over now ranks last.
- Guide: **the guide no longer reconciles before the client can answer.** For the first seconds after
  entering the world `C_QuestLog.IsQuestFlaggedCompleted` returns false for every quest rather than
  "not yet known". Since this client never hands saved progress back, every login reconciles from
  scratch — in exactly that window — so the guide concluded the character had done nothing and sent
  them back at quests they had already finished. It now redoes the reconcile once the completed list
  lands, and says where it moved to.
- Guide: auto-pick **fails closed on an unknown faction**. `UnitFactionGroup` can answer nil early in
  the login, and a nil switched the faction filter off entirely rather than narrowing it — so an
  Alliance character could be auto-loaded onto a Horde route on the other continent. Listing is
  unchanged: not knowing should not hide every guide, only stop one being loaded on a guess.
- `tools/check_events.py`: rejects two files in one module registering the same event, which
  AceEvent silently collapses to one handler.
- `tools/refresh_harvest.sh`: one command to fold a play session's harvest back into the shipped
  database and rebuild the routes derived from it. Merging is now idempotent, so a diff after a
  session shows what the session added rather than reordered coordinates, and `sv_to_json.lua`
  detects which of the three historical global names an export actually uses.
- Guide: **corpse run** — while a ghost the arrow points at your body, ahead of the guide, the quest
  log and any pin, since nothing else can be done until you get there.
- Guide: **travel hints** on the arrow — "Hearth to Deathknell, then 240 yd" or "Fly to The
  Sepulcher, then 180 yd" when the detour saves more than 700 yards and the hearthstone is actually
  off cooldown. Flight points are only the ones this character has visited.
- Guide: the harvest now records **the client's own next-objective waypoint** for every quest in the
  log (`C_QuestLog.GetNextWaypoint`). Forever exposes no quest POIs, so until now an objective only
  got a position when a player was standing on the spot as a counter moved; a quest accepted in a
  village now knows roughly where to go the moment it is accepted. Once a quest is complete the same
  call points at the turn-in, so it also fills in ender positions — the thing route generation is
  actually short of. Both are ranked below a real sighting and carried through `merge_scan.py`.
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

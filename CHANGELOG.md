# Changelog

## Unreleased

- **The loop was mine, and the client was never lying.** Read out of Abhi's saved variables at last:
  16 of the Zephras Isle route's 17 quests were in `GetAllCompletedQuestIDs`, and the per-quest flag
  agreed on every one of them. He really had finished everything the route knew about. A generated
  route carries the quests the harvest has managed to *place* — 17, while the zone has many more —
  so a level 6 character finishing all of them is completely normal, and a start suggestion landing
  on the last step is the route being exhausted, not evidence of anything.
  The previous release read that as impossible, concluded the completion data must be wrong, stopped
  believing it for the route's quests, and sent the character back to step 1 to be offered quests
  they had handed in hours earlier. That guard is gone entirely, along with the distrust mechanism it
  drove. A route whose quests are all finished now says so — naming how many it covers and why that
  is fewer than the zone has — then chains to its `#next` or hands over to smart mode.
- Guide: **a finished route can still be loaded by name.** Otherwise it bounces straight back out to
  smart mode, which reads as "it will not let me select that any more". `/lode guide reset` starts
  it over.

- **Guide: a step asking for a quest this character can never be given is skipped.** "A Student of
  the Arcane" and "A Student of Nature" are the same step of the same chain offered to different
  specialisations: a druid takes Nature, and the route then asks for Arcane forever. The step can
  never complete, so the guide parks on it and every later step is unreachable. No data fixes this —
  the harvest records that a quest exists, not who is allowed to have it — but the NPC knows. When
  you open a quest giver and the step's quest is not on their list, that is a fact, and the step is
  marked done with a line saying why. `<` goes back to it.
  Each event reads only its own quest source, which matters more than it sounds: `GetNumAvailableQuests`
  answers from QuestFrame, which keeps whatever it last showed, so consulting it during a gossip
  window can return the *previous* NPC's quests — and skipping a step on that would be far worse
  than the problem being solved. `QUEST_DETAIL` is not a trigger at all, because opening one quest's
  page says nothing about the rest of the list. An empty list is treated as "the client has not
  answered yet", not as "this NPC has nothing".
- **`/lode guide`'s help is generated from its own dispatch table.** The usage line was hand-written
  and listed neither `why` nor `completed`, so someone told to run `/lode guide completed` got back a
  list that did not mention it — which reads exactly like nothing happened. An unknown sub-command
  now names what was typed and lists what does exist, and a command cannot be added without
  appearing in the help.

- **Route quality is measured, and regressions in it fail loudly.** Everything the guide lint did
  proved a route was *valid* — right order, right positions, right levels, the right faction's NPCs
  — and none of it said whether the route was any good to walk. It now reports how far each route
  travels, how much of that is doubling back over ground already covered, and its longest single
  hop. There is deliberately no pass/fail threshold: the hand-written routes, the ones a person
  walked and was happy with, range from 28% to 64% backtracking, so any line drawn through that
  would be taste dressed up as a rule. Instead `docs/route-shape.json` records what each route
  scores today and the lint reports when one gets more than 10% worse — which is exactly what
  happens when a change to the generator has an effect nobody intended. `--record-shape` accepts the
  new numbers deliberately.
- The "already been here" radius scales with the route rather than sitting at a fixed two map
  percent, which is about one camp in Durotar and about a third of Zephras Isle. Small dense starting
  zones were scoring 73% backtracking for ordinary hub-and-spoke questing.

- **A route must never send you to the other faction's NPCs.** The generator filtered on the quest's
  race bitmask, which is almost always empty: in a contested zone the faction split is expressed by
  *who stands there*, not by a flag on the quest. The generated Alliance Ashenvale route took 22 of
  its 57 quests from Horde NPCs — Je'neu Sancrea at Zoram'gar, the whole Warsong Lumber Camp chain,
  Senani Thunderheart at Splintertree — and passed every check there was, because nothing looked at
  the NPC. Both the generator and the guide lint now do. A quest offered in every capital lists one
  giver per city, so the generator picks one this faction can actually talk to rather than the first
  in the list, and the lint only objects when none of them will.
- Guide: **class-restricted quests carry `.class`.** A general route was handing warriors "Journey to
  the Marsh", which is a mage quest — unfinishable, so the guide parked on it. The engine has always
  filtered steps by class; it was never being told which steps to filter. Class quests also get a
  step of their own, since `.class` hides the whole step and folding one in with three ordinary
  quests from the same NPC would hide all four from everybody else.
- **Alliance levelling reaches 30.** Duskwood (25-30) and Hillsbrad Foothills (30-35) close the last
  gap, so both factions now run 1 to 30 unbroken — as far as the beta goes — and every `#next` in
  that range leads to a route that exists.
- `tools/router/regen.sh` rebuilds every generated route from its own recorded `--regen-args`. There
  is no separate manifest to drift out of step with the files, and a hand-written guide has no such
  line and is never touched.

- **The completed-quest check asks the client's list, not its per-quest flag.** On this build
  `IsQuestFlaggedCompleted` answers true for every quest in Zephras Isle for a character who has done
  four of them, which is what sent a level 6 druid to step 36 of 36. The first attempt at handling
  that refused to believe the flag for a route the character's level said they could not have
  finished — which fixed "you have done everything" by replacing it with "you have done nothing",
  and started offering back quests that had just been handed in. Distrusting a bad signal is not the
  same as finding a good one: `GetAllCompletedQuestIDs` returns the finished quests as a list, which
  cannot be wrong in that shape, so it is now the answer wherever the client provides one. The flag
  remains the fallback for a client with no list. A turn-in watched happening this session counts
  immediately either way, because the list lags the event and nobody should be sent back to an NPC
  they just left.
- **`/lode guide completed`** prints both of the client's answers side by side for every quest in the
  loaded route, plus whether it is in the quest log. Which call to believe had been argued twice from
  behaviour; this settles it from data, in one screen, without anyone reloading.
- Guide: **a neutral race's route chains by faction.** `#next Horde: <guide>` and
  `#next Alliance: <guide>` sit alongside the plain `#next`, because the Skyborne pick a side at
  creation and level 12 sends the two halves of the race to different continents. Zephras Isle had no
  successor at all, so a Skyborne reached 12 and fell into smart mode with no route.
- **Four routes that were referenced but did not exist.** Every `#next` in the packs now leads
  somewhere: Redridge Mountains, Wetlands and Ashenvale for Alliance (20-25), Desolace for Horde
  (30-35). Alliance levelling stopped dead at 20 and Horde at 30, which is not a levelling suite.
  All four are generated, and all twenty-one routes now lint with zero errors.
- **The route generator can read the vanilla database at last.** It only ever unioned the harvest and
  ATT, never pfQuest's 4,400 quests, and its position lookup understood only the harvest's coordinate
  shape — so every vanilla zone generated an empty route regardless of the map id it was given. With
  both fixed it also learned: faction filtering by Classic's race bitmask (an Alliance Ashenvale route
  was otherwise routed through a Horde camp), a level floor so a 20-25 route does not open on "Accept
  CLUCK! (lvl 1) from Chicken", a quest's hard `min` level as a gate rather than a suggestion, `.xp`
  checkpoints paced from the route's own declared level range, turn-in stops positioned at each
  quest's own ender rather than one representative's (an Ashenvale turn-in pointed eighteen map units
  from the NPC holding it), world objects as quest enders, and prerequisites satisfied by being turned
  in rather than merely accepted.
- Guide: a turn-in whose location was never recorded says so and points at the giver; one whose ender
  is known to stand in another zone becomes an optional breadcrumb with no arrow at all. Conflating
  the two briefly turned every turn-in in a freshly harvested zone into an optional step the
  speed-run mode skipped.

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

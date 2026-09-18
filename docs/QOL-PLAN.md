# Lodestar — quality-of-life plan for Forever

Companion to `FOREVER-FEATURES.md`. API names below were checked against `tools/wow-api/api.json` (build 1.60.1.69893):
**GF** = documented global function, **NS** = documented `C_*` namespace function, **INF** = undocumented global that
Blizzard's own camelot-loaded Lua calls (exists, but no signature docs), **UI** = Lua-side global from Blizzard UI code,
**?** = not found in either list (assume absent until `/lode probe` says otherwise).

## Part A — "Character" module (`Lodestar_Character`)

### What Blizzard's Forever character sheet already renders

From `Blizzard_UIPanels_Game/Camelot/PaperDollFrameConstants.lua` (`PAPERDOLL_STATCATEGORIES`) and `CharacterFrame.lua`
(`CharacterStatsPaneScrollBoxMixin:UpdateStats`). Rows marked *hide 0* disappear when the value is zero.

| Category | Rows | Notes |
|---|---|---|
| General | Health, Power, Movement speed | speed from `GetUnitSpeed`; tooltip shows run/swim |
| Attributes | Strength, Agility, Intellect, Stamina, Spirit | tooltips show class-specific derived values (AP, crit, mana, HP, regen from spirit) |
| Weapons | Main-hand dmg, Off-hand dmg *hide 0*, Ranged dmg *hide 0*, Attack power *hide 0*, Ranged AP *hide 0* | damage tooltip appends the **equipped weapon's skill** (`C_SkillInfo.GetSkillLineInfoByID`) |
| Modifiers | Hit *hide 0*, Crit *hide 0*, Haste *hide 0*, Expertise *hide 0*, Armor pen *hide 0*, Spell power *hide 0*, Spell healing *hide 0*, Spell pen *hide 0* | Hit/Crit/Haste show **only the max** of melee/ranged/spell; the split is tooltip-only. Spell power shows the **minimum** school; per-school values tooltip-only |
| Defense | Defense (x / level×5), Dodge *hide 0*, Block (only with shield), Parry *hide 0*, Armor | block value tooltip-only |
| Resistance (hard-coded after the categories) | Arcane, Fire, Frost, Nature, Shadow | tooltip: expected resist % vs same-level caster |
| Pet tab | Health, Armor, Damage, AP, Spell power, Hit, Crit, Haste, Speed | plus happiness/loyalty (`C_PetInfo.GetPetHappiness`, `GetPetLoyalty`, `GetPetTrainingPoints` — NS, Classic pet system is back) |
| Other tabs | Reputation, **Skills** (weapon skills with hit/crit/glancing detail vs +0/+3), PvP rank, Currency, Statistics | Skills tab already does the weapon-skill math; do not duplicate it there |

Defined in `PAPERDOLL_STATINFO` but **not placed in any camelot category** (i.e. hidden): `ITEMLEVEL`, `MANAREGEN`, `ATTACK_ATTACKSPEED`,
`HITCHANCE_MELEE/RANGED/SPELL`, `WEAPON_SKILL`, `HOLY_RESIST`, and the retail-only `MASTERY`, `VERSATILITY`, `LIFESTEAL`,
`AVOIDANCE`, `SPEED`, `STAGGER`, `ENERGY_REGEN`, `RUNE_REGEN`, `FOCUS_REGEN`.
Known issue (Kaivax 09-17): the pane does not show Level/Class/Titles yet — Blizzard's, leave it.

### Stats to add, with the exact API

| Row | API (verified) | Status on Forever / caveat |
|---|---|---|
| Melee hit % | `GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier()` GF/GF | Blizzard computes exactly this for its tooltip. Add miss table vs +0/+1/+2/+3 (boss) using the camelot tables `meleeMissChances = {5.0, 5.2, 5.4, 9.0}` and weapon-skill delta from the Skills tab formula (`(targetLevel×5 − weaponSkill) × 0.04`). |
| Ranged hit % | `GetCombatRatingBonus(CR_HIT_RANGED) + GetRangedHitModifier()` GF/GF | show only for Warrior/Hunter/Rogue (Blizzard's rule) |
| Spell hit % | `GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier()` GF/GF | spell miss table `{4, 5, 6, 17}` from the same file |
| Melee / ranged / spell crit % | `GetCritChance()`, `GetRangedCritChance()`, `GetSpellCritChance()` GF | **Per-school spell crit is not available**: `GetSpellCritChance` takes no `school` argument on this client (`PlayerScriptDocumentation.lua`). |
| Spell power per school | `GetSpellBonusDamage(school)` GF, school 2..`MAX_SPELL_SCHOOLS` (2 Holy, 3 Fire, 4 Nature, 5 Frost, 6 Shadow, 7 Arcane); `GetSpellBonusHealing()` GF | one row per school that differs from the minimum, or all six behind a toggle |
| Mana regen (MP5) | `GetManaRegen()` GF → `baseManaRegen, castingManaRegen` per second (×5); `GetManaRegenFromSpirit()` GF | `PaperDollFrame_SetManaRegen` exists, just unplaced. Skip for classes with `UnitPowerMax("player", Enum.PowerType.Mana) == 0` |
| Health regen (HP5) | `GetHealthRegen()` GF → out-of-combat, in-combat; `GetHealthRegenFromSpirit()` GF | Blizzard multiplies by 0.75 for "standing" |
| Haste split | `GetMeleeHaste()`, `GetRangedHaste()` (+ quiver haste 2nd return), `UnitSpellHaste("player")` GF | only when any > 0 |
| Attack speed / DPS | `UnitAttackSpeed("player")` GF → mh, oh; `UnitDamage("player")` GF → min/max/oh min/max/…/percent; `UnitRangedDamage("player")` GF → speed, min, max | DPS = (min+max)/2/speed; `PaperDollFrame_SetAttackSpeed` exists unplaced |
| Weapon skill (MH/OH/ranged) | `GetInventoryItemID("player", slot)` INF → `C_Item.GetItemInfoInstant(id)` NS (classID/subclassID) → `WEAPON_SUBCLASS_TO_SKILL_ID` table copied from `PaperDollFrameStats.lua` → `C_SkillInfo.GetSkillLineInfoByID(skillID)` NS → `rank, maxRank, modifier`; Feral 3014 when `GetShapeshiftForm() ~= 0` on a Druid; 162 Unarmed when empty | rows "Swords 87/100 (+5)"; event `SKILL_LINES_CHANGED` |
| Defense detail | `UnitDefenseSkill("player")` GF → base, modifier; enemy miss/crit/crush vs +0..+3 from `GetEnemyChanceToMiss` / `GetEnemyCritChance` / `GetEnemyCrushingBlowChance` formulas in `PaperDollFrameStats.lua` (5 % base, ±0.04/skill point, crush at ≥15 diff) | Blizzard shows only "x / max" |
| Block value | `GetShieldBlock()` GF; chance `GetBlockChance()` GF | tooltip-only today |
| Dodge / Parry sources | `GetDodgeChance()`, `GetParryChance()`, `GetDodgeChanceFromAttribute()`, `GetParryChanceFromAttribute()` GF | optional "from agility" sub-line |
| Armor detail | `UnitArmor("player")` GF → base, effective, real, bonus; reduction % vs level via `C_PaperDollInfo.GetArmorEffectiveness(armor, level)` NS and vs target `GetArmorEffectivenessAgainstTarget` NS | Blizzard shows effective only |
| Resistances | `UnitResistance("player", Enum.Damageclass.X)` GF → base, real, effective, bonus; % via `ResistancePercent(resistance, casterLevel)` GF | Blizzard already lists 5 schools; add Holy only if non-zero (`Enum.Damageclass.Holy`), add "avg resist vs +3" line |
| Expertise / armor pen / spell pen | `GetExpertise()` GF (mh, oh, ranged), `GetArmorPenetration()` GF, `GetSpellPenetration()` GF | Blizzard shows when non-zero; Blizzard says Forever adds stats that reduce enemy dodge/parry, so expertise may be live. Leave Blizzard's rows. |
| Average item level | `GetAverageItemLevel()` INF → overall, equipped, pvp; `C_PaperDollInfo.GetMinItemLevel()` NS; `C_Item.GetDetailedItemLevelInfo(link)` NS per slot | `PaperDollFrame_SetItemLevel` exists but is unplaced on camelot (camelot uses the scroll-box path, which ignores `MIN_PLAYER_LEVEL_FOR_ITEM_LEVEL_DISPLAY`). Retail formula, but item levels are real Classic data; label it "avg item level (equipped)" |
| Durability | `GetInventoryItemDurability(slot)` INF (used by the camelot paper doll's repair mode and `EquipmentManager.lua`) for slots 1–18 → cur, max (nil for slots without durability); show min % and average; event `UPDATE_INVENTORY_DURABILITY` | repair cost only at a merchant (`GetRepairAllCost` INF) |
| XP / rested | `UnitXP("player")`, `UnitXPMax("player")` GF; `GetXPExhaustion()` GF (nil when none); `GetRestState()` GF → id, name, factor; `IsResting()` GF; events `PLAYER_XP_UPDATE`, `UPDATE_EXHAUSTION`, `PLAYER_UPDATE_RESTING` | row "XP 12,345 / 20,000 (62 %)" + "Rested 3,400 (17 % of level)" |
| Movement | `GetUnitSpeed("player")` GF → current, run, flight, swim (yards/s; % = v/7×100) | Blizzard has it; keep, add swim % row only if different |
| Progress (new category) | Unspent talent points: `GetNumUnspentTalents()` INF (verify) or `C_Traits.GetTreeCurrencyInfo(C_ClassTalents.GetActiveConfigID(), treeID, true)` NS; Legacy: `C_MajorFactions.GetCurrentRenownLevel(2802)` NS = points earned, `C_Traits.GetTreeCurrencyInfo(C_Traits.GetConfigIDByTreeID(1187/1188/1189), treeID, true)[1].spent` NS; PvP rank: `C_MajorFactions.GetCurrentRenownLevel(2800)` NS | Legacy config IDs are nil until the system unlocks (renown 0) — guard |
| Retail-only stats | Mastery/Versatility/Lifesteal/Avoidance/Speed/Stagger APIs exist (`GetMastery`, `GetVersatilityBonus`, `GetLifesteal`, `GetAvoidance`, `GetSpeed` GF) but Blizzard excluded them from camelot | **do not show**; they are meaningless under Classic combat rules |

### How to integrate (no reimplementation of the sheet)

- The camelot stats pane iterates the global tables at runtime: `PAPERDOLL_STATCATEGORIES` (categories with `categoryName`,
  `unit`, `stats = {{stat=, hideAt=, showFunc=, id=, texture=/atlas=}}`) and `PAPERDOLL_STATINFO[name].updateFunc(statFrame, unit, id)`.
  Insert our categories at `PLAYER_LOGIN` (Blizzard's tables exist by then; `Blizzard_UIPanels_Game` is not load-on-demand) and
  our `updateFunc`s call `PaperDollFrame_SetLabelAndText(statFrame, label, text, isPercentage, numericValue)` and set
  `statFrame.tooltip/tooltip2/tooltip3` or `statFrame.onEnterFunc` — identical to Blizzard's own rows, so we inherit the
  scroll box, header style, zebra striping, atlas icons and gamepad navigation for free.
- Refresh: Blizzard already re-runs `PaperDollFrame_UpdateStats()` on `UNIT_STATS`, `COMBAT_RATING_UPDATE`, `SKILL_LINES_CHANGED`,
  `PLAYER_EQUIPMENT_CHANGED`, `UNIT_AURA`, `SPELL_POWER_CHANGED`, `UNIT_RESISTANCES`, `UNIT_DEFENSE`… Add a small frame that
  calls it (throttled, only while `CharacterFrame:IsShown()`) on `PLAYER_XP_UPDATE`, `UPDATE_EXHAUSTION`, `UPDATE_INVENTORY_DURABILITY`,
  `TRAIT_TREE_CURRENCY_INFO_UPDATED`, `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`.
- Options: per-category toggles (Melee / Ranged / Spell / Regen / Defense detail / Weapon skills / Gear / Progress), "hide zero rows",
  and "replace Blizzard's max-only Hit/Crit/Haste rows" (remove those three entries from Blizzard's Modifiers category when ours are on).
- Taint: these tables and frames are not secure; nothing here calls protected functions. None of the stat APIs are marked
  secret-returning in the docs. Watch `/lode errors` on the first beta run anyway.
- Effort: **M** (one file for the stat functions, one for the injection/options, ~600 lines). No data dependencies.

## Part B — QoL gripes for Classic-style leveling (ranked)

Value 1–5, effort S/M/L. "done" = already shipped in the suite (see README).

| # | Gripe / feature | V | E | Needs (APIs / data) | Where |
|---|---|---|---|---|---|
| 1 | **Character sheet hidden stats** (Part A) | 5 | M | see Part A; all verified | new `Lodestar_Character` |
| 2 | **Mob / NPC quest relevance on tooltips** ("Starts quest X", "Objective of Y 3/10", "Drops Z for quest W") | 5 | M | `Lodestar_Guide/Data/Vanilla.lua` already has `quests[id].start.npcs / end.npcs / obj.npcs`, `items[id].npcs` → build a reverse `npcID → quests` index lazily; NPC id from `UnitGUID` (`Creature-0-…-<id>-…`); hook `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, …)` (UI, already used by Lodestar_UI); filter with `C_QuestLog.IsQuestFlaggedCompleted` / `IsOnQuest` NS and level window. `C_QuestLog.IsUnitOnQuest(questID, unit)` and `UnitIsRelatedToActiveQuest(unit)` NS cover active quests only. Blizzard's retail tooltip already prints active-quest progress lines on mobs — verify on Forever so we do not double up. **Coverage gap:** new Forever quests/mobs until the harvest fills them (`Harvest.lua` records NPC↔quest links) | Guide (data) + UI (tooltip) |
| 3 | **Legacy tracker** — LDB/minimap text "Legacy 12 earned · 7/16 spent · 2 new challenges", unspent-points nag on level-up, challenge-criteria toasts and a "closest challenges" list | 4 | M | `C_MajorFactions.GetCurrentRenownLevel(2802)`, `C_Traits.GetConfigIDByTreeID` + `GetTreeCurrencyInfo` (trees 1187/1188/1189, currency 4225), achievements API (`GetCategoryList`, `GetCategoryNumAchievements`, `GetAchievementInfo`, `GetAchievementNumCriteria`, `GetAchievementCriteriaInfo` INF), events `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`, `CRITERIA_UPDATE`, `ACHIEVEMENT_EARNED`, `TRAIT_TREE_CURRENCY_INFO_UPDATED`; Blizzard's own `LegacyChallengesUnviewed` saved var for the "new" dot. Guard everything for renown 0 (below level 25 the Blizzard UI itself errors) | new `Lodestar_Legacy` (small) or core |
| 4 | **Turn-ins-to-ding** ("3 turn-ins = level") in the XP tracker | 4 | S | `C_QuestLog.GetNumQuestLogEntries` / `GetInfo(i)` NS, `C_QuestLog.ReadyForTurnIn(questID)` NS, `GetQuestLogRewardXP()` INF after `C_QuestLog.SetSelectedQuest(questID)` (Blizzard's `QuestInfo.lua` pattern; `AM_QuestDialog.lua` passes the questID directly — try that first, fall back to select), `UnitXP/UnitXPMax` | Leveling (already in roadmap) |
| 5 | **Leveling status strip** in the XP tracker: bag slots free, lowest durability %, rested %, Well Fed / camp buffs present | 4 | S | `C_Container.CalculateTotalNumberOfFreeBagSlots()` NS, `GetInventoryItemDurability` INF, `GetXPExhaustion` GF, `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")` NS (names only; spell IDs for Well Fed/camp buffs must be harvested on beta — no public IDs yet). Events `BAG_UPDATE_DELAYED`, `UPDATE_INVENTORY_DURABILITY`, `UNIT_AURA` | Leveling |
| 6 | **Bag-space and repair warnings** (chat/UIErrors nag at ≤3 free slots / <20 % durability; "vendor nearby" hint from harvested NPC kinds) | 4 | S | as #5 plus harvest `npcs[].kind` (vendor/repair) and `C_Minimap` tracking (Blizzard already tracks Repair/Innkeeper/TaxiNode/Trainer/Auctioneer/Banker/Mailbox on camelot — `MinimapConstants.OPTIONAL_FILTERS`) | Economy |
| 7 | **Camp buff / Well Fed reminder** — on `PLAYER_UPDATE_RESTING` or when a campfire aura appears, list which camp buffs you lack; warn when a camp buff has <5 min left and you are still in the zone | 3 | M | aura spell IDs (harvest: record every new player buff gained while `IsResting()` and near a "Campfire" mouseover; store name→spellID in `LodestarScanDB`); `C_UnitAuras.GetPlayerAuraBySpellID` NS; camp cooldowns are not exposed by any API — track our own timestamps from `UNIT_SPELLCAST_SUCCEEDED` (object placement spells, IDs unknown) | new "Camp" section in Leveling |
| 8 | **Hearthstone suggestion** ("hearth: 3 turn-ins are within 200 yd of your inn, HS ready") | 3 | M | `GetBindLocation()` GF (name only) + harvest innkeeper positions matched by subzone; hearth cooldown `C_Container.GetItemCooldown(6948)` NS / `C_Item.GetItemCooldown` NS; `C_Container.PlayerHasHearthstone()`, `UseHearthstone()` NS (protected action — only suggest, or a secure button); Guide already has `.hs` steps and a router with hub positions | Guide (Smart) |
| 9 | **Flight-path tracker** — map pins for flight masters you have not learned, "FP not learned, 40 yd away" nudge, learned/unlearned list per continent | 3 | S | harvest already records taxi nodes seen (`TAXIMAP_OPENED`, `C_TaxiMap.GetAllTaxiNodes()` NS → `nodeID, name, position, state` where `Enum.FlightPathState` is only Current/Reachable/Unreachable — **unlearned nodes are not returned**, so "not learned" = flight master harvested but no node with that name seen on the taxi map) and flight masters (NPC kind); world-map pins via Guide's existing pin code; `NumTaxiNodes`, `TaxiNodeName` INF | Guide |
| 10 | **Auto-fill "DELETE" on rare+ item deletion** | 3 | S | camelot `GameEvent.HandleDeleteItemConfirm` shows `DELETE_GOOD_ITEM` / `DELETE_GOOD_QUEST_ITEM` (`hasEditBox`); hook `StaticPopupDialogs["DELETE_GOOD_ITEM"].OnShow` to `dialog.EditBox:SetText(DELETE_ITEM_CONFIRM_STRING)` and enable button 1 (Leatrix does this; `StaticPopupDialogs` UI global). Also offer "confirm rare loot roll / bind on pickup" hooks in the same place | UI |
| 11 | **Unspent talent points nag** on level-up and at login | 3 | S | `GetNumUnspentTalents()` INF (probe first) or `C_Traits.GetTreeCurrencyInfo(C_ClassTalents.GetActiveConfigID(), …)` NS; talent unlock level lowered by Legacy "Talented" (`PlayerSpellsMicroButtonMixin:GetTalentUnlockLevel()` UI) | Leveling |
| 12 | **Skill-cap / trainer reminders** (Cooking 74/75, First Aid capped, weapon skill lagging 10+ points, class trainer has new spells at this level) | 3 | S | `GetProfessions()`/`GetProfessionInfo(i)` INF (rank, maxRank), `C_SkillInfo.GetNumSkillLines/GetSkillLineInfo` NS for weapon skills, harvest trainer positions (`Data/Trainers.lua` exists); class trainer "new spells" needs a level→spell table (not available; harvest it at the trainer: `TRAINER_SHOW`, `GetNumTrainerServices`, `GetTrainerServiceInfo`, `GetTrainerServiceCost`, `IsTradeskillTrainer` are all INF — present, undocumented) | Leveling |
| 13 | **Quest log hygiene** — "log 19/20, these 3 are grey/trivial, abandon?" | 3 | S | `C_QuestLog.GetMaxNumQuestsCanAccept()`, `IsQuestTrivial(questID)`, `GetQuestDifficultyLevel`, `CanAbandonQuest`/`SetAbandonQuest`+`AbandonQuest` NS | Leveling |
| 14 | **"Already known / known by alt" on recipe tooltips** | 3 | M | record learned recipes per character when a tradeskill window opens: `C_TradeSkillUI.GetAllProfessionTradeSkillLines()`, `GetRecipeInfo(recipeID).learned` NS (`TRADE_SKILL_LIST_UPDATE`); the client's own "Already known" line covers this character. Mapping recipe *item* → recipe spell is the hard part: `C_Item.GetItemSpell(itemID)` NS gives the "teach" spell, not the craft; fall back to parsing the tooltip's "Use: Teaches you how to …" line (`TooltipDataProcessor` gives line text). Verify on beta before committing | Economy |
| 15 | **Corpse-run arrow** — point the Guide arrow at the corpse while a ghost | 3 | S | `C_DeathInfo.GetCorpseMapPosition(uiMapID)` NS, `UnitIsGhost("player")` GF; Guide arrow already takes arbitrary targets | Guide |
| 16 | **Guild board without addon comms** | 3 | M | Beta realm has `AreOutgoingAddonChatMessagesRestricted() == true` everywhere → Presence/LFG messages never send (`SendAddonMessage` → `AddOnMessageLockdown`). Fallback: roster-only board from `C_Club.GetClubMembers/GetMemberInfo` NS (level, zone, presence — become secret values under `C_ChatInfo.InChatMessagingLockdown()`), `/lode lfg` composes a guild chat line the user sends themselves (never auto-send chat: that is exactly the "automate communicating" class Blizzard restricts). Re-enable comms automatically if a launch realm reports `false` (`ADDON_RESTRICTION_STATE_CHANGED`, type `Chat`) | Guild + core Comm |
| 17 | **Mount-fund tracker** ("gold to riding: 34 g / 90 g") | 2 | S | `GetMoney()` GF; the training cost is not published (Blizzard: cost moved from mount to training) — configurable target, default filled in when harvested from a riding trainer (`TRAINER_SHOW` service costs) | Economy |
| 18 | **Bag vendor-value totals** ("greys 1 g 12 s, all 14 g") in the bag/minimap tooltip | 2 | S | `C_Container.GetContainerItemInfo` NS + `C_Item.GetItemInfo` sellPrice NS; Baganator/Bagnon own the bag UI, so keep it to a tooltip line | Economy |
| 19 | **Layer/shard change notice** ("world layer changed" in chat with timestamp — useful for rare/node camping) | 1 | S | events `SHARD_TRANSFER_IMMINENT`, `SHARD_TRANSFER` (Blizzard already pops a dialog) | UI |
| 20 | **Minimap gathering nodes** | 4 | L | **No Forever node data exists.** Would need: harvest node positions from `UNIT_SPELLCAST_SUCCEEDED` (player, Herb Gathering / Mining spell IDs — verify on beta) + `C_Map.GetPlayerMapPosition`, name from the last world-object `GameTooltip` text; minimap pins need a HereBeDragons-style rotating-minimap projection (not embedded yet; `C_Minimap.GetViewRadius`, `IsRotateMinimapIgnored` NS exist). Big data + UI job; defer until the harvest has weeks of data | new `Lodestar_Nodes` |
| 21 | **Auto-dismount on cast/interact** | 2 | S | Camelot removes the auto-dismount setting entirely (`ControlsOverrides.SetupAutoDismountSetting` is empty) — the retail engine dismounts on cast by itself; verify on beta. If a "You are mounted" error shows up, hook `UI_ERROR_MESSAGE` and call `Dismount()` GF (not protected) | UI (only if needed) |
| 22 | Screenshot cleanup | 0 | – | impossible from Lua (no filesystem); only `SCREENSHOT_SUCCEEDED` toast | drop |
| 23 | Hunter pet happiness/feed reminder (Classic pet system is back: `C_PetInfo.GetPetHappiness`, `GetPetLoyalty`, `GetPetTrainingPoints`, `CanPetEatItem`, `GetPetFoodTypes` NS) | 3 | S | events `UNIT_HAPPINESS`, `PET_UI_UPDATE` (both present); food types → matching bag items via `C_Container.GetContainerItemInfo` | Leveling (Hunter only) |
| — | Vendor/AH prices, auto-sell, auto-repair, quest automation, fast loot, coords, IDs, chat links/timestamps/copy, XP/hr, time-per-level, `/way`, arrow, guides, recorder, harvest, trails | — | — | **done** | — |

Not worth building (Blizzard already has it on camelot): minimap tracking of repair/innkeeper/flight/trainer/auctioneer/banker/mailbox,
trivial-quest filter, interact-with-target key, day/night dial, quest-item buttons in the tracker, transmog, collections journal,
Blizzard damage meter & cooldown viewer, nameplate levels.

## Part C — the next ten, in order

1. **Lodestar_Character (Part A).** The owner's headline ask; every API is verified in Blizzard's own camelot code; no data dependency; no competing Forever addon exists.
2. **Quest relevance on mob/NPC tooltips (#2).** The single Questie feature people miss most, and we already own the data (pfQuest import + harvest); Questie has no Forever build.
3. **Turn-ins-to-ding (#4).** Small, already on the roadmap, makes the XP tracker feel smart.
4. **Leveling status strip (#5) + bag/repair warnings (#6).** One event set (bags, durability, rested, auras) feeds both; ships as XP-tracker rows plus chat nags.
5. **Legacy tracker (#3).** Forever's signature system; the constants (trees 1187/1188/1189, currency 4225, faction 2802) are read straight from Blizzard's code, and no addon covers it yet.
6. **Guild board comm fallback (#16).** Not a feature, a fix: on this realm nothing we send arrives, so the board and the version-announce must degrade gracefully before launch.
7. **DELETE auto-fill + confirm-popup helpers (#10).** Fifteen minutes of work, high daily annoyance.
8. **Unspent talent / skill-cap / trainer reminders (#11, #12).** Cheap, uses `C_Traits`/`C_SkillInfo`/harvested trainers; complements the guide's `.train` steps.
9. **Flight-path tracker + hearthstone suggestion (#9, #8).** Both ride on harvest data the Guide already collects; the arrow and pins exist.
10. **Camp buff / Well Fed reminder (#7).** Forever-specific and visible, but blocked on harvesting aura IDs from the beta first — start the harvest hook now, ship the reminder when the table has entries.

Deferred: minimap gathering nodes (#20, needs months of data), recipe-known-by-alt (#14, needs the item→recipe mapping verified), pet reminders (#23).

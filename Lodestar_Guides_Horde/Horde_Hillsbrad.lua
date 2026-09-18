-- Lodestar Guides: Horde — Hillsbrad Foothills (levels 20-25), the continuation of the Silverpine route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Tarren Mill loops: west (the gray bears and moss
-- creepers on the hills, the Hillsbrad Fields for Battle of Hillsbrad, Deathstalker Lesh at Azurelode
-- Mine), east (the Syndicate camp and Durnholde Keep: WANTED, The Rescue), west again (the mountain
-- lions, the peasants, the skulls, Stanley), west a third time (the blacksmiths and the Shipment of
-- Iron), then the Undercity for training and the zeppelin to Kalimdor. Every quest id and position
-- comes from the data; the order still has to be verified in play (/lode record).
--
-- Left out on purpose: the Alterac Mountains (the Syndicate, Crushridge and Dalaran quests Tarren
-- Mill hands out for Alterac start at level 30+), Dun Garok (Battle of Hillsbrad parts 6-7, level
-- 28-30, Captain Ironhill lvl 32 — the 30+ guide), the Elixir of Agony chain past part 2 (level 30
-- murlocs), the rogue poison quest (Hinott's Assistance needs its Orgrimmar prologue) and Blood of
-- Innocents (needs Journey to Tarren Mill from Apothecary Zamah in Thunder Bluff — optional here).
-- Tarren Mill has no class trainer in Vanilla; the training trip is the Undercity at the end.
--
-- Auto-pick: #levels is 20-23 on both this guide and the Stonetalon guide (a level 24 character is
-- handed to Ashenvale). Engine.PickGuide breaks the tie between two equally generic Horde guides by
-- registration order, which is the TOC order (Stonetalon first); Undead characters arrive here through
-- the Silverpine guide's #next, which LoadGuide follows on finish regardless of level.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 20-25: Hillsbrad Foothills
#faction Horde
#levels 20-23
#next Horde 25-30: Ashenvale
#author Lodestar
-- #levels stops at 23 so the auto-pick hands a level 24 character to Ashenvale; by the XP tables the quests here run 20 to about 23, the optional ones and Shadowfang Keep to 24.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Tarren Mill: first visit ---------------------------------------------------------------------------------------

step
  .goto Hillsbrad Foothills,61.4,19.1
  .turnin 493 >>Turn in Journey to Hillsbrad Foothills to Apothecary Lydon in Tarren Mill (if you brought it from the Sepulcher)
  .accept 496 >>Accept Elixir of Suffering

step
  .goto Hillsbrad Foothills,63.2,20.7
  .accept 498 >>Accept The Rescue from Krusk, the orc by the east side of the town

step
  .goto Hillsbrad Foothills,62.6,20.8
  .accept 549 >>Accept WANTED: Syndicate Personnel from the poster on the town hall wall

step
  .goto Hillsbrad Foothills,62.3,20.3
  .accept 527 >>Accept Battle of Hillsbrad from High Executor Darthalia, in front of the town hall

step
  .goto Hillsbrad Foothills,62.8,19.0
  .hs Tarren Mill >>Set your hearthstone at the Tarren Mill inn (Innkeeper Shay)
  .vendor

step
  .goto Hillsbrad Foothills,60.1,18.6
  .text >>Talk to Zarise, the bat handler on the west side of Tarren Mill, to learn the flight path

-- West loop 1: the bears and creepers on the hills, the Hillsbrad Fields, Azurelode Mine ----------------------------------

step
  .goto Hillsbrad Foothills,56.9,28.9
  .complete 496,1 >>Loot 5 Gray Bear Tongues from Gray Bears (lvl 21-22) on the hills south-west of Tarren Mill, north of the road (80% drop)

step
  .goto Hillsbrad Foothills,56.5,30.1
  .complete 496,2 >>Loot 5 Creeper Ichor from Forest Moss Creepers (lvl 20-21) on the same hills — a slow drop (about 1 in 6), so kill every creeper you pass; Giant Moss Creepers (lvl 24-25) further west drop it too

step
  .goto Hillsbrad Foothills,33.2,34.8
  .complete 527 >>Battle of Hillsbrad at the Hillsbrad Fields, the human farms in the west: kill Farmer Ray (lvl 23) at the north-west farmhouse, Farmer Getz (lvl 24) at the farm south-east of him (36.7,39.4), and the Hillsbrad Farmhands (lvl 22-23) and Farmers (lvl 23-24) working the fields between them — stay out of the town hall (lvl 25-30) for now

step
  .goto Hillsbrad Foothills,20.8,47.4
  .accept 494 >>Accept Time To Strike from Deathstalker Lesh, hiding on the hillside above Azurelode Mine, west of the fields (the miners in the mine are lvl 26-29 — do not go in)

-- Tarren Mill: second visit -----------------------------------------------------------------------------------------

step
  .goto Hillsbrad Foothills,62.3,20.3
  .turnin 527 >>Turn in Battle of Hillsbrad to High Executor Darthalia (hearth or walk back to Tarren Mill)
  .turnin 494 >>Turn in Time To Strike
  .accept 528 >>Accept Battle of Hillsbrad (part 2)

step
  .goto Hillsbrad Foothills,62.1,19.7
  .accept 546 >>Accept Souvenirs of Death from Deathguard Samsa, by the inn

step
  .goto Hillsbrad Foothills,61.4,19.1
  .turnin 496 >>Turn in Elixir of Suffering to Apothecary Lydon
  .accept 499 >>Accept Elixir of Suffering (part 2) — a hand-off to Umpi, next to him

step
  .goto Hillsbrad Foothills,61.5,19.2
  .turnin 499 >>Turn in Elixir of Suffering to Umpi, Lydon's troll

step
  .goto Hillsbrad Foothills,62.6,19.7
  .optional >>Dangerous!: four named humans of lvl 25-29 around the fields and the mine — take it with the later field loops if you are 24+ or have a partner
  .accept 567 >>Accept Dangerous! from the poster by the inn

step
  .goto Hillsbrad Foothills,61.4,19.1
  .optional >>Blood of Innocents is only offered after Journey to Tarren Mill (Apothecary Zamah, Thunder Bluff — the Grimtotem/Forsaken chain); if Lydon has it for you, the Syndicate Shadow Mages at Durnholde drop the vials
  .accept 1066 >>Accept Blood of Innocents from Apothecary Lydon

-- East loop: the Syndicate camp and Durnholde Keep -------------------------------------------------------------------

step
  .goto Hillsbrad Foothills,66.1,45.7
  .complete 549 >>Kill Syndicate Watchmen (lvl 20-21) and Syndicate Rogues (lvl 21-22): start at the Syndicate camp on the hills south-east of Tarren Mill, then work east into Durnholde Keep, the ruined fort in the east (75-84,37-47). The Shadow Mages there also drop Hillsbrad Human Skulls for Souvenirs of Death — loot everything

step
  .goto Hillsbrad Foothills,79.6,41.8
  .complete 498 >>The Rescue, inside Durnholde Keep: kill Jailor Eston (lvl 24) for the Dull Iron Key and Jailor Marlgen (lvl 24, north of him at 79.8,40.2) for the Burnished Gold Key, then open the two Locked balls and chains of the prisoners — one at 79.8,39.6 by Marlgen, one at 75.3,41.5 at the west end of the keep

step
  .goto Hillsbrad Foothills,76.6,42.9
  .optional >>Blood of Innocents
  .complete 1066,1 >>Loot Vials of Innocent Blood from the Syndicate Shadow Mages (lvl 21-22) in Durnholde Keep (80% drop)

-- Tarren Mill: third visit --------------------------------------------------------------------------------------------

step
  .goto Hillsbrad Foothills,62.3,20.3
  .turnin 549 >>Turn in WANTED: Syndicate Personnel to High Executor Darthalia (hearth or walk back to Tarren Mill)

step
  .goto Hillsbrad Foothills,63.2,20.7
  .turnin 498 >>Turn in The Rescue to Krusk

step
  .goto Hillsbrad Foothills,61.4,19.1
  .xp 21 >>You should be level 21 by now (if not, the Syndicate at Durnholde are quick kills)
  .accept 501 >>Accept Elixir of Pain from Apothecary Lydon (level 21)

step
  .goto Hillsbrad Foothills,61.4,19.1
  .optional >>Blood of Innocents
  .turnin 1066 >>Turn in Blood of Innocents to Apothecary Lydon (his follow-up, Return to Thunder Bluff, is a hand-off to Apothecary Zamah — take it if you will be in Thunder Bluff anyway)

step
  .goto Hillsbrad Foothills,62.8,19.0
  .vendor >>Sell, repair and restock at the inn

-- West loop 2: the mountain lions, the peasants, the skulls, Stanley --------------------------------------------------------

step
  .goto Hillsbrad Foothills,50.2,41.3
  .complete 501,1 >>Loot 5 Mountain Lion Blood from Starving Mountain Lions (lvl 23-24) on the hills between Tarren Mill and the fields (50,41 and 37.8,36.2; 80% drop)

step
  .goto Hillsbrad Foothills,34.7,44.9
  .complete 528,1 >>Kill Hillsbrad Peasants (lvl 24-25) in the southern half of the Hillsbrad Fields (30-36,40-46)

step
  .goto Hillsbrad Foothills,33.7,40.1
  .complete 546,1 >>Loot 20 Hillsbrad Human Skulls from the farmers, farmhands and peasants of the fields (you will have some from the Syndicate already; about 3 in 4 drop one)

step
  .goto Hillsbrad Foothills,32.6,39.8
  .optional >>Dangerous!
  .complete 567 >>Kill Citizen Wilkes (lvl 25) in the fields at 32.6,39.8, Farmer Kalaba (lvl 25) at the southern farm (36,46.5), Clerk Horrace Whitesteed (lvl 26) in the town hall (29.8,42.4) and Miner Hackett (lvl 29) in Azurelode Mine (31.1,58.6) — Hackett is the dangerous one, leave him for level 26+

-- Tarren Mill: fourth visit ------------------------------------------------------------------------------------------

step
  .goto Hillsbrad Foothills,62.3,20.3
  .turnin 528 >>Turn in Battle of Hillsbrad to High Executor Darthalia (hearth or walk back)
  .accept 529 >>Accept Battle of Hillsbrad (part 3)

step
  .goto Hillsbrad Foothills,62.1,19.7
  .turnin 546 >>Turn in Souvenirs of Death to Deathguard Samsa

step
  .goto Hillsbrad Foothills,61.4,19.1
  .turnin 501 >>Turn in Elixir of Pain to Apothecary Lydon
  .accept 502 >>Accept Elixir of Pain (part 2) — for Stanley, Farmer Ray's dog at the fields

step
  .goto Hillsbrad Foothills,62.3,20.3
  .optional >>Dangerous!
  .turnin 567 >>Turn in Dangerous! to High Executor Darthalia

-- West loop 3: the blacksmiths, the Shipment of Iron, Stanley, the town hall (optional) ----------------------------------

step
  .goto Hillsbrad Foothills,32.0,45.8
  .complete 529 >>Kill Hillsbrad Apprentice Blacksmiths (lvl 24-25) at the smithy in the south-west of the fields, Blacksmith Verringtan (lvl 26) among them, and take the Shipment of Iron from the crate next to the forge (32,45.4)

step
  .goto Hillsbrad Foothills,32.7,35.3
  .turnin 502 >>Feed the Elixir of Pain to Stanley, the dog at Farmer Ray's farmhouse in the north-west of the fields

step
  .goto Hillsbrad Foothills,62.3,20.3
  .xp 22
  .turnin 529 >>Turn in Battle of Hillsbrad to High Executor Darthalia (hearth or walk back to Tarren Mill)

step
  .goto Hillsbrad Foothills,62.3,20.3
  .optional >>Battle of Hillsbrad (part 4): the Hillsbrad Councilmen (lvl 25-26) and Magistrate Burnside (lvl 30) in the town hall — bring a partner or come back at 26+; parts 5-7 (the mine and Dun Garok) are level 28-30 and belong to a later guide
  .accept 532 >>Accept Battle of Hillsbrad (part 4) from High Executor Darthalia

step
  .goto Hillsbrad Foothills,29.7,41.6
  .optional >>Battle of Hillsbrad (part 4)
  .complete 532 >>In the Hillsbrad town hall: kill the Hillsbrad Councilmen (lvl 25-26) and Magistrate Burnside (lvl 30, upstairs), take the Hillsbrad Town Registry from the desk (29.5,41.5) and post the Hillsbrad Proclamation on the wall (29.7,41.7)

step
  .goto Hillsbrad Foothills,62.3,20.3
  .optional >>Battle of Hillsbrad (part 4)
  .turnin 532 >>Turn in Battle of Hillsbrad to High Executor Darthalia

-- Level 23: Elixir of Agony (optional, level 24), then the Undercity and the zeppelin to Kalimdor -----------------------------------

step
  .goto Hillsbrad Foothills,61.4,19.1
  .xp 23 >>You should be level 23 by now — Tarren Mill's quests for this band run out here. Ashenvale's Horde quests start at 20-24, so move on; if you would rather be 24 first, the Syndicate at Durnholde Keep and the humans of the fields are the grind, and Shadowfang Keep is a good run at this level

step
  .goto Hillsbrad Foothills,61.4,19.1
  .optional >>Elixir of Agony (level 24): Mudsnout Blossoms from the gnoll camp in the south-east (gnolls lvl 26-28), then a hand-off to Faranell in the Undercity, where you are going anyway — skip it with Next if you are not 24
  .xp 24
  .accept 509 >>Accept Elixir of Agony from Apothecary Lydon (level 24)

step
  .goto Hillsbrad Foothills,64.6,61.3
  .optional >>Elixir of Agony
  .complete 509,1 >>Pick Mudsnout Blossoms, the plants growing in the Mudsnout gnoll camp far south of Tarren Mill, beyond the east-west road (63-66,59-63; Mudsnout Gnolls lvl 26-27, Shamans lvl 27-28 — pick around the edge)

step
  .goto Hillsbrad Foothills,61.4,19.1
  .optional >>Elixir of Agony
  .turnin 509 >>Turn in Elixir of Agony to Apothecary Lydon (hearth or walk back)
  .accept 513 >>Accept Elixir of Agony (part 2) — for Master Apothecary Faranell in the Undercity

step
  .goto Hillsbrad Foothills,60.1,18.6
  .fly Undercity >>Fly to the Undercity with Zarise

step
  .goto Undercity,63.3,48.6
  .train >>Train new skills at your class trainer in the Undercity (War Quarter for warriors, the Magic Quarter for mages, warlocks and priests, the Rogues' Quarter), sell and repair

step
  .goto Undercity,48.8,69.3
  .optional >>Elixir of Agony
  .turnin 513 >>Turn in Elixir of Agony to Master Apothecary Faranell in the Apothecarium (his follow-up, part 3, is level 30 — leave it)

step
  .goto Tirisfal Glades,60.7,58.9
  .text >>Leave the Undercity through the Ruins of Lordaeron and walk to the zeppelin tower just outside, to the east (Zapetta stands at its foot). Take the zeppelin to Orgrimmar (the platform on the Orgrimmar side of the tower — the other one goes to Grom'gol); it lands at the tower outside Orgrimmar's front gate in Durotar

step
  .goto Orgrimmar,37.6,75.4
  .optional >>The Ashenvale Hunt: an Orgrimmar breadcrumb that unlocks Senani Thunderheart's three elite hunts in Ashenvale (group quests, optional there too)
  .accept 235 >>Accept The Ashenvale Hunt from Warcaller Gorlach, just inside Orgrimmar's front gate

step
  .goto Orgrimmar,45.1,63.9
  .text >>Talk to Doras, the wind rider master on the rise above the Valley of Strength, to learn the Orgrimmar flight path (train here too if you skipped the Undercity trainers). Then leave by the front gate: the road runs south-west through Durotar, over the bridge at Far Watch Post into the Barrens, and on to the Crossroads

step
  .goto The Barrens,51.5,30.9
  .accept 6541 >>Accept Report to Kadrak from Thork at the north entrance of the Crossroads — he is the first Horde post inside Ashenvale. Talk to Devrak by the inn to learn the Crossroads flight path

step
  .zone Ashenvale >>Follow the road north out of the Crossroads, through the Mor'shan Rampart at the top of the Barrens, into Ashenvale — Kadrak stands just past the rampart
]], "Lodestar_Guides_Horde")

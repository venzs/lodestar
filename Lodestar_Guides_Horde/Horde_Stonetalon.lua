-- Lodestar Guides: Horde — Stonetalon Mountains (levels 20-25), the continuation of the Barrens route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Horde loops: Camp Aparaje and Grimtotem Post at the
-- Barrens entrance (Makaba's Grimtotem quests, Kaya's escort), Malaka'jin, the Webwinder Path north
-- (Blood Feeders, Besseleth), Sun Rock Retreat as the hub, a south loop for Boulderslide Ravine and
-- the Malaka'jin turn-in, an east loop into Windshear Crag (Piznik, Ziz Fizziks), the Gaea Seeds
-- around Mirkfallon Lake, then the Charred Vale (harpies, flame spirits, the dirt mounds). Stonetalon
-- Peak and Jin'Zil's beasts are optional. Every quest id and position comes from the data; the order
-- still has to be verified in play (/lode record).
--
-- Left out on purpose: Goblin Invaders / Shredding Machines (need The Spirits of Stonetalon from
-- Zor Lonetree in Orgrimmar, which no guide in the chain picks up), the Ziz Fizziks chain past Super
-- Reaper 6000 (Ratchet hand-offs), Reclaiming the Charred Vale (Alliance prologue), Test of Lore
-- (level 30), the warlock Dogran chain, and the Alliance camp at Windshear Crag (Gaxim, Kaela).
-- Sun Rock Retreat has no class trainer in Vanilla; the training trip is Thunder Bluff / Orgrimmar at
-- the end, before flying to the Crossroads for Ashenvale.
--
-- Auto-pick: #levels is 20-23 on both this guide and the Hillsbrad guide (a level 24 character is
-- handed to Ashenvale). Engine.PickGuide breaks the tie between two equally generic Horde guides by
-- registration order, which is the TOC order (this guide is listed first, so a fresh Horde character
-- at 20-23 auto-picks Stonetalon); the Barrens guide's #next brings Kalimdor characters here anyway.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 20-25: Stonetalon Mountains
#faction Horde
#levels 20-23
#next Horde 25-30: Ashenvale
#author Lodestar
-- #levels stops at 23 so the auto-pick hands a level 24 character to Ashenvale; by the XP tables the quests here run 20 to about 22-23, the optional ones to 24.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Camp Aparaje and Grimtotem Post: the Barrens entrance --------------------------------------------------------------

step
  .goto Stonetalon Mountains,85.8,97.7
  .accept 6548 >>Accept Avenge My Village from Makaba Flathoof at Camp Aparaje, where the road from the Barrens enters Stonetalon

step
  .goto Stonetalon Mountains,82.4,87.9
  .complete 6548 >>Kill Grimtotem Ruffians and Grimtotem Mercenaries (lvl 14-15) at the Grimtotem camps along the road north-west of Camp Aparaje — low XP, but they die fast

step
  .goto Stonetalon Mountains,73.5,85.6
  .accept 6523 >>Accept Protect Kaya from Kaya Flathoof, held at Grimtotem Post, the hostile camp further up the road, and escort her back to Camp Aparaje (Grimtotem ambushes, lvl 14-16 — kill Grundig's guards on the way if they aggro)

step
  .goto Stonetalon Mountains,85.8,97.7
  .turnin 6523 >>Turn in Protect Kaya to Makaba Flathoof at Camp Aparaje
  .turnin 6548 >>Turn in Avenge My Village
  .accept 6629 >>Accept Kill Grundig Darkcloud
  .accept 6401 >>Accept Kaya's Alive — a hand-off to Tammra Windfield at Sun Rock Retreat

step
  .goto Stonetalon Mountains,73.6,86.1
  .complete 6629 >>Back at Grimtotem Post: kill Grundig Darkcloud (lvl 18) and the Grimtotem Brutes (lvl 15-16) around him

step
  .goto Stonetalon Mountains,85.8,97.7
  .turnin 6629 >>Turn in Kill Grundig Darkcloud to Makaba Flathoof

-- Malaka'jin -------------------------------------------------------------------------------------------------------------

step
  .goto Stonetalon Mountains,71.2,95.0
  .accept 6461 >>Accept Blood Feeders from Xen'Zilla in Malaka'jin, the troll camp at the west end of the road

step
  .goto Stonetalon Mountains,73.2,94.9
  .accept 6542 >>Accept Report to Kadrak from Darn Talongrip — a hand-off to Kadrak at the Ashenvale border, turned in by the next guide

step
  .goto Stonetalon Mountains,74.5,97.9
  .optional >>Jin'Zil's Forest Magic: four beast parts from the animals around Stonetalon Peak in the far north-west (lvl 22-27), and the turn-in is back here — only worth it with the Stonetalon Peak trip at the end
  .accept 1058 >>Accept Jin'Zil's Forest Magic from Witch Doctor Jin'Zil, on the hill above Malaka'jin (level 20)

-- The Webwinder Path north: creepers, Besseleth, venomspitters ----------------------------------------------------------------

step
  .goto Stonetalon Mountains,64.8,83.5
  .complete 6461,1 >>Kill Deepmoss Creepers (lvl 16-17) along the Webwinder Path, the spider trail that climbs north-west from Malaka'jin

step
  .goto Stonetalon Mountains,59.1,75.7
  .accept 6284 >>Accept Arachnophobia from the Wanted poster beside the path

step
  .goto Stonetalon Mountains,52.0,73.9
  .complete 6284,1 >>Kill Besseleth (lvl 21) in the spider hollow west of the path and take her fang

step
  .goto Stonetalon Mountains,52.8,75.6
  .complete 6461,2 >>Kill Deepmoss Venomspitters (lvl 17-18) around Besseleth's hollow and along the path north to Sun Rock (54,61)

-- Sun Rock Retreat: the hub ----------------------------------------------------------------------------------------------

step
  .goto Stonetalon Mountains,47.2,61.2
  .turnin 6284 >>Turn in Arachnophobia to Maggran Earthbinder in Sun Rock Retreat, the tauren town on the lake
  .accept 6282 >>Accept Harpies Threaten

step
  .goto Stonetalon Mountains,47.5,58.4
  .turnin 6401 >>Turn in Kaya's Alive to Tammra Windfield, on the north side of the town
  .accept 6301 >>Accept Cycle of Rebirth

step
  .goto Stonetalon Mountains,47.2,64.0
  .accept 6421 >>Accept Boulderslide Ravine from Mor'rogal, south side of the town

step
  .goto Stonetalon Mountains,47.4,64.3
  .accept 6562 >>Accept Trouble in the Deeps from Tsunaman, next to Mor'rogal — a hand-off to Je'neu Sancrea at Zoram'gar Outpost in Ashenvale, turned in by the next guide
  .accept 6393 >>Accept Elemental War

step
  .goto Stonetalon Mountains,45.9,60.4
  .optional >>Cenarius' Legacy: dryads and keepers (lvl 23-25) at Stonetalon Peak in the far north-west; its follow-ups (Ordanus in Ashenvale, The Den) are level 29
  .accept 1087 >>Accept Cenarius' Legacy from Braelyn Firehand, the orc on the west side of the town (level 20)

step
  .goto Stonetalon Mountains,47.5,62.1
  .hs Sun Rock Retreat >>Set your hearthstone at the Sun Rock Retreat inn (Innkeeper Jayka)
  .vendor

step
  .goto Stonetalon Mountains,45.1,59.8
  .text >>Talk to Tharm, the wind rider master on the west side of the town, to learn the Sun Rock Retreat flight path

-- South loop: Boulderslide Ravine, then Malaka'jin for the Blood Feeders turn-in --------------------------------------------------

step
  .goto Stonetalon Mountains,58.2,89.5
  .complete 6421 >>Walk back down the Webwinder Path to Boulderslide Ravine, the cave in the south-east near Malaka'jin (its entrance is south of the path's lower end), and pick up 5 Resonite Crystals from the ground inside (Deepmoss spiders lvl 16-18 on the way; Gogger Rock Keepers, Geomancers and Stonepounders lvl 16-18 in the cave — the Hatefury satyrs west of the entrance are lvl 31-33, stay clear of them)

step
  .goto Stonetalon Mountains,71.2,95.0
  .turnin 6461 >>Turn in Blood Feeders to Xen'Zilla in Malaka'jin, a short walk east of the ravine

step
  .goto Stonetalon Mountains,47.2,64.0
  .turnin 6421 >>Turn in Boulderslide Ravine to Mor'rogal (hearth to Sun Rock Retreat)

step
  .goto Stonetalon Mountains,47.2,64.0
  .optional >>Earthen Arise: a second trip to Boulderslide Ravine to wake Goggeroc (lvl 20) with the crystal — good XP, long walk; do it if you leave Stonetalon by road
  .accept 6481 >>Accept Earthen Arise from Mor'rogal

-- East loop: Windshear Crag — Ziz Fizziks, Piznik, the Venture Co. -----------------------------------------------------------

step
  .goto Stonetalon Mountains,59.0,62.6
  .optional >>Super Reaper 6000 is only offered after the Ziz Fizziks breadcrumb from Sputtervalve in Ratchet; if Ziz has it for you, the blueprints drop from the Venture Co. Operators at Windshear Crag (about 1 in 6)
  .accept 1093 >>Accept Super Reaper 6000 from Ziz Fizziks, the goblin by the road east of Sun Rock Retreat

step
  .goto Stonetalon Mountains,71.9,60.0
  .accept 1090 >>Accept Gerenzo's Orders from Piznik, the goblin at the mine on the east side of Windshear Crag (Venture Co. loggers lvl 18-19 and operators lvl 19-20 across the crag)

step
  .goto Stonetalon Mountains,71.9,60.0
  .complete 1090 >>Tell Piznik you are ready and defend him while he mines — Venture Co. Miners (lvl 19-20) come in three waves; keep them off him

step
  .goto Stonetalon Mountains,71.9,60.0
  .turnin 1090 >>Turn in Gerenzo's Orders to Piznik
  .accept 1092 >>Accept Gerenzo's Orders (part 2) — a hand-off to Ziz Fizziks

step
  .goto Stonetalon Mountains,67.1,52.4
  .optional >>Super Reaper 6000
  .complete 1093,1 >>Loot the Super Reaper 6000 Blueprints from Venture Co. Operators (lvl 19-20) at the logging camps north of the crag (67,52 and 71,42)

step
  .goto Stonetalon Mountains,59.0,62.6
  .turnin 1092 >>Turn in Gerenzo's Orders to Ziz Fizziks on the way back to Sun Rock Retreat

step
  .goto Stonetalon Mountains,59.0,62.6
  .optional >>Super Reaper 6000
  .turnin 1093 >>Turn in Super Reaper 6000 to Ziz Fizziks (his follow-up, Further Instructions, is a hand-off to Ratchet — skip it)

-- North loop: the Gaea Seeds around Mirkfallon Lake --------------------------------------------------------------------------

step
  .goto Stonetalon Mountains,48.0,39.8
  .complete 6301,1 >>Pick up Gaea Seeds, the small plants scattered around Mirkfallon Lake north of Sun Rock Retreat (46-51,36-45; Deepmoss Venomspitters lvl 17-18 and Pridewings lvl 19-21 around the shore)

step
  .goto Stonetalon Mountains,47.5,58.4
  .turnin 6301 >>Turn in Cycle of Rebirth to Tammra Windfield (walk back south to Sun Rock Retreat)
  .accept 6381 >>Accept New Life

-- West loop: the Charred Vale ----------------------------------------------------------------------------------------------

step
  .goto Stonetalon Mountains,35.1,53.1
  .xp 21
  .complete 6393,1 >>Loot Incendrites from the Rogue Flame Spirits (lvl 23-24) on the burnt slopes at the north-east edge of the Charred Vale, west of Sun Rock (35,53 and 34,64; Burning Ravagers lvl 24-25 deeper in drop them too; 80%)

step
  .goto Stonetalon Mountains,32.6,60.7
  .complete 6282 >>Kill Bloodfury Harpies and Ambushers (lvl 23-24) on the east side of the Charred Vale, then Bloodfury Roguefeathers and Slayers (lvl 25-26) further west (30,69) — pull one at a time, the harpies fly in groups

step
  .goto Stonetalon Mountains,34.2,61.3
  .complete 6381,1 >>Plant Tammra's seeds at the Gaea Dirt Mounds spread across the Charred Vale (34.2,61.3; 37.8,66.2; 32.2,68.2; 36.6,74.4; 29.1,68.9 and more) — work them in with the harpy kills

step
  .goto Stonetalon Mountains,47.2,61.2
  .turnin 6282 >>Turn in Harpies Threaten to Maggran Earthbinder (hearth or walk back to Sun Rock Retreat)

step
  .goto Stonetalon Mountains,47.2,61.2
  .optional >>Bloodfury Bloodline: Bloodfury Ripper (lvl 26) at the east edge of the Charred Vale — fine at 24, risky at 22
  .accept 6283 >>Accept Bloodfury Bloodline from Maggran Earthbinder

step
  .goto Stonetalon Mountains,47.4,64.3
  .turnin 6393 >>Turn in Elemental War to Tsunaman

step
  .goto Stonetalon Mountains,47.5,58.4
  .turnin 6381 >>Turn in New Life to Tammra Windfield

step
  .goto Stonetalon Mountains,30.8,61.9
  .optional >>Bloodfury Bloodline
  .complete 6283,1 >>Kill Bloodfury Ripper (lvl 26) on the ledge at the east side of the Charred Vale and loot her remains

step
  .goto Stonetalon Mountains,47.2,61.2
  .optional >>Bloodfury Bloodline
  .turnin 6283 >>Turn in Bloodfury Bloodline to Maggran Earthbinder

-- Optional: Stonetalon Peak — Cenarius' Legacy and Jin'Zil's beasts ------------------------------------------------------------

step
  .goto Stonetalon Mountains,36.1,14.4
  .optional >>Cenarius' Legacy
  .complete 1087 >>Follow the road north out of the Charred Vale to Stonetalon Peak and kill Cenarion Botanists (lvl 23-24), Daughters of Cenarius (lvl 23-25) and Sons of Cenarius (lvl 24-25) in the grove below the peak (35-38,10-16) — the night elf outpost at the top is Alliance, stay out of it

step
  .goto Stonetalon Mountains,39.8,13.8
  .optional >>Jin'Zil's Forest Magic
  .complete 1058 >>Around Stonetalon Peak and the road south of it: Stonetalon Sap from Sap Beasts (lvl 22-23), Fey Dragon Scales from Fey Dragons (lvl 24-25, 37-40,13-21), Twilight Whiskers from Twilight Runners (lvl 23-24) and Courser Eyes from Antlered Coursers (lvl 22-23) — all about 80%

step
  .goto Stonetalon Mountains,45.9,60.4
  .optional >>Cenarius' Legacy
  .turnin 1087 >>Turn in Cenarius' Legacy to Braelyn Firehand in Sun Rock Retreat (hearth if it is ready; Ordanus and The Den, her follow-ups, are level 29 — leave them)

-- Level 23: Calling in the Reserves, then Thunder Bluff / Orgrimmar to train and the road to Ashenvale ------------------------------

step
  .goto Stonetalon Mountains,47.2,61.2
  .xp 22 >>You should be level 22-23 by now — Sun Rock's quests for this band run out here. Ashenvale's Horde quests start at 20-24, so move on; if you would rather be 23-24 first, the harpies of the Charred Vale and the Venture Co. at Windshear Crag are the grind, and the optional quests above are worth it

step
  .goto Stonetalon Mountains,47.2,61.2
  .xp 23
  .accept 5881 >>Accept Calling in the Reserves from Maggran Earthbinder (level 23 — skip it with Next if you are not 23 yet): a hand-off to Grish Longrunner at the Great Lift into Thousand Needles, turned in two guides from now; it sits in the log until then

step
  .goto Stonetalon Mountains,58.2,89.5
  .optional >>Earthen Arise
  .complete 6481,1 >>Back in Boulderslide Ravine: use the Resonite Crystal at the back of the cave to wake Goggeroc (lvl 20) and kill him

step
  .goto Stonetalon Mountains,47.2,64.0
  .optional >>Earthen Arise
  .turnin 6481 >>Turn in Earthen Arise to Mor'rogal

step
  .goto Stonetalon Mountains,74.5,97.9
  .optional >>Jin'Zil's Forest Magic
  .turnin 1058 >>Turn in Jin'Zil's Forest Magic to Witch Doctor Jin'Zil at Malaka'jin (only if you are leaving by the Barrens road anyway)

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .fly Thunder Bluff >>Fly from Sun Rock Retreat to Thunder Bluff

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .train >>Train new skills at your class trainer in Thunder Bluff, sell and repair, then fly to the Crossroads

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .fly Orgrimmar >>Fly from Sun Rock Retreat to Orgrimmar (the wind riders route you through the Crossroads)

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .train >>Train new skills at your class trainer in Orgrimmar, sell and repair, then fly back to the Crossroads

step
  .goto The Barrens,51.5,30.9
  .fly The Crossroads >>Fly to the Crossroads. Then follow the road north out of the Crossroads to the Mor'shan Rampart at the top of the Barrens

step
  .zone Ashenvale >>Walk north through the Mor'shan Rampart into Ashenvale — Kadrak, who wants Darn Talongrip's report, stands just past the rampart
]], "Lodestar_Guides_Horde")

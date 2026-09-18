-- Lodestar Guides: Horde — Thousand Needles (levels 25-30), the continuation of the Ashenvale route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Freewind Post loops: the Great Lift (Brave Moonhorn,
-- Grish Longrunner), Freewind Post as the hub, Dorn Plainstalker east of it, a north loop (the Galak
-- centaur of Splithoof Crag, Darkcloud Pinnacle: Arnak, Lakota's escort), the Alien Eggs south of the
-- post, a west loop (the Grimtotem document chests, the Incendia Agave, the leap of faith, Whitereach
-- Post, Highperch and Pao'ka's escort), then Dorn's tests and the Shimmering Flats race quests as
-- optional 28-30 content. By the XP tables the core quests carry a character from 25 to about 28; the
-- optional quests, Razorfen Kraul and kill XP make up the rest to 30. Every quest id and position comes
-- from the data; the order still has to be verified in play (/lode record).
--
-- Left out on purpose: The Sacred Flame (its prologue starts in Thunder Bluff), Test of Lore (a hand-off
-- to Stonetalon and Ashenvale), A New Ore Sample (needs Weapons of Choice from the Barrens), the Hemet
-- Nesingwary and Martek hand-offs (Stranglethorn, Badlands) and The Crone of the Kraul (Alliance).
-- Freewind Post has no class trainer in Vanilla; the training trip is Thunder Bluff / Orgrimmar at the
-- end, on the way to Desolace.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 25-30: Thousand Needles
#faction Horde
#levels 27-29
#next Horde 30-35: Desolace
#author Lodestar
-- #levels is 27-29 for the auto-pick only: Ashenvale hands a level 25-26 character here through #next; the quests run to about 28, the optional Shimmering Flats and Dorn's tests to 30.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- The Great Lift --------------------------------------------------------------------------------------------------------

step
  .goto Thousand Needles,32.2,22.2
  .accept 4542 >>Accept Message to Freewind Post from Brave Moonhorn at the Great Lift

step
  .goto Thousand Needles,31.9,21.7
  .turnin 5881 >>Turn in Calling in the Reserves to Grish Longrunner, next to Brave Moonhorn (Maggran's letter from Sun Rock Retreat — if you came through Hillsbrad you do not have it, click Next)

-- Freewind Post: the hub --------------------------------------------------------------------------------------------------

step
  .goto Thousand Needles,45.7,50.7
  .turnin 4542 >>Follow the road south-east along the canyon floor to Freewind Post, the tauren post on the mesa in the middle of the zone (a lift at the foot of the mesa takes you up), and turn in Message to Freewind Post to Cliffwatcher Longhorn
  .accept 4841 >>Accept Pacify the Centaur

step
  .goto Thousand Needles,44.6,50.3
  .accept 4821 >>Accept Alien Egg from Hagar Lightninghoof

step
  .goto Thousand Needles,44.9,48.9
  .accept 4767 >>Accept Wind Rider from Elu, by the wind riders (level 25)

step
  .goto Thousand Needles,46.0,50.9
  .accept 5147 >>Accept Wanted - Arnak Grimtotem from the poster

step
  .goto Thousand Needles,46.1,51.5
  .hs Freewind Post >>Set your hearthstone at the Freewind Post inn (Innkeeper Abeqwa)
  .vendor

step
  .goto Thousand Needles,45.1,49.1
  .text >>Talk to Nyse, the wind rider master, to learn the Freewind Post flight path

step
  .goto Thousand Needles,53.9,41.5
  .accept 1149 >>Accept Test of Faith from Dorn Plainstalker, the tauren on the needle north-east of Freewind Post (level 25) — the leap is in the west, on the way to Whitereach Post later

-- North loop: Splithoof Crag, Darkcloud Pinnacle -------------------------------------------------------------------------------

step
  .goto Thousand Needles,43.7,39.3
  .complete 4841 >>Kill Galak Scouts and Windchasers (lvl 24-25) and Galak Wranglers (lvl 25-26) at Splithoof Crag, the centaur camps north of Freewind Post (39-48,32-44; Maulers, Stormers and Marauders lvl 26-28 deeper in)

step
  .goto Thousand Needles,39.4,33.1
  .accept 4881 >>Kill the Galak Messenger (lvl 26), a centaur runner on the west side of Splithoof Crag, and accept Assassination Plot from the note he always drops — for Kanati Greycloud at Whitereach Post

step
  .goto Thousand Needles,38.1,26.9
  .complete 5147,1 >>Climb Darkcloud Pinnacle, the Grimtotem mesa north-west of Splithoof Crag (a ramp winds up the mesa), and kill Arnak Grimtotem (lvl 29) at the top for his hoof (Grimtotem Bandits, Stompers and Geomancers lvl 25-27, Reavers lvl 28)

step
  .goto Thousand Needles,37.9,26.4
  .accept 4904 >>Accept Free at Last from Lakota Windsong, the captive next to Arnak, and escort her down off the pinnacle (Grimtotem ambushes) — the turn-in is Thalia Amberhide at Freewind Post

-- Freewind Post: second visit ---------------------------------------------------------------------------------------------

step
  .goto Thousand Needles,45.7,50.7
  .turnin 4841 >>Turn in Pacify the Centaur to Cliffwatcher Longhorn (hearth or walk back)
  .turnin 5147 >>Turn in Wanted - Arnak Grimtotem
  .accept 5064 >>Accept Grimtotem Spying

step
  .goto Thousand Needles,46.0,51.6
  .turnin 4904 >>Turn in Free at Last to Thalia Amberhide, by the inn

-- South: the Alien Eggs ------------------------------------------------------------------------------------------------------------

step
  .goto Thousand Needles,52.3,55.2
  .complete 4821,1 >>Pick up an Alien Egg from the nests south-east of Freewind Post (52.3,55.2; also 56.4,50.4 and 37.6,56.1) — Venomous Cloud Serpents (lvl 26-28) and Needles Cougars (lvl 27-28) guard them

step
  .goto Thousand Needles,44.6,50.3
  .turnin 4821 >>Turn in Alien Egg to Hagar Lightninghoof at Freewind Post
  .accept 4865 >>Accept Serpent Wild — a hand-off to Motega Firemane at Whitereach Post

-- West loop: the document chests, the Incendia Agave, the leap of faith, Whitereach Post, Highperch ------------------------------------

step
  .goto Thousand Needles,39.3,41.5
  .complete 5064 >>Grimtotem Spying: open the Document Chests at the three Grimtotem camps west of Splithoof Crag — 39.3,41.5, then 33.8,40, then 31.8,32.6 below Darkcloud Pinnacle (Grimtotem lvl 25-28 at each)

step
  .goto Thousand Needles,26.4,32.9
  .complete 1149,1 >>Test of Faith: find the ledge on the canyon wall east of Whitereach Post (26.4,32.9 — a path climbs to it) and make the leap Dorn asked for; the fall does not kill you

step
  .goto Thousand Needles,21.5,32.3
  .turnin 4865 >>Turn in Serpent Wild to Motega Firemane at Whitereach Post, the tauren camp at the west end of the canyon

step
  .goto Thousand Needles,21.5,32.3
  .optional >>Sacred Fire: Incendia Agave from the Grimtotem side of the canyon, but the turn-in is Magatha Grimtotem in Thunder Bluff — take it if you fly to Thunder Bluff to train at the end
  .accept 5062 >>Accept Sacred Fire from Motega Firemane

step
  .goto Thousand Needles,21.3,32.1
  .turnin 4881 >>Turn in Assassination Plot to Kanati Greycloud, next to Motega
  .accept 4966 >>Accept Protect Kanati Greycloud

step
  .goto Thousand Needles,21.3,32.1
  .complete 4966 >>Tell Kanati you are ready and kill the three Galak assassins (lvl 28) who come for him

step
  .goto Thousand Needles,21.3,32.1
  .turnin 4966 >>Turn in Protect Kanati Greycloud to Kanati Greycloud

step
  .goto Thousand Needles,21.4,32.6
  .optional >>Hypercapacitor Gizmo: an Enraged Panther (lvl 30) that prowls north of Whitereach Post
  .accept 5151 >>Accept Hypercapacitor Gizmo from Wizlo Bearingshiner, the gnome at Whitereach Post

step
  .goto Thousand Needles,22.8,24.6
  .optional >>Hypercapacitor Gizmo
  .complete 5151,1 >>Kill the Enraged Panther (lvl 30) on the ridge north of Whitereach Post and loot the gizmo it swallowed

step
  .goto Thousand Needles,21.4,32.6
  .optional >>Hypercapacitor Gizmo
  .turnin 5151 >>Turn in Hypercapacitor Gizmo to Wizlo Bearingshiner

step
  .goto Thousand Needles,12.6,35.1
  .complete 4767,1 >>Highperch, the wyvern roost in the far west (8-18,32-42): pick up Highperch Wyvern Eggs from the nests — Highperch Wyverns and Consorts (lvl 28-29) sit on them, the Patriarch (lvl 30-31) roosts at the back (10,34); pull carefully, they come in twos

step
  .goto Thousand Needles,17.9,40.6
  .accept 4770 >>Accept Homeward Bound from Pao'ka Swiftmountain, the tauren hiding at the south-east edge of Highperch, and escort him out past the wyverns to Whitereach Post

step
  .goto Thousand Needles,21.5,32.3
  .turnin 4770 >>Turn in Homeward Bound to Motega Firemane at Whitereach Post

step
  .goto Thousand Needles,35.6,36.2
  .optional >>Sacred Fire
  .complete 5062,1 >>Pick Incendia Agave, the plants growing around the Grimtotem camps between Darkcloud Pinnacle and Splithoof Crag (33-38,33-39), on the way back east

-- Freewind Post: third visit, then Dorn's tests ---------------------------------------------------------------------------------------

step
  .goto Thousand Needles,44.9,48.9
  .turnin 4767 >>Turn in Wind Rider to Elu at Freewind Post (hearth or walk back)

step
  .goto Thousand Needles,45.7,50.7
  .turnin 5064 >>Turn in Grimtotem Spying to Cliffwatcher Longhorn

step
  .goto Thousand Needles,46.1,51.5
  .vendor >>Sell, repair and restock at the inn

step
  .goto Thousand Needles,53.9,41.5
  .xp 26
  .turnin 1149 >>Turn in Test of Faith to Dorn Plainstalker

step
  .goto Thousand Needles,53.9,41.5
  .optional >>Test of Endurance and Test of Strength: Grenka Bloodscreech (lvl 31) in the harpy canyon and Rok'Alim the Pounder (lvl 30 rock elemental) in the west — named mobs above your level, good XP with a partner; Test of Lore after them is a trip to Stonetalon and Ashenvale, leave it
  .accept 1150 >>Accept Test of Endurance from Dorn Plainstalker

step
  .goto Thousand Needles,27.1,52.2
  .optional >>Test of Endurance
  .complete 1150 >>Grenka Bloodscreech (lvl 31) roosts among the Screeching harpies (lvl 28-30) in the canyon south-west of Freewind Post (26-28,47-56) — kill her for her claw; the Flank of Meat is not in the data, the cougars and hyenas around the canyon drop it

step
  .goto Thousand Needles,53.9,41.5
  .optional >>Test of Endurance
  .turnin 1150 >>Turn in Test of Endurance to Dorn Plainstalker
  .accept 1151 >>Accept Test of Strength

step
  .goto Thousand Needles,25.7,42.2
  .optional >>Test of Strength
  .complete 1151,1 >>Kill Rok'Alim the Pounder (lvl 30), the rock elemental that wanders the canyon floor south-east of Whitereach Post (25.7,42.2), and loot his fragments

step
  .goto Thousand Needles,53.9,41.5
  .optional >>Test of Strength
  .turnin 1151 >>Turn in Test of Strength to Dorn Plainstalker (Test of Lore, his last test, sends you to Braug Dimspirit in Stonetalon — skip it)

-- Optional: the Shimmering Flats race chain (level 28-30) -------------------------------------------------------------------------------

step
  .goto Thousand Needles,77.8,77.3
  .optional >>The Shimmering Flats (level 28): the goblin and gnome race teams at the Mirage Raceway in the south-east salt flat; the mobs out there are lvl 30-35 — good XP at 29-30, slow before that. Rocket Car Parts is the easy one (rubble on the ground)
  .xp 28
  .accept 1110 >>Follow the road east out of the canyon down to the Shimmering Flats and accept Rocket Car Parts from Kravel Koalbeard at the raceway

step
  .goto Thousand Needles,78.1,77.1
  .optional >>The Shimmering Flats
  .accept 1104 >>Accept Salt Flat Venom from Fizzle Brassbolts (Scorpid Reavers lvl 31-32, Terrors lvl 33-34 — a 1 in 4 drop)
  .accept 1105 >>Accept Hardened Shells from Wizzle Brassbolts (Sparkleshell Tortoises lvl 30-31 — about 1 in 3)

step
  .goto Thousand Needles,80.2,75.9
  .optional >>The Shimmering Flats
  .xp 29
  .accept 1176 >>Accept Load Lightening from Pozzik (level 29; Salt Flats Scavengers lvl 30-32 and Vultures lvl 32-34)

step
  .goto Thousand Needles,81.6,78.0
  .optional >>The Shimmering Flats
  .accept 1175 >>Accept A Bump in the Road from Trackmaster Zherin (Saltstone Basilisks lvl 30-31, Crystalhides lvl 32-33, Gazers lvl 34-35 — the Gazers are for level 32+)

step
  .goto Thousand Needles,73.2,68.7
  .optional >>The Shimmering Flats
  .complete 1110,1 >>Collect Rocket Car Parts from the Rocket Car Rubble scattered over the salt flat (73.2,68.7; 69.9,58.9; 79.5,59.1; 77.7,51.8; 72.5,80.8 and more)

step
  .goto Thousand Needles,76.2,58.6
  .optional >>The Shimmering Flats
  .complete 1105,1 >>Loot Hardened Tortoise Shells from Sparkleshell Tortoises (lvl 30-31) on the northern half of the flat (69-84,52-69)

step
  .goto Thousand Needles,73.6,59.4
  .optional >>The Shimmering Flats
  .complete 1175 >>Kill Saltstone Basilisks (lvl 30-31) on the northern flat, Crystalhides (lvl 32-33) in the middle and Gazers (lvl 34-35) in the south (72-84,78-91)

step
  .goto Thousand Needles,70.3,70.9
  .optional >>The Shimmering Flats
  .complete 1176,1 >>Loot Hollow Vulture Bones from Salt Flats Scavengers (lvl 30-32) and Vultures (lvl 32-34) across the flat (80%)

step
  .goto Thousand Needles,73.9,61.0
  .optional >>The Shimmering Flats
  .complete 1104,1 >>Loot Salty Scorpid Venom from Scorpid Reavers (lvl 31-32) on the northern flat and Scorpid Terrors (lvl 33-34) in the south (25% drop)

step
  .goto Thousand Needles,77.8,77.3
  .optional >>The Shimmering Flats
  .turnin 1110 >>Turn in Rocket Car Parts to Kravel Koalbeard (his hand-off to Hemet Nesingwary is for Stranglethorn — skip it)

step
  .goto Thousand Needles,78.1,77.1
  .optional >>The Shimmering Flats
  .turnin 1104 >>Turn in Salt Flat Venom to Fizzle Brassbolts (Martek the Exiled, his follow-up, is a hand-off to the Badlands — skip it)
  .turnin 1105 >>Turn in Hardened Shells to Wizzle Brassbolts (his follow-up, Encrusted Tail Fins, is for the level 30+ guide)

step
  .goto Thousand Needles,80.2,75.9
  .optional >>The Shimmering Flats
  .turnin 1176 >>Turn in Load Lightening to Pozzik (Goblin Sponsorship, his follow-up, is a hand-off chain through Ratchet and Booty Bay — skip it)

step
  .goto Thousand Needles,81.6,78.0
  .optional >>The Shimmering Flats
  .turnin 1175 >>Turn in A Bump in the Road to Trackmaster Zherin

-- Level 30: train, Sacred Fire (optional), then Desolace ---------------------------------------------------------------------------------

step
  .goto Thousand Needles,46.1,51.5
  .xp 28 >>You should be level 28 by now — Freewind Post's quests run out here, and Desolace's start at 30. The Shimmering Flats quests above, Dorn's tests, the Grimtotem of Darkcloud Pinnacle (lvl 25-29) and the Screeching harpies (lvl 28-30) are the grind to 30; Razorfen Kraul (lvl 25-30, in the southern Barrens) is the dungeon for this band

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .fly Thunder Bluff >>Fly from Freewind Post to Thunder Bluff

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .train >>Train new skills at your class trainer in Thunder Bluff, sell and repair

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .fly Orgrimmar >>Fly from Freewind Post to Orgrimmar

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .train >>Train new skills at your class trainer in Orgrimmar, sell and repair

step
  .goto Thunder Bluff,69.9,30.9
  .optional >>Sacred Fire
  .turnin 5062 >>Turn in Sacred Fire to Magatha Grimtotem on the Elder Rise in Thunder Bluff (fly there if you trained in Orgrimmar; her follow-up, Arikara, is a hand-off back to Whitereach Post — leave it)

step
  .goto Stonetalon Mountains,45.1,59.8
  .fly Sun Rock Retreat >>Fly to Sun Rock Retreat in Stonetalon Mountains (from Orgrimmar the wind riders route you through the Crossroads)

step
  .zone Desolace >>Take the road west out of Sun Rock Retreat through the Charred Vale and south into Desolace — Shadowprey Village and Ghost Walker Post are the Horde posts there
]], "Lodestar_Guides_Horde")

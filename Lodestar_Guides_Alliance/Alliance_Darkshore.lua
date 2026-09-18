-- Lodestar Guides: Alliance — Darkshore (levels 12-20), the continuation of the Night Elf route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Auberdine loops: the beach and Bashal'Aran, the south
-- (the Blackwood camp, Ameth'Aran, the Grove of the Ancients and a run to the Master's Glaive), a
-- Darnassus trip for the trainers, the north (the Cliffspring River, the Blackwood village, the Tower
-- of Althalaxx and the Mist's Edge shore), the deep south (Onu, the Twilight camp, Volcor, the Greymist
-- murlocs), then the road south into Ashenvale with the escorts that end there. Every quest id and
-- position comes from the data; the order still has to be verified in play (/lode record).
-- Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance 12-20: Darkshore
#faction Alliance
#levels 12-19
#next Alliance 20-25: Ashenvale
#author Lodestar
-- #levels stops at 19 so the auto-pick hands a level 20 character to the next guide; the route itself runs to 20.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Auberdine: first visit -----------------------------------------------------------------------------------

step
  .goto Darkshore,36.8,44.3
  .turnin 6342 >>Turn in Flight to Auberdine to Laird, outside the Auberdine inn (if you flew in from Rut'theran with it)

step
  .goto Darkshore,37.0,44.1
  .hs Auberdine >>Set your hearthstone at the Auberdine inn (Innkeeper Shaussiy)
  .accept 983 >>Accept Buzzbox 827 from Wizbang Cranktoggle, the gnome outside the inn

step
  .goto Darkshore,36.3,45.6
  .text >>Talk to Caylais Moonfeather, the hippogryph master on the platform south of the inn, to learn the Auberdine flight path

step
  .goto Darkshore,36.6,45.6
  .accept 3524 >>Accept Washed Ashore from Gwennyth Bly'Leggonde, by the flight platform

step
  .goto Darkshore,35.7,43.7
  .accept 963 >>Accept For Love Eternal from Cerellean Whiteclaw on the dock — Anaya haunts Ameth'Aran at night; she is a level 16 ghost, so this waits for the second trip south

step
  .goto Darkshore,37.7,43.4
  .accept 4811 >>Accept The Red Crystal from Sentinel Glynda Nal'Shea, by the road through town

step
  .goto Darkshore,38.8,43.4
  .accept 2118 >>Accept Plagued Lands from Tharnariun Treetender, in the house east of the road

step
  .goto Darkshore,39.4,43.5
  .accept 984 >>Accept How Big a Threat? from Terenthis, in the same house

step
  .goto Darkshore,37.4,40.1
  .accept 954 >>Accept Bashal'Aran from Thundris Windweaver at the north end of town
  .accept 958 >>Accept Tools of the Highborne

step
  .goto Darkshore,37.7,40.7
  .accept 2178 >>Accept Easy Strider Living from Alanndarian Nightsong, next to Thundris

step
  .goto Darkshore,37.3,43.6
  .accept 947 >>Accept Cave Mushrooms from Barithras Moonshade, by the road (level 12) — the mushrooms are in Cliffspring Hollow, for the north loop

-- The beach: crawlers, the sea creature, the skeletal turtle, the red crystal -----------------------------------

step
  .goto Darkshore,36.2,44.5
  .complete 983,1 >>Loot 4 Crawler Legs from Pygmy Tide Crawlers on the beach below the town (lvl 9-10)

step
  .goto Darkshore,36.6,46.3
  .turnin 983 >>Turn in Buzzbox 827 at the buzzbox south of the flight platform
  .accept 1001 >>Accept Buzzbox 411 from it — Thresher Eyes, from the Darkshore Threshers out in the water (lvl 12-14)

step
  .goto Darkshore,36.4,50.9
  .complete 3524,1 >>Take the Sea Creature Bones from the Beached Sea Creature on the beach south of town

step
  .goto Darkshore,36.6,45.6
  .turnin 3524 >>Turn in Washed Ashore to Gwennyth Bly'Leggonde
  .accept 4681 >>Accept Washed Ashore (part 2)

step
  .goto Darkshore,31.8,46.3
  .complete 4681,1 >>Swim out west of the dock to the Skeletal Sea Turtle on the sea floor for the Sea Turtle Remains (Darkshore Threshers around it, lvl 12-14 — they drop the Thresher Eyes for Buzzbox 411 while you are here)

step
  .goto Darkshore,36.6,45.6
  .turnin 4681 >>Turn in Washed Ashore to Gwennyth Bly'Leggonde — from now on every Beached Sea Turtle and Sea Creature along the coast starts a quest to bring back to her

step
  .goto Darkshore,37.0,43.0
  .complete 4811 >>Walk east along the road to the Mysterious Red Crystal at the foot of the mountains (47.2, 48.7) and look at it

step
  .goto Darkshore,41.9,45.8
  .complete 2178,1 >>Loot 6 Strider Meat from Foreststrider Fledglings east of town (lvl 11-13)

step
  .goto Darkshore,37.7,43.4
  .turnin 4811 >>Turn in The Red Crystal to Sentinel Glynda Nal'Shea in Auberdine
  .accept 4812 >>Accept As Water Cascades

step
  .goto Darkshore,37.5,43.5
  .complete 4812,1 >>Fill the Empty Water Tube at the moonwell in the middle of Auberdine

step
  .goto Darkshore,47.3,48.7
  .turnin 4812 >>Pour the water over the Mysterious Red Crystal, east of town, and turn in As Water Cascades
  .accept 4813 >>Accept The Fragments Within from the crystal

step
  .goto Darkshore,42.8,45.0
  .class Druid
  .complete 6001 >>Kill Lunaclaw, the moonstalker in the woods east of Auberdine (lvl 12), for the bear spirit (Body and Heart, from Darnassus)

step
  .goto Darkshore,37.7,43.4
  .turnin 4813 >>Turn in The Fragments Within to Sentinel Glynda Nal'Shea

step
  .goto Darkshore,37.7,40.7
  .turnin 2178 >>Turn in Easy Strider Living to Alanndarian Nightsong

-- Bashal'Aran ------------------------------------------------------------------------------------------------------

step
  .goto Darkshore,44.2,36.3
  .turnin 954 >>Turn in Bashal'Aran to Asterion, the ghost in the ruins of Bashal'Aran north-east of Auberdine
  .accept 955 >>Accept Bashal'Aran (part 2)

step
  .goto Darkshore,46.5,38.1
  .complete 955,1 >>Loot 8 Grell Earrings from the Wild Grells and Vile Sprites in the ruins (lvl 10-12)

step
  .goto Darkshore,44.2,36.3
  .turnin 955 >>Turn in Bashal'Aran to Asterion
  .accept 956 >>Accept Bashal'Aran (part 3)

step
  .goto Darkshore,47.3,37.7
  .complete 956,1 >>Loot an Ancient Moonstone Seal from the Deth'ryll Satyrs at the east end of the ruins (lvl 12-13, 34% drop)

step
  .goto Darkshore,44.2,36.3
  .turnin 956 >>Turn in Bashal'Aran to Asterion
  .accept 957 >>Accept Bashal'Aran (part 4) — the Ancient Flame in Ameth'Aran, to the south

step
  .goto Darkshore,43.4,34.7
  .complete 2118 >>Use the trap Tharnariun gave you on a Rabid Thistle Bear (lvl 13-14; there are some among the Thistle Bears north of the ruins and more south of Auberdine) and lead the captured bear back to him

step
  .goto Darkshore,38.8,43.4
  .turnin 2118 >>Turn in Plagued Lands to Tharnariun Treetender in Auberdine
  .accept 2138 >>Accept Cleansing of the Infected

-- South loop: the Blackwood camp, Ameth'Aran, the Grove of the Ancients, the Master's Glaive ------------------------------

step
  .goto Darkshore,38.2,52.6
  .xp 13
  .complete 2138,1 >>Kill 15 Rabid Thistle Bears in the woods south of Auberdine (lvl 13-14)

step
  .goto Darkshore,39.3,53.5
  .complete 984,1 >>Walk through the Blackwood furbolg camp south of town (Pathfinders and Windtalkers, lvl 12-14) — the quest wants you to see it
  .complete 984,2 >>and the second camp just beyond it

step
  .goto Darkshore,40.3,59.7
  .accept 953 >>Accept The Fall of Ameth'Aran from Sentinel Tysha Moonblade, by the road at Ameth'Aran

step
  .goto Darkshore,43.3,58.7
  .complete 953,1 >>Read the Lay of Ameth'Aran, a stone tablet in the north of the ruins (Cursed and Writhing Highborne, lvl 10-13)
  .complete 958,1 >>Loot 8 Highborne Relics from the Highborne ghosts around the ruins (40% drop)

step
  .goto Darkshore,42.7,63.1
  .complete 953,2 >>Read The Fall of Ameth'Aran, the tablet at the south end of the ruins

step
  .goto Darkshore,42.4,61.8
  .complete 957 >>Use the Ancient Flame in the middle of Ameth'Aran to light Asterion's brazier

step
  .goto Darkshore,40.3,59.7
  .turnin 953 >>Turn in The Fall of Ameth'Aran to Sentinel Tysha Moonblade

step
  .goto Darkshore,37.1,62.2
  .accept 4722 >>Take the Beached Sea Turtle on the beach west of Ameth'Aran and accept its quest for Gwennyth

step
  .goto Darkshore,36.0,70.9
  .xp 12
  .accept 4728 >>Take the Beached Sea Creature further south along the beach and accept its quest

step
  .goto Darkshore,43.6,76.3
  .turnin 952 >>Turn in Grove of the Ancients to Onu, the ancient at the Grove of the Ancients, south along the road (if you brought it from Darnassus)

step
  .goto Darkshore,42.7,86.5
  .complete 984,3 >>Follow the road south to the Master's Glaive, the giant sword in the ground (Twilight cultists, lvl 16-18 — stay on the edge and just look; you come back for them later)

step
  .goto Darkshore,39.4,43.5
  .turnin 984 >>Turn in How Big a Threat? to Terenthis in Auberdine (hearth)
  .accept 985 >>Accept How Big a Threat? (part 2)
  .accept 4761 >>Accept Thundris Windweaver

step
  .goto Darkshore,39.7,54.4
  .complete 985,1 >>Kill 8 Blackwood Pathfinders at the furbolg camps south of Auberdine (lvl 12-13)
  .complete 985,2 >>Kill 8 Blackwood Windtalkers there too (lvl 13-14)

-- Auberdine: second visit ------------------------------------------------------------------------------------------------

step
  .goto Darkshore,39.4,43.5
  .turnin 985 >>Turn in How Big a Threat? to Terenthis in Auberdine
  .accept 986 >>Accept A Lost Master — Fine Moonstalker Pelts, from the Sires and Matriarchs (lvl 17-20) in the far north-east or the deep south

step
  .goto Darkshore,37.4,40.1
  .turnin 4761 >>Turn in Thundris Windweaver to Thundris Windweaver
  .turnin 958 >>Turn in Tools of the Highborne
  .accept 4762 >>Accept The Cliffspring River

step
  .goto Darkshore,36.6,45.6
  .turnin 4722 >>Turn in the Beached Sea Turtle quest to Gwennyth Bly'Leggonde
  .turnin 4728 >>Turn in the Beached Sea Creature quest

step
  .goto Darkshore,38.8,43.4
  .turnin 2138 >>Turn in Cleansing of the Infected to Tharnariun Treetender
  .accept 2139 >>Accept Tharnariun's Hope — the Den Mother, in the north

step
  .goto Darkshore,39.0,43.6
  .xp 14
  .accept 965 >>Accept The Tower of Althalaxx from Sentinel Elissa Starbreeze, by Terenthis' house (level 13)

step
  .goto Darkshore,38.1,41.2
  .accept 982 >>Accept Deep Ocean, Vast Sea from Gorbold Steelhand at the north end of town (level 13)

step
  .goto Darkshore,37.0,44.1
  .vendor >>Sell junk at the vendors around the inn and buy food and water

-- Warriors: the Shade of Elura, then the Darnassus trip for the trainers -----------------------------------------------------

step
  .goto Darkshore,32.2,44.4
  .class Warrior
  .complete 1686,1 >>Swim out west of the dock: loot 4 Elunite Ore from the Crates of Elunite in the wreck on the sea floor
  .complete 1686,2 >>Kill the Shade of Elura at the wreck (lvl 11) and take her medallion

step
  .goto Darkshore,36.3,45.6
  .xp 14
  .fly Rut'theran Village >>Fly to Rut'theran Village with Caylais Moonfeather and take the portal up to Darnassus — the class trainers (level 14-16)

step
  .goto Darnassus,58.7,34.9
  .class Warrior
  .train Arias'ta Bladesinger >>Train at Arias'ta Bladesinger in the Warrior's Terrace

step
  .goto Darnassus,57.3,34.6
  .class Warrior
  .turnin 1686 >>Turn in The Shade of Elura to Elanaria in the Warrior's Terrace
  .accept 1692 >>Accept Smith Mathiel

step
  .goto Darnassus,59.5,45.4
  .class Warrior
  .turnin 1692 >>Turn in Smith Mathiel to Mathiel, the smith south of the terrace
  .accept 1693 >>Accept Weapons of Elunite

step
  .goto Darnassus,59.5,45.4
  .class Warrior
  .turnin 1693 >>Speak with Mathiel again and turn in Weapons of Elunite for your Elunite weapon

step
  .goto Darnassus,40.4,8.5
  .class Hunter
  .train Jocaste >>Train at Jocaste in the Cenarion Enclave

step
  .goto Darnassus,34.5,25.9
  .class Rogue
  .train Erion Shadewhisper >>Train at Erion Shadewhisper in the Cenarion Enclave

step
  .goto Darnassus,38.3,81.0
  .class Priest
  .train Astarii Starseeker >>Train at Astarii Starseeker in the Temple of the Moon

step
  .goto Darnassus,35.4,8.4
  .class Druid
  .turnin 6001 >>Turn in Body and Heart to Mathrengyl Bearwalker in the Cenarion Enclave for Bear Form

step
  .goto Darnassus,34.8,7.4
  .class Druid
  .train Denatharion >>Train at Denatharion in the Cenarion Enclave

step
  .goto Darnassus,31.2,84.5
  .optional >>The Absent Minded Prospector: a long escort through the Twilight camp in the deep south (lvl 20) that starts here and ends back in Darnassus — good XP with a friend
  .accept 730 >>Accept Trouble In Darkshore? from Chief Archaeologist Greywhisker in the Temple of the Moon (level 14)

step
  .goto Darnassus,67.4,15.6
  .vendor >>Sell and repair in the Tradesmen's Terrace, then take the portal down and fly back to Auberdine
  .fly Auberdine

-- North loop: the Cliffspring River, the Blackwood village, the Tower of Althalaxx, the Mist's Edge --------------------------------

step
  .goto Darkshore,44.2,36.3
  .turnin 957 >>Turn in Bashal'Aran to Asterion in the ruins of Bashal'Aran, on the way north

step
  .goto Darkshore,42.0,28.6
  .turnin 1001 >>Turn in Buzzbox 411 at the buzzbox on the beach north of Auberdine (kill Darkshore Threshers in the water for the eyes if you are short)
  .accept 1002 >>Accept Buzzbox 323 from it

step
  .goto Darkshore,38.2,28.8
  .complete 982,1 >>Dive for Silver Dawning's Lockbox in the wreck off the beach
  .complete 982,2 >>and Mist Veil's Lockbox in the wreck a little to the east (Darkshore Threshers, lvl 12-14)

step
  .goto Darkshore,41.9,31.5
  .accept 4723 >>Take the Beached Sea Creature on the beach and accept its quest for Gwennyth

step
  .goto Darkshore,44.2,20.6
  .accept 4725 >>Take the Beached Sea Turtle on the beach at the Mist's Edge and accept its quest

step
  .goto Darkshore,50.8,25.6
  .complete 4762,1 >>Fill the sample vial at the pool under the first waterfall of the Cliffspring River, below the bridge

step
  .goto Darkshore,46.2,23.7
  .complete 1002,1 >>Loot 6 Moonstalker Fangs from the Moonstalker Runts along the coast here (lvl 10-11, 20% drop) — the Moonstalkers in the south drop them too

step
  .goto Darkshore,51.3,24.6
  .turnin 1002 >>Turn in Buzzbox 323 at the buzzbox by the river mouth
  .accept 1003 >>Accept Buzzbox 525 from it — Grizzled Scalps from the Grizzled Thistle Bears in the deep south

step
  .goto Darkshore,53.1,18.1
  .accept 4727 >>Take the Beached Sea Turtle on the beach north-east of the river and accept its quest

step
  .goto Darkshore,55.0,24.9
  .turnin 965 >>Turn in The Tower of Althalaxx to Balthule Shadowstrike, hiding on the hill south of the tower
  .accept 966 >>Accept The Tower of Althalaxx (part 2)

step
  .goto Darkshore,56.5,26.9
  .complete 966,1 >>Loot 4 Worn Parchments from the Dark Strand Fanatics around the Tower of Althalaxx (lvl 16-17, 45% drop)

step
  .goto Darkshore,55.0,24.9
  .turnin 966 >>Turn in The Tower of Althalaxx to Balthule Shadowstrike
  .accept 967 >>Accept The Tower of Althalaxx (part 3) — for Delgren the Purifier at Maestra's Post in Ashenvale

step
  .goto Darkshore,61.4,11.2
  .xp 16
  .complete 986,1 >>Loot 4 Fine Moonstalker Pelts from Moonstalker Sires and Matriarchs on the coast north-east of the tower (lvl 17-20, 40% drop)

step
  .goto Darkshore,55.9,35.4
  .complete 947,1 >>Pick 8 Death Caps in Cliffspring Hollow, the cave south of the tower (Blackwood furbolgs inside, lvl 14-16)
  .complete 947,2 >>and 8 Scaber Stalks — both mushrooms grow all through the cave

step
  .goto Darkshore,51.5,38.3
  .complete 2139,1 >>Kill the Den Mother in the bear cave south of the Blackwood village (lvl 18-19)

-- Auberdine: third visit -------------------------------------------------------------------------------------------------------

step
  .goto Darkshore,37.4,40.1
  .turnin 4762 >>Turn in The Cliffspring River to Thundris Windweaver in Auberdine (hearth)
  .accept 4763 >>Accept The Blackwood Corrupted — the samples are in the Blackwood village you just passed

step
  .goto Darkshore,38.8,43.4
  .turnin 2139 >>Turn in Tharnariun's Hope to Tharnariun Treetender

step
  .goto Darkshore,38.1,41.2
  .turnin 982 >>Turn in Deep Ocean, Vast Sea to Gorbold Steelhand

step
  .goto Darkshore,37.3,43.6
  .turnin 947 >>Turn in Cave Mushrooms to Barithras Moonshade
  .accept 948 >>Accept Onu

step
  .goto Darkshore,36.6,45.6
  .turnin 4723 >>Turn in the Beached Sea Creature quest to Gwennyth Bly'Leggonde
  .turnin 4725 >>Turn in the Beached Sea Turtle quests
  .turnin 4727 >>and the other one

step
  .goto Darkshore,36.1,44.9
  .xp 15
  .accept 1138 >>Accept Fruit of the Sea from Gubber Blump, by the flight platform (level 15) — the Reef Crawlers on the beach south of Ameth'Aran drop the crab chunks

step
  .goto Darkshore,39.4,43.5
  .turnin 986 >>Turn in A Lost Master to Terenthis
  .accept 993 >>Accept A Lost Master (part 2) — Volcor, hiding at the Twilight camp in the deep south

step
  .goto Darkshore,37.2,44.2
  .xp 17
  .accept 4740 >>Read the WANTED poster outside the inn and accept WANTED: Murkdeep! (level 15) — the Greymist murloc camp on the beach in the far south-west

step
  .goto Darkshore,37.4,41.8
  .optional >>The Absent Minded Prospector
  .turnin 730 >>Turn in Trouble In Darkshore? to Archaeologist Hollee at the north end of Auberdine
  .accept 729 >>Accept The Absent Minded Prospector — Prospector Remtravel digs on the beach in the deep south

step
  .goto Darkshore,52.9,33.4
  .complete 4763,1 >>Take a sample from the Blackwood Fruit Stores in the Blackwood village, north-east of Auberdine
  .complete 4763,2 >>and the Grain Stores
  .complete 4763,3 >>and the Nut Stores

step
  .goto Darkshore,52.0,34.0
  .complete 4763,4 >>Use the Cleansing Bowl at the bonfire in the middle of the village and kill Xabraxxis when he appears (lvl 17) for the Talisman of Corruption

step
  .goto Darkshore,37.4,40.1
  .turnin 4763 >>Turn in The Blackwood Corrupted to Thundris Windweaver in Auberdine

-- Deep south: Anaya, Onu and the Master's Glaive, Volcor, the Greymist murlocs ------------------------------------------------------------

step
  .goto Darkshore,41.8,60.7
  .complete 963,1 >>Kill Anaya Dawnrunner, the ghost who walks Ameth'Aran at night (lvl 16 — if it is day, come back on the way north) and take her pendant

step
  .goto Darkshore,43.6,76.3
  .turnin 948 >>Turn in Onu to Onu at the Grove of the Ancients
  .accept 944 >>Accept The Master's Glaive

step
  .goto Darkshore,40.1,79.8
  .complete 1003,1 >>Loot 6 Grizzled Scalps from Grizzled Thistle Bears in the woods west of the grove (lvl 16-17, 32% drop)

step
  .goto Darkshore,41.4,80.6
  .turnin 1003 >>Turn in Buzzbox 525 at the last buzzbox, on the beach west of the bears

step
  .goto Darkshore,35.5,77.5
  .complete 1138,1 >>Loot 6 Fine Crab Chunks from the Reef Crawlers on the beach west of the bears (lvl 15-17, 40% drop)

step
  .goto Darkshore,32.7,80.8
  .accept 4730 >>Take the Beached Sea Creature on the beach further west and accept its quest

step
  .goto Darkshore,39.0,86.0
  .complete 944,1 >>Walk around the Master's Glaive (Twilight cultists, lvl 16-18): the hilt
  .complete 944,2 >>the blade
  .complete 944,3 >>and the tip

step
  .goto Darkshore,39.2,87.6
  .turnin 944 >>Use the Scrying Bowl at the base of the sword to turn in The Master's Glaive
  .accept 949 >>Accept The Twilight Camp from the bowl

step
  .goto Darkshore,38.5,86.1
  .turnin 949 >>Read the Twilight Tome at the cultists' camp beside the sword and turn in The Twilight Camp
  .accept 950 >>Accept Return to Onu from the tome

step
  .goto Darkshore,45.0,85.3
  .xp 18
  .turnin 993 >>Turn in A Lost Master to Volcor, hiding in the cave east of the Glaive
  .accept 995 >>Accept Escape Through Stealth — sneak with him past the cultists to the road (Escape Through Force, the level 22 version, is a group quest)

step
  .goto Darkshore,45.0,85.3
  .complete 995 >>Follow Volcor as he sneaks out of the camp; stay close and off the cultists' paths until he thanks you

step
  .goto Darkshore,31.7,83.7
  .accept 4731 >>Take the Beached Sea Turtle at the Greymist murloc camp on the beach south-west of the Glaive and accept its quest (Greymist Hunters and Oracles, lvl 16-19)

step
  .goto Darkshore,31.2,85.6
  .accept 4732 >>Take the second Beached Sea Turtle there and accept its quest

step
  .goto Darkshore,31.3,87.4
  .accept 4733 >>Take the Beached Sea Creature at the south end of the camp and accept its quest

step
  .goto Darkshore,31.5,85.0
  .complete 4740,1 >>Clear the murloc huts at the Greymist camp: Murkdeep (lvl 19) comes out of the sea with his guards after the waves of Greymist murlocs

step
  .goto Darkshore,43.6,76.3
  .turnin 950 >>Turn in Return to Onu to Onu at the Grove of the Ancients

step
  .goto Darkshore,43.6,76.3
  .optional >>Mathystra Relics: the ruins of Mathystra are in the far north-east corner of Darkshore (lvl 18-20 naga) — a long way back for one turn-in
  .accept 951 >>Accept Mathystra Relics from Onu

step
  .goto Darkshore,35.7,83.7
  .optional >>The Absent Minded Prospector
  .turnin 729 >>Turn in The Absent Minded Prospector to Prospector Remtravel, digging on the beach west of the grove
  .accept 731 >>Accept The Absent Minded Prospector (part 2) — an escort through the Twilight camp (lvl 20 cultists); keep him alive

step
  .goto Darkshore,35.7,83.7
  .optional >>The Absent Minded Prospector
  .complete 731 >>Escort Prospector Remtravel to his dig site and back

-- Auberdine: last visit, then the road south into Ashenvale ---------------------------------------------------------------------------

step
  .goto Darkshore,39.4,43.5
  .turnin 995 >>Turn in Escape Through Stealth to Terenthis in Auberdine (hearth)

step
  .goto Darkshore,37.7,43.4
  .turnin 4740 >>Turn in WANTED: Murkdeep! to Sentinel Glynda Nal'Shea

step
  .goto Darkshore,35.7,43.7
  .turnin 963 >>Turn in For Love Eternal to Cerellean Whiteclaw on the dock

step
  .goto Darkshore,36.1,44.9
  .turnin 1138 >>Turn in Fruit of the Sea to Gubber Blump

step
  .goto Darkshore,36.6,45.6
  .turnin 4730 >>Turn in the Beached Sea Creature quests to Gwennyth Bly'Leggonde
  .turnin 4731 >>and the Beached Sea Turtle quests
  .turnin 4732 >>from the Greymist camp
  .turnin 4733 >>all of them

step
  .goto Darkshore,37.4,41.8
  .optional >>The Absent Minded Prospector
  .turnin 731 >>Turn in The Absent Minded Prospector to Archaeologist Hollee

step
  .goto Darkshore,58.5,19.3
  .optional >>Mathystra Relics
  .complete 951,1 >>Pick up 6 Mathystra Relics from the ruins in the far north-east corner of Darkshore (Cursed Highborne and naga, lvl 18-20)

step
  .goto Darkshore,43.6,76.3
  .optional >>Mathystra Relics
  .turnin 951 >>Turn in Mathystra Relics to Onu at the Grove of the Ancients

step
  .goto Darkshore,37.0,44.1
  .xp 19 >>You should be level 19 by now; if not, the Twilight cultists at the Master's Glaive and the Greymist murlocs are good XP. Sell and repair, then take the road south for the last time — three escorts and a hand-off on the way end in Ashenvale

step
  .goto Darkshore,44.4,76.4
  .xp 17
  .accept 5321 >>Accept The Sleeper Has Awakened from Kerlonian Evershade at the Grove of the Ancients (level 17): take the Horn of Awakening from his chest and blow it whenever he falls asleep on the walk to Maestra's Post in Ashenvale

step
  .goto Darkshore,44.4,76.3
  .complete 5321,1 >>Take the Horn of Awakening from Kerlonian's Chest next to him

step
  .goto Darkshore,38.7,87.3
  .accept 945 >>Accept Therylune's Escape from Therylune at the Twilight camp — she runs to the road south (cultists on the way, lvl 16-18)

step
  .goto Darkshore,45.9,90.3
  .accept 5713 >>Accept One Shot. One Kill. from Sentinel Aynasha, on the road at the south end of Darkshore — for Sentinel Onaeya at Maestra's Post in Ashenvale. Follow the road south into Ashenvale
]], "Lodestar_Guides_Alliance")

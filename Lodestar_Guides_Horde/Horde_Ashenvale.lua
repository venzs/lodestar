-- Lodestar Guides: Horde — Ashenvale (levels 25-30), where the Hillsbrad and Stonetalon routes meet.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Splintertree loops: Kadrak at the Mor'shan Rampart,
-- Splintertree Post as the hub, the Warsong Lumber Camp (Outrunners, Torek), Xavian and Satyrnaar
-- (Satyr Horns), then the long west trip — Mystral Lake (Stonetalon Standstill), around Astranaar,
-- Zoram'gar Outpost and the Zoram Strand (the naga, the Blackfathom cave), the Thistlefur Village
-- (Between a Rock and a Thistlefur, Troll Charm, Ruul) — and a hearth back to Splintertree. The Ashenvale
-- Hunt (three elite beasts) and the Warsong Reports are optional. Every quest id and position comes
-- from the data; the order still has to be verified in play (/lode record).
--
-- Both arrivals enter by the Barrens road: Kalimdor characters fly Sun Rock Retreat -> the Crossroads,
-- Undead take the zeppelin to Orgrimmar and walk. The turn-ins for the previous zone's hand-offs (Report
-- to Kadrak from Malaka'jin or from Thork, Trouble in the Deeps from Sun Rock) are separate steps that
-- say "click Next" for the other path. The Horde side of Ashenvale is thin: by the XP tables the quests
-- here carry a character from 23-24 to about 25, the rest is kill XP (the elite hunts, Blackfathom Deeps);
-- Thousand Needles' quests start at 25 and take over from there.
-- Splintertree Post has no class trainer in Vanilla; the training trip is Orgrimmar / Thunder Bluff at
-- the end, on the way to Camp Taurajo.
--
-- Left out on purpose: Warsong Supplies / Warsong Saw Blades (a 10% rope drop and items the data cannot
-- place), The Lost Pages (level 30, no drop sources in the data), Horde Presence (needs the Runed Scroll),
-- Kayneth Stillwind's Forest Song quests (Alliance), Allegiance to the Old Gods and Amongst the Ruins
-- (Blackfathom Deeps instance).
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 25-30: Ashenvale
#faction Horde
#levels 24-26
#next Horde 25-30: Thousand Needles
#author Lodestar
-- #levels is 24-26 for the auto-pick only: the Hillsbrad and Stonetalon guides hand a level 23-24 character here through #next, and Thousand Needles picks up at the end whatever the level.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Kadrak at the Mor'shan Rampart ----------------------------------------------------------------------------------------

step
  .goto Ashenvale,68.6,89.1
  .turnin 6542 >>Turn in Report to Kadrak to Kadrak, just north of the Mor'shan Rampart (Darn Talongrip's report from Malaka'jin — if you came from Hillsbrad you do not have this one, click Next)

step
  .goto Ashenvale,68.6,89.1
  .turnin 6541 >>Turn in Report to Kadrak to Kadrak (Thork's report from the Crossroads — if you came from Stonetalon you do not have this one, click Next)

step
  .goto Ashenvale,68.6,89.1
  .optional >>The Warsong Reports: three short talk quests at the Warsong Lumber Camp, Satyrnaar and Zoram'gar, but the turn-in is back here at the Barrens border — take it if you will leave Ashenvale by this road
  .accept 6543 >>Accept The Warsong Reports from Kadrak

-- Splintertree Post: the hub ---------------------------------------------------------------------------------------------

step
  .goto Ashenvale,73.8,61.5
  .optional >>The Ashenvale Hunt: Senani's three hunts are elite beasts (lvl 25, 28 and 31) — group quests; the Orgrimmar, Thunder Bluff and Camp Taurajo breadcrumbs all end here
  .turnin 235 >>Turn in The Ashenvale Hunt to Senani Thunderheart in Splintertree Post, the Horde post on the road north of the rampart (if you brought it from Orgrimmar)

step
  .goto Ashenvale,73.8,61.5
  .optional >>The Ashenvale Hunt
  .accept 6383 >>Accept The Ashenvale Hunt from Senani Thunderheart
  .turnin 6383 >>...and hand it straight back to her; the three hunts start from the trophies the beasts drop

step
  .goto Ashenvale,73.7,60.0
  .accept 25 >>Accept Stonetalon Standstill from Mastok Wrilehiss, the orc in the north of the post (level 23)

step
  .goto Ashenvale,73.1,61.5
  .accept 6441 >>Accept Satyr Horns from Pixel, the goblin in the middle of the post

step
  .goto Ashenvale,74.0,60.6
  .hs Splintertree Post >>Set your hearthstone at the Splintertree Post inn (Innkeeper Kaylisk)
  .vendor

step
  .goto Ashenvale,73.2,61.6
  .text >>Talk to Vhulgra, the wind rider master by the inn, to learn the Splintertree Post flight path

-- South-east loop: the Warsong Lumber Camp ---------------------------------------------------------------------------------

step
  .goto Ashenvale,71.1,68.1
  .accept 6503 >>Accept Ashenvale Outrunners from Kuray'bin at the Warsong Lumber Camp, south of the post

step
  .goto Ashenvale,71.0,68.4
  .optional >>The Warsong Reports
  .accept 6547 >>Accept Warsong Scout Update from the Warsong Scout in the camp
  .turnin 6547 >>...and hand it straight back for his report

step
  .goto Ashenvale,72.5,72.5
  .complete 6503,1 >>Kill Ashenvale Outrunners (lvl 23-24), the night elf patrols in the woods around and south of the lumber camp (70-76,69-76)

step
  .goto Ashenvale,68.3,75.3
  .optional >>Torek's Assault: Torek and his grunts march on the Silverwind Refuge (Alliance sentinels lvl 24-26) — a group event, and a long one; join in if you have company
  .accept 6544 >>Accept Torek's Assault from Torek, south-west of the lumber camp, and follow his band west to the Silverwind Refuge

step
  .goto Ashenvale,71.1,68.1
  .turnin 6503 >>Turn in Ashenvale Outrunners to Kuray'bin

-- East loop: Xavian and Satyrnaar -------------------------------------------------------------------------------------------

step
  .goto Ashenvale,67.9,54.4
  .complete 6441,1 >>Loot 12 Satyr Horns (45% drop) from the Felmusk satyrs (lvl 25-27) at Xavian, the ruins on the hill north-west of Splintertree (66-69,51-56); the Bleakheart satyrs (lvl 26-28) at Satyrnaar, east of the post (79-83,44-52), drop them too — the casters (Hellcallers, Felsworn) hurt, pull them one at a time

step
  .goto Ashenvale,81.8,53.5
  .optional >>The Warsong Reports
  .accept 6546 >>Accept Warsong Outrider Update from the Warsong Outrider at the south edge of Satyrnaar, east of the post
  .turnin 6546 >>...and hand it straight back for his report

step
  .goto Ashenvale,73.1,61.5
  .turnin 6441 >>Turn in Satyr Horns to Pixel in Splintertree Post

step
  .goto Ashenvale,73.0,62.5
  .optional >>Torek's Assault
  .turnin 6544 >>Turn in Torek's Assault to Ertog Ragetusk in Splintertree Post, once the assault is over

-- West trip 1: Mystral Lake ------------------------------------------------------------------------------------------------------

step
  .goto Ashenvale,49.4,69.8
  .complete 25 >>Follow the road west out of Splintertree and turn south to Mystral Lake: kill Befouled Water Elementals (lvl 23-25) around the shore and wade out to the altar in the middle of the lake (48.9,69.6) to explore it

step
  .goto Ashenvale,49.4,69.8
  .item 16408
  .accept 1918 >>The Befouled Water Globe that dropped from the elementals starts The Befouled Element — accept it from the globe; Mastok in Splintertree wants it (turned in when you are back)

-- West trip 2: Zoram'gar Outpost and the Zoram Strand -------------------------------------------------------------------------------

step
  .goto Ashenvale,11.6,34.3
  .turnin 6562 >>Continue west along the road. Astranaar, the Alliance town on the island (35,50), has lvl 50+ guards: leave the road before the bridge, go around the lake on its south side and rejoin the road west of the town; Maestra's Post further along (26,37) is Alliance too — keep to the south of it. At Zoram'gar Outpost on the coast, turn in Trouble in the Deeps to Je'neu Sancrea (Tsunaman's letter from Sun Rock Retreat — if you came from Hillsbrad you do not have it, click Next)

step
  .goto Ashenvale,11.6,34.3
  .optional >>The Essence of Aku'Mai: three sapphires from the floor of the Blackfathom Deeps entrance cave at the north end of the Zoram Strand (satyrs and naga lvl 20-22 outside the instance — solo at 25)
  .accept 6563 >>Accept The Essence of Aku'Mai from Je'neu Sancrea

step
  .goto Ashenvale,11.7,34.9
  .accept 6442 >>Accept Naga at the Zoram Strand from Marukai

step
  .goto Ashenvale,11.6,34.9
  .accept 6462 >>Accept Troll Charm from Mitsuwa, next to Marukai

step
  .goto Ashenvale,11.9,34.5
  .accept 216 >>Accept Between a Rock and a Thistlefur from Karang Amakkar

step
  .goto Ashenvale,12.1,34.6
  .optional >>Vorsha the Lasher: Muglash leads you up the Zoram Strand to the naga altar and calls Vorsha (an elite hydra) — a group quest
  .accept 6641 >>Accept Vorsha the Lasher from Muglash and follow him north along the strand

step
  .goto Ashenvale,12.2,34.2
  .optional >>The Warsong Reports
  .accept 6545 >>Accept Warsong Runner Update from the Warsong Runner in the outpost
  .turnin 6545 >>...and hand it straight back for her report

step
  .goto Ashenvale,11.9,34.5
  .vendor >>Sell, repair and restock at Zoram'gar (there is no inn — the hearth stays at Splintertree)

step
  .goto Ashenvale,11.3,28.0
  .complete 6442,1 >>Kill the Wrathtail naga on the Zoram Strand north of the outpost for 20 Wrathtail Heads (always drop): Razortails and Sea Witches (lvl 18-20) near the outpost, Myrmidons and Priestesses (lvl 20-21) further up the coast (7,14)

step
  .goto Ashenvale,11.3,28.0
  .optional >>Vorsha the Lasher
  .complete 6641 >>Stay with Muglash on the strand: he lights the naga brazier and Vorsha the Lasher surfaces with her naga — kill her

step
  .goto Ashenvale,14.0,10.8
  .optional >>The Essence of Aku'Mai
  .complete 6563,1 >>Pick up 3 Sapphires of Aku'Mai from the floor of the Blackfathom Deeps cave at the north end of the strand (12-17,10-13; Fallenroot satyrs and Blackfathom naga lvl 20-22 — stay outside the instance portal)

step
  .goto Ashenvale,11.7,34.9
  .turnin 6442 >>Turn in Naga at the Zoram Strand to Marukai (walk back down the strand)

step
  .goto Ashenvale,11.6,34.3
  .optional >>The Essence of Aku'Mai
  .turnin 6563 >>Turn in The Essence of Aku'Mai to Je'neu Sancrea (his follow-up, Amongst the Ruins, is inside Blackfathom Deeps — a dungeon quest)

step
  .goto Ashenvale,12.2,34.2
  .optional >>Vorsha the Lasher
  .turnin 6641 >>Turn in Vorsha the Lasher to the Warsong Runner

-- West trip 3: the Thistlefur Village ---------------------------------------------------------------------------------------------

step
  .goto Ashenvale,34.1,38.4
  .complete 216 >>Kill Thistlefur Shamans and Thistlefur Avengers (lvl 23-24) at the Thistlefur Village, the furbolg dens on the hills north of the road between Zoram'gar and Astranaar (31-40,31-46) — the Ursas and Totemics there are the same level

step
  .goto Ashenvale,40.9,33.6
  .complete 6462,1 >>Open one of the Troll Chests in the furbolg huts on the east side of the village (39-43,31-36) for Mitsuwa's Troll Charm

step
  .goto Ashenvale,41.5,34.5
  .accept 6482 >>Accept Freedom to Ruul from Ruul Snowhoof, caged at the east end of the village: open the cage and follow the bear down to the road (Thistlefur ambushes, lvl 23-25) — the turn-in is Yama Snowhoof in Splintertree

step
  .goto Ashenvale,11.9,34.5
  .turnin 216 >>Turn in Between a Rock and a Thistlefur to Karang Amakkar (walk back west to Zoram'gar)

step
  .goto Ashenvale,11.9,34.5
  .optional >>King of the Foulweald: Chief Murgut (lvl 26) at the Foulweald village near Mystral Lake, but the totem comes back here to Zoram'gar — only with a second trip west
  .accept 6621 >>Accept King of the Foulweald from Karang Amakkar

step
  .goto Ashenvale,11.6,34.9
  .turnin 6462 >>Turn in Troll Charm to Mitsuwa

-- Back east: Splintertree turn-ins, the Foulweald (optional), the Ashenvale Hunt (optional) ---------------------------------------

step
  .goto Ashenvale,74.1,60.9
  .xp 24
  .turnin 6482 >>Turn in Freedom to Ruul to Yama Snowhoof in Splintertree Post (hearth)

step
  .goto Ashenvale,73.7,60.0
  .turnin 25 >>Turn in Stonetalon Standstill to Mastok Wrilehiss (his follow-up, Je'neu of the Earthen Ring, only opens after The Befouled Element — a hand-off back to Zoram'gar; skip it)

step
  .goto Ashenvale,73.7,60.0
  .item 16408
  .turnin 1918 >>Turn in The Befouled Element to Mastok Wrilehiss

step
  .goto Ashenvale,56.7,64.1
  .optional >>King of the Foulweald
  .complete 6621 >>At the Foulweald village south-west of Splintertree (53-57,60-64; furbolgs lvl 23-25): place Murgut's Totem Basket at the totem in the middle of the village to call Chief Murgut (lvl 26), kill him and take his totem

step
  .goto Ashenvale,11.9,34.5
  .optional >>King of the Foulweald
  .turnin 6621 >>Turn in King of the Foulweald to Karang Amakkar at Zoram'gar Outpost (a long walk west — pair it with anything else you left in the west)

step
  .goto Ashenvale,39.8,65.2
  .optional >>The Ashenvale Hunt
  .accept 23 >>Kill Ursangous (lvl 25 elite bear) in the woods south of Astranaar, around Iris Lake, and accept Ursangous's Paw from the paw he drops

step
  .goto Ashenvale,57.5,56.1
  .optional >>The Ashenvale Hunt
  .accept 24 >>Kill Shadumbra (lvl 28 elite nightsaber) north of Mystral Lake, west of Raynewood Retreat, and accept Shadumbra's Head from her head

step
  .goto Ashenvale,75.0,70.1
  .optional >>The Ashenvale Hunt
  .accept 2 >>Kill Sharptalon (lvl 31 elite hippogryph) in the woods south-east of the Warsong Lumber Camp and accept Sharptalon's Claw from the claw

step
  .goto Ashenvale,73.8,61.5
  .optional >>The Ashenvale Hunt
  .turnin 23 >>Turn in Ursangous's Paw to Senani Thunderheart in Splintertree Post
  .turnin 24 >>Turn in Shadumbra's Head
  .turnin 2 >>Turn in Sharptalon's Claw

step
  .goto Ashenvale,73.8,61.5
  .optional >>The Ashenvale Hunt
  .accept 247 >>Accept The Hunt Completed from Senani Thunderheart
  .turnin 247 >>...and hand it straight back

-- Level 26-27: the road out ------------------------------------------------------------------------------------------------------

step
  .goto Ashenvale,74.0,60.6
  .xp 25 >>You should be level 25 by now — Ashenvale's Horde quests run out here and Thousand Needles' start at 25. If you are short, the satyrs at Xavian and Satyrnaar (lvl 25-28) are the grind, the elite hunts above are worth a group, and Blackfathom Deeps (lvl 22-28, at the north end of the Zoram Strand) is the dungeon for this band

step
  .goto Ashenvale,68.6,89.1
  .optional >>The Warsong Reports
  .turnin 6543 >>Turn in The Warsong Reports to Kadrak at the Mor'shan Rampart (walk south from Splintertree; the road continues into the Barrens if you would rather walk to Camp Taurajo)

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .fly Thunder Bluff >>Fly from Splintertree Post to Thunder Bluff (the wind riders route you through the Crossroads)

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .train >>Train new skills at your class trainer in Thunder Bluff, sell and repair

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .fly Orgrimmar >>Fly from Splintertree Post to Orgrimmar

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll,Undead
  .train >>Train new skills at your class trainer in Orgrimmar, sell and repair

step
  .goto The Barrens,44.4,59.2
  .fly Camp Taurajo >>Fly to Camp Taurajo in the southern Barrens (Undead who never learned its path: fly to the Crossroads and take the road south past the Stagnant Oasis and the Field of Giants — talk to Omusa Thunderhorn at the camp for the flight path)

step
  .goto The Barrens,44.2,92.2
  .text >>Follow the road south out of Camp Taurajo through the Bristleback quilboar (lvl 16-20) to the Great Lift at the southern edge of the Barrens; Brave Moonhorn and Grish Longrunner wait at the top of the lift

step
  .zone Thousand Needles >>Take the Great Lift down into Thousand Needles
]], "Lodestar_Guides_Horde")

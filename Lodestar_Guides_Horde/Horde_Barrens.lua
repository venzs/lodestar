-- Lodestar Guides: Horde — The Barrens (levels 12-20), where the Durotar and Mulgore routes meet.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Crossroads loops (north: the Razormane and the
-- plainstriders; west: the Kolkar, the Forgotten Pools and the Witchwing harpies; east: Kreenig
-- Snarlsnout and Echeyakee; south-east: Ratchet and the Southsea pirates; south: the oases, the
-- Kolkar leaders and Camp Taurajo). The Sludge Fen (Samophlange), Wailing Caverns and the 20+ Camp
-- Taurajo chains are optional or left to the next guide. Every quest id and position comes from the
-- data; the order still has to be verified in play (/lode record).
-- Orcs and Trolls arrive at Far Watch Post from Durotar, Tauren at Camp Taurajo from Mulgore; the
-- .race steps at the top cover both.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 12-20: The Barrens
#faction Horde
#levels 12-19
#next Horde 20-25: Stonetalon Mountains
#author Lodestar
-- #levels stops at 19 so the auto-pick hands a level 20 character to the next guide; the route itself runs to 20.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Arrival: Tauren from Mulgore (Camp Taurajo) ------------------------------------------------------------------

step
  .goto The Barrens,44.9,58.6
  .race Tauren
  .accept 854 >>Accept Journey to the Crossroads from Kirge Sternhorn in Camp Taurajo, just past the pass from Mulgore

step
  .goto The Barrens,44.4,59.2
  .race Tauren
  .text >>Talk to Omusa Thunderhorn, the wind rider master in Camp Taurajo, to learn the flight path, then follow the road north to the Crossroads (Bristleback quilboar and thunder lizards along the way, lvl 16-19 — stay on the road)

-- Arrival: Orcs and Trolls from Durotar (Far Watch Post) --------------------------------------------------------------

step
  .goto The Barrens,62.3,19.4
  .race Orc,Troll
  .turnin 840 >>Turn in Conscript of the Horde to Kargal Battlescar at Far Watch Post, the tower just past the bridge from Durotar
  .accept 842 >>Accept Crossroads Conscription

step
  .goto The Barrens,62.3,20.1
  .race Orc,Troll
  .turnin 809 >>Turn in Ak'Zeloth to Ak'Zeloth, next to the tower
  .accept 924 >>Accept The Demon Seed — the Altar of Fire is north-west of the Crossroads, on the western loop

step
  .goto The Barrens,61.4,21.1
  .class Warrior
  .turnin 1505 >>Turn in Veteran Uzzek to Uzzek at Far Watch Post

step
  .goto The Barrens,61.4,21.1
  .class Warrior
  .optional >>Path of Defense sends you back to Thunder Ridge in Durotar for Singed Scales; the reward chain (Thun'grim's Forged Steel) gives a good level 10 weapon
  .accept 1498 >>Accept Path of Defense from Uzzek

step
  .goto Durotar,39.2,29.2
  .class Warrior
  .optional >>Path of Defense
  .complete 1498,1 >>Loot Singed Scales from Thunder Lizards and Lightning Hides on Thunder Ridge, back across the river in western Durotar (lvl 9-11)

step
  .goto The Barrens,61.4,21.1
  .class Warrior
  .optional >>Path of Defense
  .turnin 1498 >>Turn in Path of Defense to Uzzek at Far Watch Post
  .accept 1502 >>Accept Thun'grim Firegaze

step
  .goto The Barrens,55.9,19.9
  .class Shaman
  .race Orc,Troll
  .turnin 2983 >>Turn in Call of Fire to Kranal Fiss, on the road west of Far Watch Post
  .accept 1524 >>Accept Call of Fire (part 2) — Telf Joolam at the river

step
  .goto The Barrens,55.9,19.9
  .class Shaman
  .race Tauren
  .turnin 2984 >>Turn in Call of Fire to Kranal Fiss, on the road between the Crossroads and Far Watch Post (north-east)
  .accept 1524 >>Accept Call of Fire (part 2) — Telf Joolam at the river

step
  .goto The Barrens,65.4,27.9
  .class Shaman
  .turnin 1524 >>Turn in Call of Fire to Telf Joolam on the bank of the Southfury River, east of the road
  .accept 1525 >>Accept Call of Fire (part 3) — Fire Tar from the Razormane here and a Reagent Pouch from the Burning Blade in Durotar

-- The Crossroads: first visit -----------------------------------------------------------------------------------------

step
  .goto The Barrens,51.5,30.9
  .race Tauren
  .turnin 854 >>Turn in Journey to the Crossroads to Thork, the orc at the north entrance of the Crossroads

step
  .goto The Barrens,51.5,30.9
  .accept 871 >>Accept Disrupt the Attacks from Thork
  .accept 5041 >>Accept Supplies for the Crossroads

step
  .goto The Barrens,52.2,31.0
  .race Orc,Troll
  .turnin 842 >>Turn in Crossroads Conscription to Sergra Darkthorn, on the platform in the middle of town

step
  .goto The Barrens,52.2,31.0
  .race Tauren
  .turnin 860 >>Turn in Sergra Darkthorn to Sergra Darkthorn, on the platform in the middle of town

step
  .goto The Barrens,52.2,31.0
  .accept 844 >>Accept Plainstrider Menace from Sergra Darkthorn

step
  .goto The Barrens,51.9,30.3
  .accept 869 >>Accept Raptor Thieves from Gazrog, in the northern hut

step
  .goto The Barrens,51.4,30.2
  .accept 848 >>Accept Fungal Spores from Apothecary Helbrim, next to Gazrog
  .accept 1492 >>Accept Wharfmaster Dizzywig — a hand-off in Ratchet

step
  .goto The Barrens,51.6,30.9
  .accept 867 >>Accept Harpy Raiders from Darsok Swiftdagger, by Thork

step
  .goto The Barrens,52.3,31.9
  .race Tauren
  .turnin 886 >>Turn in The Barrens Oases to Tonga Runetotem, south end of the Crossroads

step
  .goto The Barrens,52.3,31.9
  .accept 870 >>Accept The Forgotten Pools from Tonga Runetotem (if he has nothing for you, the chain starts with The Barrens Oases from Hamuul Runetotem in Thunder Bluff — skip it)

step
  .goto The Barrens,52.0,29.9
  .hs The Crossroads >>Set your hearthstone at the Crossroads inn (Boorand Plainswind)
  .vendor

step
  .goto The Barrens,51.5,30.3
  .text >>Talk to Devrak, the wind rider master by the inn, to learn the Crossroads flight path

-- Optional: the wind rider chains, a free flight to your capital and back ------------------------------------------------

step
  .goto The Barrens,52.6,29.8
  .race Orc,Troll
  .optional >>A free round trip to Orgrimmar with four small turn-ins — you get the Orgrimmar flight path out of it; skip on a speed run
  .accept 6365 >>Accept Meats to Orgrimmar from Zargh, the butcher by the inn

step
  .goto The Barrens,51.5,30.3
  .race Orc,Troll
  .optional >>Wind rider chain
  .turnin 6365 >>Turn in Meats to Orgrimmar to Devrak
  .accept 6384 >>Accept Ride to Orgrimmar — he flies you there for free

step
  .goto Orgrimmar,54.1,68.4
  .race Orc,Troll
  .optional >>Wind rider chain
  .turnin 6384 >>Turn in Ride to Orgrimmar to Innkeeper Gryshka in Orgrimmar
  .accept 6385 >>Accept Doras the Wind Rider Master

step
  .goto Orgrimmar,45.1,63.9
  .race Orc,Troll
  .optional >>Wind rider chain
  .turnin 6385 >>Turn in Doras the Wind Rider Master to Doras
  .accept 6386 >>Accept Return to the Crossroads. — a free flight back

step
  .goto The Barrens,52.6,29.8
  .race Orc,Troll
  .optional >>Wind rider chain
  .turnin 6386 >>Turn in Return to the Crossroads. to Zargh

step
  .goto The Barrens,51.2,29.0
  .race Tauren
  .optional >>A free round trip to Thunder Bluff with four small turn-ins; skip on a speed run
  .accept 6361 >>Accept A Bundle of Hides from Jahan Hawkwing, north-west corner of the Crossroads

step
  .goto The Barrens,51.5,30.3
  .race Tauren
  .optional >>Wind rider chain
  .turnin 6361 >>Turn in A Bundle of Hides to Devrak
  .accept 6362 >>Accept Ride to Thunder Bluff — a free flight

step
  .goto Thunder Bluff,45.8,55.8
  .race Tauren
  .optional >>Wind rider chain
  .turnin 6362 >>Turn in Ride to Thunder Bluff to Ahanu on the central rise
  .accept 6363 >>Accept Tal the Wind Rider Master

step
  .goto Thunder Bluff,47.0,49.8
  .race Tauren
  .optional >>Wind rider chain
  .turnin 6363 >>Turn in Tal the Wind Rider Master to Tal
  .accept 6364 >>Accept Return to Jahan — a free flight back

step
  .goto The Barrens,51.2,29.0
  .race Tauren
  .optional >>Wind rider chain
  .turnin 6364 >>Turn in Return to Jahan to Jahan Hawkwing

-- North loop: the Razormane, the plainstriders, the raptors -------------------------------------------------------------------

step
  .goto The Barrens,55.1,26.6
  .complete 871,2 >>Kill Razormane Water Seekers at the quilboar camps north-east of the Crossroads (lvl 10-11)
  .complete 871,3 >>Kill Razormane Thornweavers there (lvl 10-11)

step
  .goto The Barrens,57.8,24.4
  .complete 871,1 >>Kill Razormane Hunters further north-east (lvl 11-12)

step
  .goto The Barrens,55.1,26.6
  .class Shaman
  .complete 1525,1 >>Loot Fire Tar from the Razormane Water Seekers and Thornweavers here (lvl 10-11, 25% drop)

step
  .goto The Barrens,58.5,25.9
  .complete 5041,1 >>Pick up 5 Crossroads' Supply Crates scattered around the Razormane camps

step
  .goto The Barrens,51.7,23.1
  .complete 844,1 >>Kill Greater Plainstriders on the plain north of the Crossroads for 7 Plainstrider Beaks (lvl 11-12)

step
  .goto The Barrens,51.3,22.6
  .complete 869,1 >>Kill Sunscale Lashtails north of the Crossroads for 6 Raptor Heads (lvl 11-13)

-- The Crossroads: second visit ------------------------------------------------------------------------------------------------

step
  .goto The Barrens,51.5,30.9
  .turnin 871 >>Turn in Disrupt the Attacks to Thork (hearth to the Crossroads)
  .turnin 5041 >>Turn in Supplies for the Crossroads
  .accept 872 >>Accept The Disruption Ends

step
  .goto The Barrens,52.2,31.0
  .turnin 844 >>Turn in Plainstrider Menace to Sergra Darkthorn
  .accept 845 >>Accept The Zhevra

step
  .goto The Barrens,51.9,30.3
  .turnin 869 >>Turn in Raptor Thieves to Gazrog
  .accept 3281 >>Accept Stolen Silver — south of Ratchet, for the south-east loop later

-- West loop: the Zhevra, the Kolkar, the Forgotten Pools, the Witchwing harpies ----------------------------------------------

step
  .goto The Barrens,47.1,28.6
  .complete 845,1 >>Kill Zhevra Runners on the plain west of the Crossroads for 4 Zhevra Hooves (lvl 13-14, 40% drop)

step
  .goto The Barrens,45.3,28.4
  .accept 855 >>Accept Centaur Bracers from Regthar Deathgate in the bunker west of the Crossroads
  .accept 850 >>Accept Kolkar Leaders

step
  .goto The Barrens,43.6,26.9
  .complete 855,1 >>Kill Kolkar Wranglers at the centaur camps west and north-west of the bunker for 15 Centaur Bracers (lvl 12-13; Stormers lvl 13-14 drop them too)

step
  .goto The Barrens,42.8,23.5
  .complete 850,1 >>Kill Barak Kodobane in the northern Kolkar camp (lvl 16 — pull him away from the others) and take his head

step
  .goto The Barrens,45.1,22.5
  .complete 870,1 >>Walk down to the Forgotten Pools, the oasis north-west of the Crossroads, to explore it

step
  .goto The Barrens,48.0,19.1
  .race Orc,Troll
  .complete 924,1 >>Use the Demon Seed at the Altar of Fire, on the hill north of the Forgotten Pools

step
  .goto The Barrens,40.9,17.2
  .complete 867,1 >>Kill Witchwing Harpies and Roguefeathers on the cliffs in the north-west for 10 Witchwing Talons (lvl 14-16)

step
  .goto The Barrens,45.3,28.4
  .turnin 855 >>Turn in Centaur Bracers to Regthar Deathgate
  .turnin 850 >>Turn in Kolkar Leaders
  .accept 851 >>Accept Verog the Dervish — he is at the Kolkar camp south of the Crossroads, on the southern loop

step
  .goto The Barrens,47.4,37.5
  .complete 848,1 >>Pick 8 Fungal Spores from the Laden Mushrooms around the Wailing Caverns hill, south-west of the Crossroads (Deviate beasts lvl 15-17 around the entrance — stay on the slopes)

-- The Crossroads: third visit --------------------------------------------------------------------------------------------------

step
  .goto The Barrens,52.2,31.0
  .turnin 845 >>Turn in The Zhevra to Sergra Darkthorn
  .accept 903 >>Accept Prowlers of the Barrens

step
  .goto The Barrens,51.6,30.9
  .turnin 867 >>Turn in Harpy Raiders to Darsok Swiftdagger
  .accept 875 >>Accept Harpy Lieutenants

step
  .goto The Barrens,52.3,31.9
  .turnin 870 >>Turn in The Forgotten Pools to Tonga Runetotem
  .accept 877 >>Accept The Stagnant Oasis

step
  .goto The Barrens,51.4,30.2
  .turnin 848 >>Turn in Fungal Spores to Apothecary Helbrim (his follow-up, Apothecary Zamah, is a hand-off in Thunder Bluff — take it if you fly there anyway)

step
  .goto The Barrens,52.0,31.6
  .xp 14
  .accept 4921 >>Accept Lost in Battle from Mankrik, by Sergra (level 14) — the Beaten Corpse is south, on the way to Ratchet later

step
  .goto The Barrens,52.0,31.6
  .optional >>Consumed by Hatred: 30 Bristleback tusks from the quilboar south of the Crossroads — lots of kills, fair XP, take it if you will grind there anyway
  .accept 899 >>Accept Consumed by Hatred from Mankrik

step
  .goto The Barrens,52.0,29.9
  .vendor >>Sell junk and restock at the Crossroads

-- North-west loop 2: prowlers and the harpy lieutenants -------------------------------------------------------------------------

step
  .goto The Barrens,42.0,23.5
  .complete 903,1 >>Kill Savannah Prowlers on the plains north-west of the Crossroads for 7 Prowler Claws (lvl 14-15)

step
  .goto The Barrens,38.9,14.3
  .complete 875,1 >>Kill Witchwing Slayers at the harpy roost in the far north-west for 8 Harpy Lieutenant Rings (lvl 16-17, 40% drop; Ambushers lvl 17-18 nearby)

step
  .goto The Barrens,52.2,31.0
  .turnin 903 >>Turn in Prowlers of the Barrens to Sergra Darkthorn (hearth to the Crossroads)
  .accept 881 >>Accept Echeyakee

step
  .goto The Barrens,51.6,30.9
  .turnin 875 >>Turn in Harpy Lieutenants to Darsok Swiftdagger

step
  .goto The Barrens,51.6,30.9
  .optional >>Serena Bloodfeather (lvl 20, with harpy guards) in the far north-west corner — come back at 19-20 or with a partner
  .accept 876 >>Accept Serena Bloodfeather from Darsok Swiftdagger

-- East loop: Kreenig Snarlsnout, Echeyakee, Far Watch Post -----------------------------------------------------------------------

step
  .goto The Barrens,58.9,25.1
  .xp 15
  .complete 872,1 >>Kill Razormane Defenders at the quilboar camps north-east of the Crossroads (lvl 12-13)
  .complete 872,2 >>Kill Razormane Geomancers there (lvl 12-13)
  .complete 872,3 >>Kill Kreenig Snarlsnout, the quilboar boss in the biggest camp (lvl 14), and take his tusk

step
  .goto The Barrens,56.1,17.4
  .complete 881,1 >>Blow Echeyakee's Horn at the bones north of the Razormane camps (56,17) and kill Echeyakee, the white lion (lvl 16), for his hide

step
  .goto The Barrens,62.3,20.1
  .race Orc,Troll
  .turnin 924 >>Turn in The Demon Seed to Ak'Zeloth at Far Watch Post

step
  .goto The Barrens,62.3,20.0
  .race Orc,Troll
  .accept 926 >>Pick up Flawed Power Stone from the Flawed Power Stones next to Ak'Zeloth
  .turnin 926 >>...and hand it straight back in at the same stones

step
  .goto The Barrens,57.2,30.3
  .class Warrior
  .optional >>Thun'grim's chain
  .turnin 1502 >>Turn in Thun'grim Firegaze to Thun'grim Firegaze, on the hill east of the Crossroads road
  .accept 1503 >>Accept Forged Steel — the Stolen Iron Chest at the Razormane camp (55,26.7)

step
  .goto The Barrens,55.0,26.7
  .class Warrior
  .optional >>Thun'grim's chain
  .complete 1503,1 >>Take the Forged Steel Bars from the Stolen Iron Chest at the Razormane camp

step
  .goto The Barrens,57.2,30.3
  .class Warrior
  .optional >>Thun'grim's chain
  .turnin 1503 >>Turn in Forged Steel to Thun'grim Firegaze and pick your weapon

step
  .goto Durotar,52.7,25.4
  .class Shaman
  .complete 1525,2 >>Cross the bridge at Far Watch Post into Durotar and loot a Reagent Pouch from the Burning Blade Cultists at the camp north of Razor Hill, by Drygulch Ravine (lvl 10-11, 25% drop)

step
  .goto The Barrens,65.4,27.9
  .class Shaman
  .turnin 1525 >>Turn in Call of Fire to Telf Joolam at the river
  .accept 1526 >>Accept Call of Fire (part 4)

step
  .goto Durotar,38.9,58.3
  .class Shaman
  .complete 1526,1 >>Use the brazier next to Telf Joolam and kill the Minor Manifestation of Fire it summons (lvl 12) for the Glowing Ember

step
  .goto Durotar,39.0,58.2
  .class Shaman
  .turnin 1526 >>Turn in Call of Fire at the Brazier of the Dormant Flame
  .accept 1527 >>Accept Call of Fire (part 5) from the brazier

step
  .goto The Barrens,55.9,19.9
  .class Shaman
  .turnin 1527 >>Turn in Call of Fire to Kranal Fiss for your Fire Totem

step
  .goto The Barrens,51.5,30.9
  .turnin 872 >>Turn in The Disruption Ends to Thork (hearth to the Crossroads)

step
  .goto The Barrens,52.2,31.0
  .turnin 881 >>Turn in Echeyakee to Sergra Darkthorn
  .accept 905 >>Accept The Angry Scytheclaws

-- South-east loop: the oases, Verog, Ratchet and the Southsea pirates --------------------------------------------------------

step
  .goto The Barrens,55.6,42.7
  .complete 877,1 >>Use Tonga's seeds at the Bubbling Fissure in the Stagnant Oasis, south-east of the Crossroads (Altered Snapjaws around the pool, lvl 16-17)

step
  .goto The Barrens,52.9,41.8
  .complete 851,1 >>Kill Verog the Dervish at the Kolkar camp west of the Stagnant Oasis (lvl 18 — pull him to the edge of the camp) and take his head

step
  .goto The Barrens,52.5,46.6
  .complete 905 >>At the raptor grounds south of the oasis: loot Sunscale Feathers from the Sunscale raptors (lvl 16-18) and place one in the Red, Blue and Yellow Raptor Nests (52.5,46.6 / 52.6,46.1 / 52,46.5)

step
  .goto The Barrens,49.3,50.3
  .complete 4921 >>Examine the Beaten Corpse on the road south of the raptor grounds (Mankrik's wife)

step
  .goto The Barrens,63.4,38.5
  .turnin 1492 >>Turn in Wharfmaster Dizzywig to Wharfmaster Dizzywig on the docks in Ratchet

step
  .goto The Barrens,62.7,36.2
  .accept 887 >>Accept Southsea Freebooters from Gazlowe, up the hill in Ratchet

step
  .goto The Barrens,62.6,37.5
  .accept 895 >>Accept WANTED: Baron Longshore from the poster in the middle of Ratchet

step
  .goto The Barrens,63.0,37.2
  .accept 894 >>Accept Samophlange from Sputtervalve — the Sludge Fen, far north; optional later

step
  .goto The Barrens,63.1,37.2
  .text >>Talk to Bragok, the wind rider master on the hill, to learn the Ratchet flight path

step
  .goto The Barrens,62.0,39.4
  .vendor >>Sell, repair and restock in Ratchet (Innkeeper Wiley's inn)

step
  .goto The Barrens,63.6,46.2
  .complete 887,1 >>Kill Southsea Brigands at the pirate camps on the coast south of Ratchet (lvl 12-13)
  .complete 887,2 >>Kill Southsea Cannoneers there (lvl 13-14)

step
  .goto The Barrens,63.6,49.1
  .complete 895,1 >>Kill Baron Longshore in the pirate camp (lvl 16) and take his head

step
  .goto The Barrens,58.0,53.9
  .complete 3281,1 >>Pick up the Stolen Silver from the chest in the Southsea camp further south-west along the coast (Northwatch soldiers to the south — avoid them)

step
  .goto The Barrens,62.7,36.2
  .turnin 887 >>Turn in Southsea Freebooters to Gazlowe (walk back up to Ratchet)
  .turnin 895 >>Turn in WANTED: Baron Longshore
  .accept 890 >>Accept The Missing Shipment

step
  .goto The Barrens,63.4,38.5
  .turnin 890 >>Turn in The Missing Shipment to Wharfmaster Dizzywig
  .accept 892 >>Accept The Missing Shipment (part 2)

step
  .goto The Barrens,62.7,36.2
  .turnin 892 >>Turn in The Missing Shipment to Gazlowe
  .accept 888 >>Accept Stolen Booty

step
  .goto The Barrens,62.6,49.6
  .complete 888,1 >>Back at the pirate camp: take the Shipment of Boots from the crate by Drizzlik's Emporium
  .complete 888,2 >>...and the Telescopic Lens from the "Fragile - Do Not Drop" crate next to it

step
  .goto The Barrens,62.7,36.2
  .turnin 888 >>Turn in Stolen Booty to Gazlowe

-- Optional: the Sludge Fen (Samophlange, Wizzlecrank) ---------------------------------------------------------------------------

step
  .goto The Barrens,52.4,11.6
  .optional >>Samophlange: a long trip to the Sludge Fen in the far north for a chain of small turn-ins; fly to the Crossroads and walk north
  .turnin 894 >>Turn in Samophlange at the Control Console in the Sludge Fen, the Venture Co. oil field north of the Crossroads (Venture Co. goblins lvl 16-18)
  .accept 900 >>Accept Samophlange (part 2) from the console

step
  .goto The Barrens,52.3,11.6
  .optional >>Samophlange
  .complete 900,1 >>Shut off the Main Control Valve
  .complete 900,2 >>Shut off the Regulator Valve
  .complete 900,3 >>Shut off the Fuel Control Valve

step
  .goto The Barrens,52.4,11.6
  .optional >>Samophlange
  .turnin 900 >>Turn in Samophlange at the Control Console
  .accept 901 >>Accept Samophlange (part 3)

step
  .goto The Barrens,52.8,10.4
  .optional >>Samophlange
  .complete 901,1 >>Kill Tinkerer Sniggles, who comes running when the valves close (lvl 16), for the Console Key

step
  .goto The Barrens,52.4,11.6
  .optional >>Samophlange
  .turnin 901 >>Turn in Samophlange at the Control Console
  .accept 902 >>Accept Samophlange (part 4) — back to Sputtervalve in Ratchet

step
  .goto The Barrens,56.5,7.5
  .optional >>Wizzlecrank's Shredder: an escort from the Sludge Fen to the road, then a turn-in in Ratchet
  .accept 858 >>Accept Ignition from Wizzlecrank's Shredder, the goblin in the shredder at the north end of the Sludge Fen

step
  .goto The Barrens,56.3,8.6
  .optional >>Wizzlecrank's Shredder
  .complete 858,1 >>Kill Supervisor Lugwizzle in the Sludge Fen (lvl 18) for the Ignition Key

step
  .goto The Barrens,56.5,7.5
  .optional >>Wizzlecrank's Shredder
  .turnin 858 >>Turn in Ignition to Wizzlecrank's Shredder
  .accept 863 >>Accept The Escape and follow the shredder south until it stops (Venture Co. ambushes, lvl 16-18)

step
  .goto The Barrens,63.0,37.2
  .optional >>Samophlange
  .turnin 902 >>Turn in Samophlange to Sputtervalve in Ratchet (fly from the Crossroads)

step
  .goto The Barrens,63.0,37.2
  .optional >>Wizzlecrank's Shredder
  .turnin 863 >>Turn in The Escape to Sputtervalve in Ratchet

-- Optional: Wailing Caverns and the deviates ------------------------------------------------------------------------------------

step
  .goto The Barrens,46.0,35.7
  .optional >>Wailing Caverns (lvl 17-24 dungeon) — the outer cave has quests of its own; take these if you run the instance or grind the deviates
  .accept 1486 >>Accept Deviate Hides from Nalpak, on the ledge outside the Wailing Caverns entrance

step
  .goto The Barrens,63.1,37.6
  .optional >>Wailing Caverns
  .accept 959 >>Accept Trouble at the Docks from Crane Operator Bigglefuzz on the Ratchet docks — Mad Magglish hides in the Wailing Caverns cave

step
  .goto The Barrens,62.4,37.6
  .optional >>Wailing Caverns
  .accept 865 >>Accept Raptor Horns from Mebok Mizzyrix in Ratchet (Sunscale Scytheclaws south of the Crossroads)

step
  .goto The Barrens,46.1,34.6
  .optional >>Wailing Caverns
  .complete 1486,1 >>Loot 20 Deviate Hides from the Deviate beasts in the Wailing Caverns cave, outside the instance portal (lvl 15-17)

step
  .goto The Barrens,45.7,33.6
  .optional >>Wailing Caverns
  .complete 959,1 >>Kill Mad Magglish, hiding in a side passage of the cave (lvl 18), for the 99-Year-Old Port

step
  .goto The Barrens,47.8,43.2
  .optional >>Wailing Caverns
  .complete 865,1 >>Kill Sunscale Scytheclaws south of the Crossroads for 5 Intact Raptor Horns (lvl 16-18)

step
  .goto The Barrens,46.0,35.7
  .optional >>Wailing Caverns
  .turnin 1486 >>Turn in Deviate Hides to Nalpak

step
  .goto The Barrens,63.1,37.6
  .optional >>Wailing Caverns
  .turnin 959 >>Turn in Trouble at the Docks to Crane Operator Bigglefuzz in Ratchet

step
  .goto The Barrens,62.4,37.6
  .optional >>Wailing Caverns
  .turnin 865 >>Turn in Raptor Horns to Mebok Mizzyrix

-- The Crossroads: fourth visit, then Hezrul ---------------------------------------------------------------------------------------

step
  .goto The Barrens,52.2,31.0
  .turnin 905 >>Turn in The Angry Scytheclaws to Sergra Darkthorn (fly or hearth to the Crossroads)
  .accept 3261 >>Accept Jorn Skyseer — a hand-off in Camp Taurajo

step
  .goto The Barrens,52.3,31.9
  .turnin 877 >>Turn in The Stagnant Oasis to Tonga Runetotem
  .accept 880 >>Accept Altered Beings

step
  .goto The Barrens,51.9,30.3
  .turnin 3281 >>Turn in Stolen Silver to Gazrog

step
  .goto The Barrens,52.0,31.6
  .turnin 4921 >>Turn in Lost in Battle to Mankrik

step
  .goto The Barrens,45.3,28.4
  .turnin 851 >>Turn in Verog the Dervish to Regthar Deathgate in the bunker west of town
  .accept 852 >>Accept Hezrul Bloodmark

step
  .goto The Barrens,46.0,41.1
  .xp 17
  .complete 852,1 >>Kill Hezrul Bloodmark at the Kolkar camp south-west of the Crossroads (lvl 19, with guards — pull carefully or bring a partner) and take his head

step
  .goto The Barrens,55.6,42.7
  .complete 880,1 >>Loot 6 Altered Snapjaw Shells from the Altered Snapjaws at the Stagnant Oasis (lvl 16-17)

step
  .goto The Barrens,44.9,51.4
  .optional >>Consumed by Hatred
  .complete 899,1 >>Loot 30 Bristleback Quilboar Tusks from the Bristleback quilboar around the Field of Giants, south of the raptor grounds (lvl 16-20)

step
  .goto The Barrens,45.3,28.4
  .turnin 852 >>Turn in Hezrul Bloodmark to Regthar Deathgate (hearth to the Crossroads; he offers Counterattack!, a level 20 event with a group — leave it for later)

step
  .goto The Barrens,52.3,31.9
  .turnin 880 >>Turn in Altered Beings to Tonga Runetotem (his hand-offs to Hamuul in Thunder Bluff and Mura in the Sepulcher lead to the Wailing Caverns chain — skip)

step
  .goto The Barrens,52.0,31.6
  .optional >>Consumed by Hatred
  .turnin 899 >>Turn in Consumed by Hatred to Mankrik

step
  .goto The Barrens,39.2,12.2
  .optional >>Serena Bloodfeather
  .complete 876,1 >>Kill Serena Bloodfeather at the harpy roost in the far north-west corner (lvl 20, with Witchwing guards) and take her head

step
  .goto The Barrens,51.6,30.9
  .optional >>Serena Bloodfeather
  .turnin 876 >>Turn in Serena Bloodfeather to Darsok Swiftdagger (hearth to the Crossroads)

-- Camp Taurajo ------------------------------------------------------------------------------------------------------------------

step
  .goto The Barrens,44.9,59.1
  .turnin 3261 >>Turn in Jorn Skyseer to Jorn Skyseer in Camp Taurajo (fly from the Crossroads if you have the path, otherwise walk the road south)
  .accept 882 >>Accept Ishamuhale

step
  .goto The Barrens,44.4,59.2
  .race Orc,Troll
  .text >>Talk to Omusa Thunderhorn, the wind rider master in Camp Taurajo, to learn the flight path

step
  .goto The Barrens,46.4,43.6
  .complete 882,2 >>Kill a Zhevra Charger on the plains between Camp Taurajo and the Crossroads for a Fresh Zhevra Carcass (lvl 17-18)

step
  .goto The Barrens,59.7,30.3
  .complete 882,1 >>Drop the carcass at the bones east of the Crossroads (59.7,30.3) to lure Ishamuhale (lvl 19) and kill him for his fang

step
  .goto The Barrens,44.9,59.1
  .turnin 882 >>Turn in Ishamuhale to Jorn Skyseer in Camp Taurajo (fly from the Crossroads)
  .accept 907 >>Accept Enraged Thunder Lizards

step
  .goto The Barrens,47.7,51.8
  .complete 907,1 >>Kill Stormsnouts on the plains north of Camp Taurajo for 6 Thunder Lizard Blood (lvl 18-19)

step
  .goto The Barrens,44.9,59.1
  .turnin 907 >>Turn in Enraged Thunder Lizards to Jorn Skyseer (his follow-up, Cry of the Thunderhawk, is a level 20 quest for the next guide)

step
  .goto The Barrens,45.6,59.0
  .xp 19 >>You should be 19-20 by now; if not, kill Bristleback quilboar and thunder lizards north of Camp Taurajo (or do the optional quests above) until you are. Then fly to the Crossroads: the Stonetalon road leaves the Barrens in the north-west, past the harpies

step
  .zone Stonetalon Mountains >>Follow the road north-west out of the Barrens into Stonetalon Mountains (Malaka'jin and the Grimtotem post at the entrance)
]], "Lodestar_Guides_Horde")

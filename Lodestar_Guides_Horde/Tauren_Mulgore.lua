-- Lodestar Guides: Horde — Tauren starting zone, Mulgore (levels 1-12).
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Mulgore route (Camp Narache → the Brambleblade Ravine →
-- Bloodhoof Village with its south-west, south-east and northern loops → the Venture Co. mine →
-- Red Rocks and the Rite of Wisdom → Thunder Bluff). Every quest id and position comes from the data;
-- the order still has to be verified in play (/lode record). Forever-only quests are not in here yet.
-- Tauren classes are Warrior, Hunter, Shaman and Druid; the other .class steps would never show.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde/Tauren 1-12: Mulgore
#faction Horde
#race Tauren
#levels 1-12
#next Horde 12-20: The Barrens
#author Lodestar
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Camp Narache -----------------------------------------------------------------------------------------

step
  .goto Mulgore,44.9,77.1
  .accept 747 >>Accept The Hunt Begins from Grull Hawkwind, right where you spawn

step
  .goto Mulgore,44.2,76.1
  .accept 752 >>Accept A Humble Task from Chief Hawkwind in the big tent

step
  .goto Mulgore,48.1,81.8
  .complete 747,1 >>Kill Plainstriders east and south of the camp for 7 Plainstrider Meat (lvl 1-2)
  .complete 747,2 >>...and 7 Plainstrider Feathers from the same birds

step
  .goto Mulgore,50.0,81.2
  .turnin 752 >>Turn in A Humble Task to Greatmother Hawkwind at the little camp south-east
  .accept 753 >>Accept A Humble Task (part 2)

step
  .goto Mulgore,50.2,81.5
  .complete 753,1 >>Fill the Water Pitcher at the well next to the Greatmother

step
  .goto Mulgore,44.2,76.1
  .turnin 753 >>Turn in A Humble Task to Chief Hawkwind
  .accept 755 >>Accept Rites of the Earthmother

step
  .goto Mulgore,44.9,77.1
  .turnin 747 >>Turn in The Hunt Begins to Grull Hawkwind
  .accept 750 >>Accept The Hunt Continues

-- Class notes (Grull hands them out after The Hunt Begins) ---------------------------------------------

step
  .goto Mulgore,44.9,77.1
  .class Warrior
  .accept 3091 >>Accept Simple Note (warrior) from Grull Hawkwind

step
  .goto Mulgore,44.9,77.1
  .class Hunter
  .accept 3092 >>Accept Etched Note (hunter) from Grull Hawkwind

step
  .goto Mulgore,44.9,77.1
  .class Shaman
  .accept 3093 >>Accept Rune-Inscribed Note (shaman) from Grull Hawkwind

step
  .goto Mulgore,44.9,77.1
  .class Druid
  .accept 3094 >>Accept Verdant Note (druid) from Grull Hawkwind

step
  .goto Mulgore,44.0,76.1
  .class Warrior
  .turnin 3091 >>Turn in Simple Note to Harutt Thunderhorn, by the chief's tent, and train
  .train Harutt Thunderhorn

step
  .goto Mulgore,44.3,75.7
  .class Hunter
  .turnin 3092 >>Turn in Etched Note to Lanka Farshot and train
  .train Lanka Farshot

step
  .goto Mulgore,45.0,75.9
  .class Shaman
  .turnin 3093 >>Turn in Rune-Inscribed Note to Meela Dawnstrider and train
  .train Meela Dawnstrider

step
  .goto Mulgore,45.1,75.9
  .class Druid
  .turnin 3094 >>Turn in Verdant Note to Gart Mistrunner and train
  .train Gart Mistrunner

-- South: cougars and Seer Graytongue --------------------------------------------------------------------

step
  .goto Mulgore,48.5,89.8
  .complete 750,1 >>Kill Mountain Cougars on the slopes south of the camp for 10 Mountain Cougar Pelts (lvl 3)

step
  .goto Mulgore,42.6,92.2
  .turnin 755 >>Turn in Rites of the Earthmother to Seer Graytongue, in the cave at the south end of the valley
  .accept 757 >>Accept Rite of Strength

step
  .goto Mulgore,44.9,77.1
  .turnin 750 >>Turn in The Hunt Continues to Grull Hawkwind
  .accept 780 >>Accept The Battleboars

step
  .goto Mulgore,44.5,76.5
  .xp 3
  .accept 3376 >>Accept Break Sharptusk! from Brave Windfeather, next to the chief's tent (level 3)

-- East: the Brambleblade Ravine ---------------------------------------------------------------------------

step
  .goto Mulgore,56.1,84.2
  .complete 780,1 >>Kill Battleboars south-east of the camp for Battleboar Snouts (lvl 3-4)
  .complete 780,2 >>...and Battleboar Flanks — the Bristleback Battleboars in the ravine drop them too (lvl 4-5)

step
  .goto Mulgore,61.6,78.8
  .complete 757,1 >>Kill Bristleback Quilboar and Shamans in the Brambleblade Ravine until a Bristleback Belt drops (lvl 3-4)

step
  .goto Mulgore,64.7,77.7
  .complete 3376,1 >>Kill Chief Sharptusk Thornmantle in the hut at the far end of the ravine (lvl 5) and take his head

step
  .goto Mulgore,44.9,77.1
  .turnin 780 >>Turn in The Battleboars to Grull Hawkwind

step
  .goto Mulgore,44.5,76.5
  .turnin 3376 >>Turn in Break Sharptusk! to Brave Windfeather

step
  .goto Mulgore,44.2,76.1
  .turnin 757 >>Turn in Rite of Strength to Chief Hawkwind
  .accept 763 >>Accept Rites of the Earthmother — a hand-off to Baine Bloodhoof in Bloodhoof Village

step
  .goto Mulgore,44.7,76.2
  .class Shaman
  .xp 4
  .accept 1519 >>Accept Call of Earth from Seer Ravenfeather (level 4 — the first shaman totem chain; kill a few more boars if you are not 4 yet)

step
  .goto Mulgore,63.7,76.2
  .class Shaman
  .complete 1519,1 >>Back in the Brambleblade Ravine: loot the Ritual Salve from a Bristleback Shaman (lvl 3-4)

step
  .goto Mulgore,44.7,76.2
  .class Shaman
  .turnin 1519 >>Turn in Call of Earth to Seer Ravenfeather
  .accept 1520 >>Accept Call of Earth (part 2)

step
  .goto Mulgore,53.9,80.5
  .class Shaman
  .turnin 1520 >>Turn in Call of Earth to the Minor Manifestation of Earth, east of the camp — kill it when it turns hostile
  .accept 1521 >>Accept Call of Earth (part 3)

step
  .goto Mulgore,44.7,76.2
  .class Shaman
  .turnin 1521 >>Turn in Call of Earth to Seer Ravenfeather for your Earth Totem

step
  .goto Mulgore,44.9,77.1
  .xp 5 >>You should be level 5 leaving Camp Narache; kill Battleboars and cougars if not, then take the path north out of the valley

step
  .goto Mulgore,38.5,81.6
  .accept 1656 >>Accept A Task Unfinished from Antur Fallow, on the path north-west of the camp — a letter for the Bloodhoof innkeeper

-- Bloodhoof Village: first visit --------------------------------------------------------------------------

step
  .goto Mulgore,47.5,60.2
  .turnin 763 >>Turn in Rites of the Earthmother to Baine Bloodhoof in Bloodhoof Village
  .accept 767 >>Accept Rite of Vision
  .accept 745 >>Accept Sharing the Land

step
  .goto Mulgore,48.5,60.4
  .accept 748 >>Accept Poison Water from Mull Thunderhorn, next to Baine

step
  .goto Mulgore,48.7,59.3
  .accept 761 >>Accept Swoop Hunting from Harken Windtotem

step
  .goto Mulgore,47.0,57.1
  .accept 766 >>Accept Mazzranache from Maur Raincaller, north end of the village

step
  .goto Mulgore,47.8,57.5
  .turnin 767 >>Turn in Rite of Vision to Zarlman Two-Moons
  .accept 771 >>Accept Rite of Vision (part 2)

step
  .goto Mulgore,47.4,62.0
  .accept 743 >>Accept Dangers of the Windfury from Ruul Eagletalon, south end of the village

step
  .goto Mulgore,51.9,59.6
  .accept 749 >>Accept The Ravaged Caravan from Morin Cloudstalker, on the road east of the village

step
  .goto Mulgore,46.6,61.1
  .turnin 1656 >>Turn in A Task Unfinished to Innkeeper Kauth
  .hs Bloodhoof Village >>Set your hearthstone at the Bloodhoof inn

step
  .goto Mulgore,49.3,56.2
  .complete 771,2 >>Pick up an Ambercorn from under the trees just north-east of the village (a small nut on the ground)

-- South-west loop: wolves, swoops, plainstriders, gnolls -------------------------------------------------

step
  .goto Mulgore,41.5,65.6
  .complete 748,1 >>Kill Prairie Wolves south-west of the village for 8 Prairie Wolf Paws (lvl 5-6)
  .complete 766,1 >>...and a Prairie Wolf Heart for Mazzranache

step
  .goto Mulgore,40.7,63.4
  .complete 761,1 >>Kill Wiry Swoops in the same fields for 6 Trophy Swoop Quills (lvl 5-7)
  .complete 766,4 >>...and a Swoop Gizzard

step
  .goto Mulgore,43.0,55.0
  .complete 748,2 >>Kill Adult Plainstriders north-west of the village for 8 Plainstrider Talons (lvl 6-7)
  .complete 766,3 >>...and a Plainstrider Scale

step
  .goto Mulgore,47.3,71.3
  .complete 745,1 >>Kill Palemane Tanners at the gnoll camps south of the village (lvl 5-6)
  .complete 745,2 >>Kill Palemane Skinners (lvl 6-7)

step
  .goto Mulgore,53.2,72.3
  .complete 745,3 >>Kill Palemane Poachers at the south-eastern gnoll camp (lvl 7-8)
  .complete 766,2 >>Flatland Cougars roam east of here (57,72) — loot a Flatland Cougar Femur while you are close (lvl 7-8)

-- Bloodhoof Village: second visit ---------------------------------------------------------------------------

step
  .goto Mulgore,48.5,60.4
  .turnin 748 >>Turn in Poison Water to Mull Thunderhorn
  .accept 754 >>Accept Winterhoof Cleansing

step
  .goto Mulgore,48.7,59.3
  .turnin 761 >>Turn in Swoop Hunting to Harken Windtotem

step
  .goto Mulgore,47.5,60.2
  .turnin 745 >>Turn in Sharing the Land to Baine Bloodhoof
  .xp 6
  .accept 746 >>Accept Dwarven Digging (level 6)

step
  .goto Mulgore,47.0,57.1
  .turnin 766 >>Turn in Mazzranache to Maur Raincaller (if the femur is still missing, hand it in on the next visit)

step
  .goto Mulgore,49.5,60.6
  .class Warrior
  .train Krang Stonehoof >>Train at Krang Stonehoof, the warrior trainer in the village

step
  .goto Mulgore,47.8,55.7
  .class Hunter
  .train Yaw Sharpmane >>Train at Yaw Sharpmane, the hunter trainer at the north end of the village

step
  .goto Mulgore,48.4,59.2
  .class Shaman
  .train Narm Skychaser >>Train at Narm Skychaser, the shaman trainer in the village

step
  .goto Mulgore,48.5,59.6
  .class Druid
  .train Gennia Runetotem >>Train at Gennia Runetotem, the druid trainer in the village

step
  .goto Mulgore,46.6,61.1
  .vendor >>Sell junk and buy food and water at the vendors around the inn

-- South-east loop: Winterhoof well, harpies -----------------------------------------------------------------

step
  .goto Mulgore,53.7,66.0
  .complete 754 >>Use the Winterhoof Cleansing Totem at the Winterhoof Water Well, south-east of the village

step
  .goto Mulgore,61.6,71.3
  .complete 743,1 >>Kill Windfury Harpies and Wind Witches on the cliffs in the south-east corner for 8 Windfury Talons (lvl 7-9)

step
  .goto Mulgore,48.5,60.4
  .turnin 754 >>Turn in Winterhoof Cleansing to Mull Thunderhorn (hearth if it is up)
  .accept 756 >>Accept Thunderhorn Totem

step
  .goto Mulgore,47.4,62.0
  .turnin 743 >>Turn in Dangers of the Windfury to Ruul Eagletalon

-- Northern loop: the caravan, the Thunderhorn well, the dwarven digsite ---------------------------------------

step
  .goto Mulgore,53.7,48.2
  .turnin 749 >>Open the Sealed Supply Crate at the ravaged caravan north-east of the village and turn in The Ravaged Caravan
  .accept 751 >>Accept The Ravaged Caravan (part 2) from the crate

step
  .goto Mulgore,49.3,47.1
  .complete 756,1 >>Kill Prairie Stalkers on the plain north of the village for Stalker Claws (lvl 7-8)

step
  .goto Mulgore,48.0,43.1
  .complete 756,2 >>Kill Flatland Cougars around the Thunderhorn Water Well for Cougar Claws (lvl 7-8)

step
  .goto Mulgore,44.4,45.0
  .complete 771,1 >>Pick up a Well Stone at the Thunderhorn Water Well, west of the cougars (a stone on the ground by the well)

step
  .goto Mulgore,32.3,49.2
  .complete 746,1 >>Kill Bael'dun Diggers and Appraisers at the dwarven digsite in the west for a Prospector's Pick (lvl 7-9)
  .complete 746,2 >>...and Broken Tools from the same dwarves

-- Bloodhoof Village: third visit -------------------------------------------------------------------------------

step
  .goto Mulgore,51.9,59.6
  .xp 8
  .turnin 751 >>Turn in The Ravaged Caravan to Morin Cloudstalker (hearth to Bloodhoof)
  .accept 764 >>Accept The Venture Co.
  .accept 765 >>Accept Supervisor Fizsprocket

step
  .goto Mulgore,48.5,60.4
  .turnin 756 >>Turn in Thunderhorn Totem to Mull Thunderhorn
  .accept 758 >>Accept Thunderhorn Cleansing

step
  .goto Mulgore,47.5,60.2
  .turnin 746 >>Turn in Dwarven Digging to Baine Bloodhoof

step
  .goto Mulgore,47.8,57.5
  .turnin 771 >>Turn in Rite of Vision to Zarlman Two-Moons
  .accept 772 >>Accept Rite of Vision (part 3) — a hand-off to Seer Wiserunner in the west

step
  .goto Mulgore,46.6,61.1
  .train >>Train at your class trainer, sell and repair before the long northern loop
  .vendor

-- North-east: the Thunderhorn well and the Venture Co. mine -------------------------------------------------------

step
  .goto Mulgore,44.4,45.0
  .complete 758 >>Use the Thunderhorn Cleansing Totem at the Thunderhorn Water Well

step
  .goto Mulgore,61.1,39.8
  .complete 764,1 >>Kill Venture Co. Workers at the mine in the north-east (lvl 8-9)
  .complete 764,2 >>Kill Venture Co. Supervisors there (lvl 9-10)

step
  .goto Mulgore,64.9,43.3
  .complete 765,1 >>Kill Supervisor Fizsprocket at the back of the mine (lvl 12 — pull him alone) and loot his clipboard

step
  .goto Mulgore,51.9,59.6
  .turnin 764 >>Turn in The Venture Co. to Morin Cloudstalker (hearth to Bloodhoof)
  .turnin 765 >>Turn in Supervisor Fizsprocket

step
  .goto Mulgore,48.5,60.4
  .turnin 758 >>Turn in Thunderhorn Cleansing to Mull Thunderhorn
  .accept 759 >>Accept Wildmane Totem

-- North: Prairie Wolf Alphas, Seer Wiserunner, the Wildmane well, Red Rocks ------------------------------------------

step
  .goto Mulgore,54.1,33.9
  .complete 759,1 >>Kill Prairie Wolf Alphas on the northern plains until a Prairie Alpha Tooth drops (lvl 9-10)

step
  .goto Mulgore,48.5,60.4
  .turnin 759 >>Turn in Wildmane Totem to Mull Thunderhorn (hearth to Bloodhoof)
  .accept 760 >>Accept Wildmane Cleansing

step
  .goto Mulgore,32.7,36.1
  .turnin 772 >>Turn in Rite of Vision to Seer Wiserunner in the cave in the western hills
  .accept 773 >>Accept Rite of Wisdom — the Ancestral Spirit at Red Rocks, far north-east

step
  .goto Mulgore,42.8,14.0
  .complete 760 >>Use the Wildmane Cleansing Totem at the Wildmane Water Well in the far north (Windfury harpies around it, lvl 9-11)

step
  .goto Mulgore,59.9,25.6
  .accept 833 >>Accept A Sacred Burial from Lorekeeper Raintotem at Red Rocks

step
  .goto Mulgore,61.0,21.3
  .complete 833,1 >>Kill 10 Bristleback Interlopers among the Red Rocks (lvl 9-10)

step
  .goto Mulgore,61.5,21.0
  .turnin 773 >>Turn in Rite of Wisdom to the Ancestral Spirit at the top of Red Rocks
  .accept 775 >>Accept Journey into Thunder Bluff

step
  .goto Mulgore,59.9,25.6
  .turnin 833 >>Turn in A Sacred Burial to Lorekeeper Raintotem

-- Bloodhoof Village: last visit (level 10) ------------------------------------------------------------------------------

step
  .goto Mulgore,48.5,60.4
  .turnin 760 >>Turn in Wildmane Cleansing to Mull Thunderhorn (hearth to Bloodhoof)

step
  .goto Mulgore,46.8,60.2
  .xp 10
  .accept 861 >>Accept The Hunter's Way from Skorn Whitecloud (level 10) — turned in to Melor Stonehoof in Thunder Bluff

step
  .goto Mulgore,49.5,60.6
  .class Warrior
  .accept 1505 >>Accept Veteran Uzzek from Krang Stonehoof (level 10) — turned in at Far Watch Post in the Barrens

step
  .goto Mulgore,48.4,59.2
  .class Shaman
  .accept 2984 >>Accept Call of Fire from Narm Skychaser (level 10) — the fire totem chain, turned in at Far Watch Post in the Barrens

step
  .goto Mulgore,48.5,59.6
  .class Druid
  .accept 5928 >>Accept Heeding the Call from Gennia Runetotem (level 10) — a hand-off to Turak Runetotem in Thunder Bluff

step
  .goto Mulgore,46.6,61.1
  .train >>Train at your class trainer, sell and repair before Thunder Bluff
  .vendor

step
  .goto Mulgore,56.3,34.4
  .complete 861,1 >>Kill Flatland Prowlers on the plains north-east of the village, on the way to Thunder Bluff, for 2 Flatland Prowler Claws (lvl 9)

-- Thunder Bluff ------------------------------------------------------------------------------------------------------

step
  .goto Thunder Bluff,60.3,51.7
  .turnin 775 >>Turn in Journey into Thunder Bluff to Cairne Bloodhoof on the high rise of Thunder Bluff (take the north lift up from the road)

step
  .goto Thunder Bluff,60.3,51.7
  .optional >>Rites of the Earthmother: Arra'chea (lvl 11) wanders the northern plains — a detour before the Barrens
  .accept 776 >>Accept Rites of the Earthmother from Cairne Bloodhoof

step
  .goto Thunder Bluff,61.5,80.9
  .turnin 861 >>Turn in The Hunter's Way to Melor Stonehoof on the Hunter Rise
  .accept 860 >>Accept Sergra Darkthorn — a hand-off in the Crossroads

step
  .goto Thunder Bluff,78.6,28.6
  .accept 886 >>Accept The Barrens Oases from Arch Druid Hamuul Runetotem on the Elder Rise — turned in at the Crossroads

step
  .goto Thunder Bluff,47.0,49.8
  .text >>Talk to Tal, the wind rider master on the central rise, to learn the Thunder Bluff flight path

step
  .goto Thunder Bluff,45.8,64.7
  .train >>Train at your class trainer in Thunder Bluff (Hunter Rise for warriors and hunters, Spirit Rise for shamans, Elder Rise for druids), then sell and repair at the inn on the central rise

step
  .goto Thunder Bluff,37.7,59.6
  .optional >>Preparation for Ceremony: the Windfury Sorceresses live in the far north-west of Mulgore; a long walk for one turn-in
  .accept 744 >>Accept Preparation for Ceremony from Eyahn Eagletalon on the central rise

step
  .goto Thunder Bluff,76.5,27.2
  .class Druid
  .turnin 5928 >>Turn in Heeding the Call to Turak Runetotem on the Elder Rise — he offers Moonglade next (Teleport: Moonglade and the bear form chain); take it now or come back at 12

-- Hunter pet quests (level 10) -------------------------------------------------------------------------------------------

step
  .goto Thunder Bluff,58.5,88.3
  .class Hunter
  .accept 6065 >>Accept The Hunter's Path from Kary Thunderhorn on the Hunter Rise — it sends you back to Yaw Sharpmane

step
  .goto Mulgore,47.8,55.7
  .class Hunter
  .turnin 6065 >>Turn in The Hunter's Path to Yaw Sharpmane in Bloodhoof Village
  .accept 6061 >>Accept Taming the Beast (Adult Plainstrider)

step
  .goto Mulgore,43.0,55.0
  .class Hunter
  .complete 6061 >>Use the Taming Rod on an Adult Plainstrider north-west of the village (lvl 6-7) and keep it alive until the channel ends

step
  .goto Mulgore,47.8,55.7
  .class Hunter
  .turnin 6061 >>Turn in Taming the Beast to Yaw Sharpmane
  .accept 6087 >>Accept Taming the Beast (Prairie Stalker)

step
  .goto Mulgore,49.3,47.1
  .class Hunter
  .complete 6087 >>Use the Taming Rod on a Prairie Stalker on the plain north of the village (lvl 7-8)

step
  .goto Mulgore,47.8,55.7
  .class Hunter
  .turnin 6087 >>Turn in Taming the Beast to Yaw Sharpmane
  .accept 6088 >>Accept Taming the Beast (Swoop)

step
  .goto Mulgore,49.8,44.4
  .class Hunter
  .complete 6088 >>Use the Taming Rod on a Swoop north of the village (lvl 7-9)

step
  .goto Mulgore,47.8,55.7
  .class Hunter
  .turnin 6088 >>Turn in Taming the Beast to Yaw Sharpmane
  .accept 6089 >>Accept Training the Beast — Holt Thunderhorn in Thunder Bluff

step
  .goto Thunder Bluff,57.3,89.8
  .class Hunter
  .turnin 6089 >>Turn in Training the Beast to Holt Thunderhorn on the Hunter Rise

-- Optional detours before the Barrens ---------------------------------------------------------------------------------------

step
  .goto Mulgore,35.0,13.7
  .optional >>Preparation for Ceremony
  .complete 744,1 >>Kill Windfury Sorceresses and Matriarchs in the far north-west for 6 Azure Feathers (lvl 9-11)
  .complete 744,2 >>...and 6 Bronze Feathers

step
  .goto Thunder Bluff,37.7,59.6
  .optional >>Preparation for Ceremony
  .turnin 744 >>Turn in Preparation for Ceremony to Eyahn Eagletalon in Thunder Bluff

step
  .goto Mulgore,53.0,14.0
  .optional >>Rites of the Earthmother
  .complete 776,1 >>Find and kill Arra'chea, the great kodo that wanders the northern plains around 53,14 (lvl 11), and take his horn

step
  .goto Thunder Bluff,60.3,51.7
  .optional >>Rites of the Earthmother
  .turnin 776 >>Turn in Rites of the Earthmother to Cairne Bloodhoof

step
  .goto Mulgore,48.5,60.4
  .xp 11 >>Mulgore's quests run out around level 11; the Barrens quests start at 10, so head out now (Prairie Wolf Alphas and Flatland Prowlers on the northern plains if you are short). Walk back down to Bloodhoof Village and take the road east through the pass

step
  .zone The Barrens >>Follow the road east out of Bloodhoof Village through the mountain pass into the Barrens (Camp Taurajo is just past it; the Crossroads lie north along the main road)
]], "Lodestar_Guides_Horde")

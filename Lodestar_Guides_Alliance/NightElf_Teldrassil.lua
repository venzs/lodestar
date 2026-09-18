-- Lodestar Guides: Alliance — Night Elf starting zone, Teldrassil (levels 1-12).
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Teldrassil route (Shadowglen → Dolanaar and Starbreeze
-- Village → Fel Rock, Ban'ethil Barrow Den, the Pools of Arlithrien and Lake Al'Ameth → a first look at
-- Darnassus → the Oracle Glade and Wellspring → Dolanaar → Darnassus → Rut'theran Village and the
-- flight to Auberdine). The four Crown of the Earth moonwells are not in the data; their positions
-- are the ones the quest texts describe. Every other quest id and position comes from the data; the
-- order still has to be verified in play (/lode record). Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance/Night Elf 1-12: Teldrassil
#faction Alliance
#race Night Elf,NightElf
#levels 1-12
#next Alliance 12-20: Darkshore
#author Lodestar
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Shadowglen ------------------------------------------------------------------------------------

step
  .goto Teldrassil,59.9,42.5
  .accept 458 >>Accept The Woodland Protector from Melithar Staghelm (right where you spawn)

step
  .goto Teldrassil,58.7,44.3
  .accept 456 >>Accept The Balance of Nature from Conservator Ilthalaine, below the tree

step
  .goto Teldrassil,57.8,45.2
  .turnin 458 >>Turn in The Woodland Protector to Tarindrella, the dryad west of Ilthalaine
  .accept 459 >>Accept The Woodland Protector (part 2)

step
  .goto Teldrassil,59.1,43.3
  .complete 456,1 >>Kill 7 Young Thistle Boars around Shadowglen (lvl 1-2)
  .complete 456,2 >>Kill 4 Young Nightsabers there too (lvl 1)

step
  .goto Teldrassil,56.3,45.7
  .complete 459,1 >>Loot 8 Fel Moss from the Grells and Grellkin west of Tarindrella (lvl 2-4)

step
  .goto Teldrassil,57.8,45.2
  .turnin 459 >>Turn in The Woodland Protector to Tarindrella

step
  .goto Teldrassil,58.7,44.3
  .turnin 456 >>Turn in The Balance of Nature to Conservator Ilthalaine
  .accept 457 >>Accept The Balance of Nature (part 2)

-- Class sigils (Ilthalaine hands them out after The Balance of Nature) ---------------------------

step
  .goto Teldrassil,58.7,44.3
  .class Warrior
  .accept 3116 >>Accept Simple Sigil (warrior) from Conservator Ilthalaine

step
  .goto Teldrassil,58.7,44.3
  .class Hunter
  .accept 3117 >>Accept Etched Sigil (hunter) from Conservator Ilthalaine

step
  .goto Teldrassil,58.7,44.3
  .class Rogue
  .accept 3118 >>Accept Encrypted Sigil (rogue) from Conservator Ilthalaine

step
  .goto Teldrassil,58.7,44.3
  .class Priest
  .accept 3119 >>Accept Hallowed Sigil (priest) from Conservator Ilthalaine

step
  .goto Teldrassil,58.7,44.3
  .class Druid
  .accept 3120 >>Accept Verdant Sigil (druid) from Conservator Ilthalaine

step
  .goto Teldrassil,60.9,42.0
  .xp 2
  .accept 4495 >>Accept A Good Friend from Dirania Silvershine, by the path east of the tree (level 2 — the boars get you there)

step
  .goto Teldrassil,57.8,41.7
  .xp 3
  .accept 916 >>Accept Webwood Venom from Gilshalan Windwalker, inside the tree (level 3)

-- Class trainers in Aldrassil -------------------------------------------------------------------

step
  .goto Teldrassil,59.6,38.4
  .class Warrior
  .turnin 3116 >>Turn in Simple Sigil to Alyissia, on the north side of the tree, and train
  .train Alyissia

step
  .goto Teldrassil,58.7,40.4
  .class Hunter
  .turnin 3117 >>Turn in Etched Sigil to Ayanna Everstride, on the north side of the tree, and train
  .train Ayanna Everstride

step
  .goto Teldrassil,59.6,38.7
  .class Rogue
  .turnin 3118 >>Turn in Encrypted Sigil to Frahun Shadewhisper, on the north side of the tree, and train
  .train Frahun Shadewhisper

step
  .goto Teldrassil,59.2,40.4
  .class Priest
  .turnin 3119 >>Turn in Hallowed Sigil to Shanda, on the north side of the tree, and train
  .train Shanda

step
  .goto Teldrassil,58.6,40.3
  .class Druid
  .turnin 3120 >>Turn in Verdant Sigil to Mardant Strongoak, on the north side of the tree, and train
  .train Mardant Strongoak

-- North: Iverron and the Webwood spiders -------------------------------------------------------------

step
  .goto Teldrassil,59.5,36.8
  .complete 457,1 >>Kill 7 Thistle Boars north of Shadowglen (lvl 2-3)
  .complete 457,2 >>Kill 7 Mangy Nightsabers there too (lvl 2)

step
  .goto Teldrassil,54.6,33.0
  .turnin 4495 >>Turn in A Good Friend to Iverron, lying on the hill north-west of Shadowglen
  .accept 3519 >>Accept A Friend in Need

step
  .goto Teldrassil,56.9,28.4
  .complete 916,1 >>Loot 10 Webwood Venom Sacs from Webwood Spiders outside Shadowthread Cave, north of Iverron (lvl 3-4)

step
  .goto Teldrassil,58.7,44.3
  .turnin 457 >>Turn in The Balance of Nature to Conservator Ilthalaine

step
  .goto Teldrassil,60.9,42.0
  .turnin 3519 >>Turn in A Friend in Need to Dirania Silvershine
  .accept 3521 >>Accept Iverron's Antidote

step
  .goto Teldrassil,57.8,41.7
  .turnin 916 >>Turn in Webwood Venom to Gilshalan Windwalker
  .accept 917 >>Accept Webwood Egg

step
  .goto Teldrassil,58.6,41.5
  .complete 3521,1 >>Pick 7 Hyacinth Mushrooms — the purple mushrooms around Shadowglen and along the path north

step
  .goto Teldrassil,57.7,37.5
  .complete 3521,3 >>Pick 4 Moonpetal Lilies — the white flowers on the slope north of the tree

step
  .goto Teldrassil,56.9,28.4
  .complete 3521,2 >>Loot 2 Webwood Ichor from Webwood Spiders outside Shadowthread Cave (lvl 3-4)

step
  .goto Teldrassil,56.8,26.5
  .complete 917,1 >>Take a Webwood Egg from the Webwood Eggs at the back of Shadowthread Cave (lvl 3-4 spiders inside)

step
  .goto Teldrassil,57.8,41.7
  .turnin 917 >>Turn in Webwood Egg to Gilshalan Windwalker
  .accept 920 >>Accept Tenaron's Summons

step
  .goto Teldrassil,60.9,42.0
  .turnin 3521 >>Turn in Iverron's Antidote to Dirania Silvershine
  .accept 3522 >>Accept Iverron's Antidote (part 2)

step
  .goto Teldrassil,59.1,39.4
  .turnin 920 >>Turn in Tenaron's Summons to Tenaron Stormgrip at the top of the tree (take the ramp up)
  .accept 921 >>Accept Crown of the Earth

step
  .goto Teldrassil,60.0,33.0
  .complete 921 >>Stand in the moonwell north of Aldrassil and use the Crystal Phial to fill it

step
  .goto Teldrassil,54.6,33.0
  .turnin 3522 >>Turn in Iverron's Antidote to Iverron on the hill north-west

step
  .goto Teldrassil,59.1,39.4
  .turnin 921 >>Turn in Crown of the Earth to Tenaron Stormgrip at the top of the tree
  .accept 928 >>Accept Crown of the Earth (part 2) — for Corithras Moonrage in Dolanaar

step
  .goto Teldrassil,59.2,40.4
  .class Priest
  .xp 5
  .accept 5622 >>Accept In Favor of Elune from Shanda (level 5) — a hand-off to Laurna Morninglight in Dolanaar

step
  .goto Teldrassil,58.7,44.3
  .xp 5 >>You should be level 5 leaving Shadowglen; kill boars or nightsabers if not, then take the path south-east out of the glen

step
  .goto Teldrassil,61.2,47.6
  .accept 2159 >>Accept Dolanaar Delivery from Porthannius, on the path out of Shadowglen

-- Dolanaar: first visit ------------------------------------------------------------------------------------

step
  .goto Teldrassil,55.6,59.8
  .turnin 2159 >>Turn in Dolanaar Delivery to Innkeeper Keldamyr in Dolanaar
  .hs Dolanaar >>Set your hearthstone at the Dolanaar inn

step
  .goto Teldrassil,56.1,61.7
  .turnin 928 >>Turn in Crown of the Earth to Corithras Moonrage, south of the inn
  .accept 929 >>Accept Crown of the Earth (part 3) — the Jade Phial, for the moonwell at Starbreeze Village

step
  .goto Teldrassil,56.0,57.3
  .accept 475 >>Accept A Troubling Breeze from Athridas Bearmantle, in the big building north of the inn

step
  .goto Teldrassil,55.6,56.9
  .accept 2438 >>Accept The Emerald Dreamcatcher from Tallonkai Swiftroot, upstairs
  .accept 932 >>Accept Twisted Hatred

step
  .goto Teldrassil,56.1,57.7
  .accept 997 >>Accept Denalan's Earth from Syral Bladeleaf, outside — for Denalan at Lake Al'Ameth

step
  .goto Teldrassil,55.9,58.8
  .accept 487 >>Accept The Road to Darnassus from Moon Priestess Amara, by the road

step
  .goto Teldrassil,55.6,56.7
  .class Priest
  .turnin 5622 >>Turn in In Favor of Elune to Laurna Morninglight, the priest trainer in the big building
  .accept 5621 >>Accept Garments of the Moon

step
  .goto Teldrassil,57.2,63.5
  .class Priest
  .complete 5621,1 >>Cast Lesser Heal and Power Word: Fortitude on Sentinel Shaya, south-east of Dolanaar (friendly — just buff and heal her)

step
  .goto Teldrassil,55.6,56.7
  .class Priest
  .turnin 5621 >>Turn in Garments of the Moon to Laurna Morninglight

step
  .goto Teldrassil,56.2,59.2
  .class Warrior
  .train Kyra Windblade >>Train at Kyra Windblade, the warrior trainer by the road

step
  .goto Teldrassil,56.7,59.5
  .class Hunter
  .train Dazalar >>Train at Dazalar, the hunter trainer south of the inn

step
  .goto Teldrassil,56.4,60.1
  .class Rogue
  .train Jannok Breezesong >>Train at Jannok Breezesong, the rogue trainer south of the inn

step
  .goto Teldrassil,55.6,56.7
  .class Priest
  .train Laurna Morninglight >>Train at Laurna Morninglight in the big building

step
  .goto Teldrassil,55.9,61.6
  .class Druid
  .train Kal >>Train at Kal, the druid trainer south of the inn

-- East loop: Zenn's beasts, the Starbreeze moonwell, Starbreeze Village --------------------------------------

step
  .goto Teldrassil,60.4,56.1
  .accept 488 >>Accept Zenn's Bidding from Zenn Foulhoof, the satyr east of Dolanaar

step
  .goto Teldrassil,58.8,58.4
  .complete 488,1 >>Loot 3 Nightsaber Fangs from Nightsabers around Dolanaar (lvl 5-6)
  .complete 488,2 >>Loot 3 Strigid Owl Feathers from Strigid Owls (lvl 5-6)
  .complete 488,3 >>Loot 3 Webwood Spider Silk from Webwood Lurkers (lvl 5-6)

step
  .goto Teldrassil,63.0,58.0
  .complete 929 >>Stand in the moonwell outside Starbreeze Village, east of Dolanaar, and use the Jade Phial to fill it

step
  .goto Teldrassil,66.3,58.5
  .turnin 475 >>Turn in A Troubling Breeze to Gaerolas Talvethren, hiding in a house in Starbreeze Village (Gnarlpine furbolgs, lvl 5-7)
  .accept 476 >>Accept Gnarlpine Corruption

step
  .goto Teldrassil,68.0,59.7
  .complete 2438,1 >>Take the Emerald Dreamcatcher from Tallonkai's Dresser in the house at the east end of the village

step
  .goto Teldrassil,60.4,56.1
  .turnin 488 >>Turn in Zenn's Bidding to Zenn Foulhoof

step
  .goto Teldrassil,56.0,57.3
  .turnin 476 >>Turn in Gnarlpine Corruption to Athridas Bearmantle in Dolanaar
  .accept 483 >>Accept The Relics of Wakening

step
  .goto Teldrassil,55.6,56.9
  .turnin 2438 >>Turn in The Emerald Dreamcatcher to Tallonkai Swiftroot
  .accept 2459 >>Accept Ferocitas the Dream Eater

step
  .goto Teldrassil,56.1,61.7
  .turnin 929 >>Turn in Crown of the Earth to Corithras Moonrage
  .accept 933 >>Accept Crown of the Earth (part 4) — the Tourmaline Phial, for the moonwell at the Pools of Arlithrien

step
  .goto Teldrassil,56.1,57.7
  .accept 489 >>Accept Seek Redemption! from Syral Bladeleaf

-- Loop 2: Ferocitas, Fel Rock, Ban'ethil, the Pools of Arlithrien, Lake Al'Ameth ------------------------------------

step
  .goto Teldrassil,68.7,52.8
  .complete 2459,1 >>Kill 7 Gnarlpine Mystics at the furbolg camp north of Starbreeze Village (lvl 6-7)
  .complete 2459,2 >>Kill Ferocitas the Dream Eater there (lvl 8) and take the Gnarlpine Necklace

step
  .goto Teldrassil,68.7,52.8
  .complete 2459,3 >>Use the Gnarlpine Necklace to get Tallonkai's Jewel out of it

step
  .goto Teldrassil,51.3,50.2
  .complete 932,1 >>Kill Lord Melenas in Fel Rock, the cave north-west of Dolanaar (lvl 8 — he stealths; clear the Fel Rock satyrs and sprites first, lvl 5-7) and take his head

step
  .goto Teldrassil,46.5,53.4
  .complete 487,1 >>Kill 6 Gnarlpine Ambushers along the road west of Dolanaar (lvl 6-7)

step
  .goto Teldrassil,44.9,61.6
  .accept 2541 >>Accept The Sleeping Druid from Oben Rageclaw, the sleeping druid in Ban'ethil Barrow Den (the furbolg den west of Dolanaar; go in at the top and follow the ramps down)

step
  .goto Teldrassil,44.3,61.7
  .complete 2541,1 >>Loot a Shaman Voodoo Charm from the Gnarlpine Shamans in the den (lvl 7-8, 15% drop — the totems and the other furbolgs in the den count toward Relics of Wakening's chests)

step
  .goto Teldrassil,45.7,57.4
  .complete 483,1 >>Open the Chest of the Raven Claw in the upper part of the den
  .complete 483,2 >>Open the Chest of the Black Feather
  .complete 483,3 >>Open the Chest of the Sky
  .complete 483,4 >>Open the Chest of Nesting — the four chests are on the different levels of the den (43-46, 57-62)

step
  .goto Teldrassil,44.9,61.6
  .turnin 2541 >>Turn in The Sleeping Druid to Oben Rageclaw
  .accept 2561 >>Accept Druid of the Claw

step
  .goto Teldrassil,44.9,61.6
  .complete 2561 >>Use the Voodoo Charm on Oben Rageclaw's body and kill the Rageclaw bear it wakes (lvl 8)

step
  .goto Teldrassil,44.9,61.6
  .turnin 2561 >>Turn in Druid of the Claw to Oben Rageclaw

step
  .goto Teldrassil,42.0,67.0
  .complete 933 >>Stand in the moonwell on the shore of the Pools of Arlithrien, south of the den, and use the Tourmaline Phial to fill it

step
  .goto Teldrassil,42.6,76.2
  .accept 930 >>Take the fruit from the Strange Fruited Plant at the south-west corner of Lake Al'Ameth and accept The Glowing Fruit

step
  .goto Teldrassil,54.0,65.3
  .complete 489,1 >>Pick up 5 Fel Cones — pine cones lying under the trees around the north shore of Lake Al'Ameth and the woods around Dolanaar

step
  .goto Teldrassil,60.9,68.5
  .turnin 997 >>Turn in Denalan's Earth to Denalan at his camp on the east shore of Lake Al'Ameth
  .turnin 930 >>Turn in The Glowing Fruit
  .accept 918 >>Accept Timberling Seeds
  .accept 919 >>Accept Timberling Sprouts

step
  .goto Teldrassil,60.8,67.8
  .complete 918,1 >>Loot 5 Timberling Seeds from Timberlings around the lake shore (lvl 5-6; the Bark Rippers to the west are lvl 7-8)
  .complete 919,1 >>Pick 6 Timberling Sprouts — the small plants along the shore

step
  .goto Teldrassil,60.9,68.5
  .turnin 918 >>Turn in Timberling Seeds to Denalan
  .turnin 919 >>Turn in Timberling Sprouts
  .accept 922 >>Accept Rellian Greenspyre — a hand-off to Darnassus

-- Dolanaar: second visit -------------------------------------------------------------------------------------------

step
  .goto Teldrassil,60.4,56.1
  .turnin 489 >>Turn in Seek Redemption! to Zenn Foulhoof

step
  .goto Teldrassil,55.6,56.9
  .turnin 2459 >>Turn in Ferocitas the Dream Eater to Tallonkai Swiftroot in Dolanaar
  .turnin 932 >>Turn in Twisted Hatred

step
  .goto Teldrassil,56.0,57.3
  .turnin 483 >>Turn in The Relics of Wakening to Athridas Bearmantle

step
  .goto Teldrassil,56.0,57.3
  .optional >>Ursal the Mauler is an elite (lvl 12) at Gnarlpine Hold in the south-west — a group quest, or come back at 12
  .accept 486 >>Accept Ursal the Mauler from Athridas Bearmantle

step
  .goto Teldrassil,55.9,58.8
  .turnin 487 >>Turn in The Road to Darnassus to Moon Priestess Amara

step
  .goto Teldrassil,56.1,61.7
  .turnin 933 >>Turn in Crown of the Earth to Corithras Moonrage
  .accept 7383 >>Accept Crown of the Earth (part 5) — the Amethyst Phial, for the moonwell in the Oracle Glade

step
  .goto Teldrassil,57.1,61.3
  .optional >>Recipe of the Kaldorei: a cooking recipe; the Small Spider Legs drop from Webwood Silkspinners near the Oracle Glade
  .accept 4161 >>Accept Recipe of the Kaldorei from Zarrin, the cook south of the inn

step
  .goto Teldrassil,55.6,59.8
  .xp 8
  .train >>Train new skills at your class trainer in Dolanaar, sell and repair, then take the road west toward Darnassus

-- Darnassus: first visit -----------------------------------------------------------------------------------------------

step
  .goto Darnassus,38.2,21.6
  .turnin 922 >>Turn in Rellian Greenspyre to Rellian Greenspyre in the Cenarion Enclave, Darnassus (through the portal at the west end of the road)
  .accept 923 >>Accept Tumors

step
  .goto Darnassus,28.9,45.8
  .accept 2519 >>Accept The Temple of the Moon from Sister Aquinne, by the water south of the enclave

step
  .goto Darnassus,36.7,85.9
  .turnin 2519 >>Turn in The Temple of the Moon to Priestess A'moora in the Temple of the Moon

step
  .goto Darnassus,36.7,85.9
  .optional >>Tears of the Moon: Lady Sathrah (lvl 12) lives in the far north of Teldrassil — worth it at 11-12, a long walk before
  .accept 2518 >>Accept Tears of the Moon from Priestess A'moora

step
  .goto Darnassus,67.4,15.6
  .vendor >>Sell junk and buy food and water in the Tradesmen's Terrace; the auction house and bank are here too

-- North loop: the Oracle Glade, Wellspring, Mist ---------------------------------------------------------------------------

step
  .goto Teldrassil,38.3,34.4
  .accept 937 >>Accept The Enchanted Glade from Sentinel Arynia Cloudsbreak in the Oracle Glade, north of Darnassus

step
  .goto Teldrassil,38.0,34.0
  .complete 7383 >>Stand in the moonwell by the Oracle Tree and use the Amethyst Phial to fill it

step
  .goto Teldrassil,36.0,38.9
  .complete 937,1 >>Loot 6 Bloodfeather Belts from the Bloodfeather harpies around the Oracle Glade (lvl 8-10)

step
  .goto Teldrassil,43.9,42.7
  .complete 923,1 >>Loot 6 Mossy Tumors from Timberling Tramplers and Mire Beasts along the Wellspring River, east of the glade (lvl 8-10)

step
  .goto Teldrassil,45.1,35.1
  .optional >>Recipe of the Kaldorei
  .complete 4161,1 >>Loot 7 Small Spider Legs from Webwood Silkspinners along the river (lvl 8-9)

step
  .goto Teldrassil,34.6,28.8
  .accept 931 >>Take the frond from the Strange Fronded Plant north-west of the glade and accept The Shimmering Frond (Bloodfeather Furies, lvl 9-10)

step
  .goto Teldrassil,31.5,31.6
  .xp 7
  .accept 938 >>Accept Mist from Mist, the nightsaber cub in the north-west corner — she follows you back to Sentinel Arynia

step
  .goto Teldrassil,38.3,34.4
  .turnin 938 >>Turn in Mist to Sentinel Arynia Cloudsbreak
  .turnin 937 >>Turn in The Enchanted Glade
  .accept 940 >>Accept Teldrassil — for Arch Druid Fandral Staghelm in Darnassus

step
  .goto Teldrassil,47.5,26.0
  .optional >>Tears of the Moon
  .complete 2518,1 >>Kill Lady Sathrah in the spider glade north-east of the Oracle Glade (lvl 12) and take her Silvery Spinnerets

-- Dolanaar: third visit, then Lake Al'Ameth again -------------------------------------------------------------------------

step
  .goto Teldrassil,56.1,61.7
  .turnin 7383 >>Turn in Crown of the Earth to Corithras Moonrage in Dolanaar (hearth to Dolanaar)
  .accept 935 >>Accept Crown of the Earth (part 6) — for Arch Druid Fandral Staghelm in Darnassus

step
  .goto Teldrassil,56.2,59.2
  .class Warrior
  .xp 10
  .accept 1684 >>Accept Elanaria from Kyra Windblade (level 10) — a hand-off to Elanaria in Darnassus

step
  .goto Teldrassil,56.4,60.1
  .class Rogue
  .xp 10
  .accept 2241 >>Accept The Apple Falls from Jannok Breezesong (level 10) — a hand-off to Syurna in Darnassus

step
  .goto Teldrassil,55.9,61.6
  .class Druid
  .xp 10
  .accept 5925 >>Accept Heeding the Call from Kal (level 10) — a hand-off to Mathrengyl Bearwalker in Darnassus

step
  .goto Teldrassil,55.6,56.7
  .class Priest
  .xp 10
  .accept 5629 >>Accept Returning Home from Laurna Morninglight (level 10) — a hand-off to Priestess Alathea in Darnassus

step
  .goto Teldrassil,57.1,61.3
  .optional >>Recipe of the Kaldorei
  .turnin 4161 >>Turn in Recipe of the Kaldorei to Zarrin

step
  .goto Teldrassil,60.9,68.5
  .turnin 931 >>Turn in The Shimmering Frond to Denalan at Lake Al'Ameth

step
  .goto Teldrassil,38.8,79.8
  .optional >>Ursal the Mauler
  .complete 486,1 >>Kill Ursal the Mauler at Gnarlpine Hold, the furbolg camp in the south-west corner of Teldrassil (lvl 12 elite)

step
  .goto Teldrassil,56.0,57.3
  .optional >>Ursal the Mauler
  .turnin 486 >>Turn in Ursal the Mauler to Athridas Bearmantle in Dolanaar

step
  .goto Teldrassil,55.6,59.8
  .xp 10 >>You should be level 10 by now; the Gnarlpine furbolgs in Ban'ethil Barrow Den are good XP if you are short. Train, sell and repair, then take the road west to Darnassus

-- Darnassus: second visit -----------------------------------------------------------------------------------------------------

step
  .goto Darnassus,34.8,9.3
  .turnin 935 >>Turn in Crown of the Earth to Arch Druid Fandral Staghelm in the Cenarion Enclave
  .turnin 940 >>Turn in Teldrassil
  .accept 952 >>Accept Grove of the Ancients — for Onu in Darkshore

step
  .goto Darnassus,38.2,21.6
  .turnin 923 >>Turn in Tumors to Rellian Greenspyre

step
  .goto Darnassus,38.2,21.6
  .optional >>Return to Denalan: Oakenscowl (lvl 9) waits south of Lake Al'Ameth — good XP if you are heading back to Dolanaar for a class quest anyway
  .accept 2498 >>Accept Return to Denalan from Rellian Greenspyre

step
  .goto Darnassus,36.7,85.9
  .optional >>Tears of the Moon
  .turnin 2518 >>Turn in Tears of the Moon to Priestess A'moora in the Temple of the Moon
  .accept 2520 >>Accept Sathrah's Sacrifice

step
  .goto Darnassus,36.7,85.9
  .optional >>Tears of the Moon
  .complete 2520 >>Use the Silvery Spinnerets at the fountain in the temple, then speak with Priestess A'moora again

step
  .goto Darnassus,36.7,85.9
  .optional >>Tears of the Moon
  .turnin 2520 >>Turn in Sathrah's Sacrifice to Priestess A'moora

-- Class quests in Darnassus (level 10) ---------------------------------------------------------------------------------------------

step
  .goto Darnassus,57.3,34.6
  .class Warrior
  .turnin 1684 >>Turn in Elanaria to Elanaria in the Warrior's Terrace
  .accept 1683 >>Accept Vorlus Vilehoof — he lives by the Pools of Arlithrien, back east

step
  .goto Darnassus,58.7,34.9
  .class Warrior
  .train Arias'ta Bladesinger >>Train at Arias'ta Bladesinger in the Warrior's Terrace

step
  .goto Darnassus,37.0,21.9
  .class Rogue
  .turnin 2241 >>Turn in The Apple Falls to Syurna in the Cenarion Enclave
  .optional >>Destiny Calls: Sethir the Ancient (lvl 12) sits in the far north of Teldrassil — a long walk for the journal
  .accept 2242 >>Accept Destiny Calls from Syurna

step
  .goto Darnassus,34.5,25.9
  .class Rogue
  .train Erion Shadewhisper >>Train at Erion Shadewhisper in the Cenarion Enclave

step
  .goto Darnassus,39.5,81.2
  .class Priest
  .turnin 5629 >>Turn in Returning Home to Priestess Alathea in the Temple of the Moon
  .accept 5627 >>Accept Stars of Elune

step
  .goto Darnassus,39.5,81.2
  .class Priest
  .turnin 5627 >>Turn in Stars of Elune to Priestess Alathea for Elune's Grace

step
  .goto Darnassus,38.3,81.0
  .class Priest
  .train Astarii Starseeker >>Train at Astarii Starseeker in the Temple of the Moon

step
  .goto Darnassus,35.4,8.4
  .class Druid
  .turnin 5925 >>Turn in Heeding the Call to Mathrengyl Bearwalker in the Cenarion Enclave
  .accept 5921 >>Accept Moonglade — learn Teleport: Moonglade from him and use it

step
  .goto Darnassus,34.8,7.4
  .class Druid
  .train Denatharion >>Train at Denatharion in the Cenarion Enclave (Teleport: Moonglade)

step
  .goto Moonglade,56.2,30.6
  .class Druid
  .turnin 5921 >>Teleport to Moonglade and turn in Moonglade to Dendrite Starblaze in Nighthaven
  .accept 5929 >>Accept Great Bear Spirit

step
  .goto Moonglade,39.1,27.5
  .class Druid
  .complete 5929 >>Speak with the Great Bear Spirit in the woods west of Nighthaven and listen to what it has to say

step
  .goto Moonglade,56.2,30.6
  .class Druid
  .turnin 5929 >>Turn in Great Bear Spirit to Dendrite Starblaze
  .accept 5931 >>Accept Back to Darnassus — the Nighthaven flight master flies druids back to Rut'theran Village

step
  .goto Darnassus,35.4,8.4
  .class Druid
  .turnin 5931 >>Turn in Back to Darnassus to Mathrengyl Bearwalker (fly to Rut'theran and take the portal up)
  .accept 6001 >>Accept Body and Heart — Lunaclaw lives in Darkshore, near Auberdine

step
  .goto Darnassus,40.4,8.5
  .class Hunter
  .xp 10
  .accept 6071 >>Accept The Hunter's Path from Jocaste in the Cenarion Enclave (level 10) — the pet quests are at Dazalar in Dolanaar
  .train Jocaste

-- Warriors, hunters and rogues: back to Dolanaar for the class quests, then Darnassus again -----------------------------------------

step
  .goto Teldrassil,47.2,63.6
  .class Warrior
  .complete 1683,1 >>Walk back east: kill Vorlus Vilehoof, the satyr by the Pools of Arlithrien south of Ban'ethil (lvl 10) and take his horn

step
  .goto Darnassus,57.3,34.6
  .class Warrior
  .turnin 1683 >>Turn in Vorlus Vilehoof to Elanaria in Darnassus
  .accept 1686 >>Accept The Shade of Elura — the Elunite and the shade are in Darkshore, by Auberdine

step
  .goto Teldrassil,56.7,59.5
  .class Hunter
  .turnin 6071 >>Turn in The Hunter's Path to Dazalar in Dolanaar (walk back east)
  .accept 6063 >>Accept Taming the Beast (Webwood Lurker)

step
  .goto Teldrassil,59.6,59.7
  .class Hunter
  .complete 6063 >>Use the Taming Rod on a Webwood Lurker in the woods around Dolanaar (lvl 5-6) and keep it alive until the channel ends

step
  .goto Teldrassil,56.7,59.5
  .class Hunter
  .turnin 6063 >>Turn in Taming the Beast to Dazalar
  .accept 6101 >>Accept Taming the Beast (Nightsaber Stalker)

step
  .goto Teldrassil,47.1,70.9
  .class Hunter
  .complete 6101 >>Use the Taming Rod on a Nightsaber Stalker west of Lake Al'Ameth (lvl 7-8)

step
  .goto Teldrassil,56.7,59.5
  .class Hunter
  .turnin 6101 >>Turn in Taming the Beast to Dazalar
  .accept 6102 >>Accept Taming the Beast (Strigid Screecher)

step
  .goto Teldrassil,41.1,68.4
  .class Hunter
  .complete 6102 >>Use the Taming Rod on a Strigid Screecher around the Pools of Arlithrien (lvl 7-8)

step
  .goto Teldrassil,56.7,59.5
  .class Hunter
  .turnin 6102 >>Turn in Taming the Beast to Dazalar
  .accept 6103 >>Accept Training the Beast — Jocaste in Darnassus teaches you to tame for real

step
  .goto Darnassus,40.4,8.5
  .class Hunter
  .turnin 6103 >>Turn in Training the Beast to Jocaste in Darnassus

step
  .goto Teldrassil,37.1,22.8
  .class Rogue
  .optional >>Destiny Calls
  .complete 2242,1 >>Kill Sethir the Ancient at the top of the hill in the far north of Teldrassil (lvl 12, with his minions lvl 8-10) and take his journal

step
  .goto Darnassus,37.0,21.9
  .class Rogue
  .optional >>Destiny Calls
  .turnin 2242 >>Turn in Destiny Calls to Syurna in Darnassus

step
  .goto Teldrassil,60.9,68.5
  .optional >>Return to Denalan
  .turnin 2498 >>Turn in Return to Denalan to Denalan at Lake Al'Ameth
  .accept 2499 >>Accept Oakenscowl

step
  .goto Teldrassil,53.8,75.1
  .optional >>Return to Denalan
  .complete 2499,1 >>Kill Oakenscowl in the timberling den south of the lake (lvl 9) and take the Gargantuan Tumor

step
  .goto Teldrassil,60.9,68.5
  .optional >>Return to Denalan
  .turnin 2499 >>Turn in Oakenscowl to Denalan

-- Rut'theran Village and the flight to Darkshore --------------------------------------------------------------------------------------

step
  .goto Darnassus,70.7,45.4
  .xp 10
  .accept 6344 >>Accept Nessa Shadowsong from Mydrannul, the guard at the Darnassus gate (level 10)

step
  .goto Teldrassil,56.3,92.4
  .turnin 6344 >>Take the portal down to Rut'theran Village and turn in Nessa Shadowsong to Nessa Shadowsong on the dock
  .accept 6341 >>Accept The Bounty of Teldrassil

step
  .goto Teldrassil,58.4,94.0
  .turnin 6341 >>Turn in The Bounty of Teldrassil to Vesprystus, the hippogryph master
  .accept 6342 >>Accept Flight to Auberdine — he flies you there for free

step
  .goto Teldrassil,58.4,94.0
  .xp 11 >>Teldrassil's quests run out around level 11; Darkshore's start at 10, so fly now (the Gnarlpine furbolgs in Ban'ethil Barrow Den are good XP if you want 12 first)
  .fly Auberdine >>Fly to Auberdine with Vesprystus

step
  .zone Darkshore >>Fly to Auberdine (or take the boat from the Rut'theran dock) — Laird stands by the Auberdine inn
]], "Lodestar_Guides_Alliance")

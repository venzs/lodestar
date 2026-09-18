-- Lodestar Guides: Alliance — Human starting zone, Elwynn Forest (levels 1-12).
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Elwynn route (Northshire Abbey → Goldshire → the
-- Stonefield and Maclure farms and the Fargodeep Mine → Crystal Lake, the Jasperlode Mine, Stone
-- Cairn Lake and the Eastvale Logging Camp → Westbrook Garrison and Hogger → Stormwind). Every quest
-- id and position comes from the data; the order still has to be verified in play (/lode record).
-- Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance/Human 1-12: Elwynn Forest
#faction Alliance
#race Human
#levels 1-12
#next Alliance 12-20: Westfall
#author Lodestar
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Northshire Abbey ------------------------------------------------------------------------------

step
  .goto Elwynn Forest,48.2,42.9
  .accept 783 >>Accept A Threat Within from Deputy Willem (right where you spawn)

step
  .goto Elwynn Forest,48.9,41.6
  .turnin 783 >>Turn in A Threat Within to Marshal McBride inside the abbey
  .accept 7 >>Accept Kobold Camp Cleanup

step
  .goto Elwynn Forest,49.0,36.3
  .complete 7,1 >>Kill 10 Kobold Vermin at the camps north of the abbey (lvl 1-2)

step
  .goto Elwynn Forest,48.9,41.6
  .turnin 7 >>Turn in Kobold Camp Cleanup to Marshal McBride
  .accept 15 >>Accept Investigate Echo Ridge

-- Class letters (McBride hands them out after Kobold Camp Cleanup) ---------------------------------

step
  .goto Elwynn Forest,48.9,41.6
  .class Warrior
  .accept 3100 >>Accept Simple Letter (warrior) from Marshal McBride

step
  .goto Elwynn Forest,48.9,41.6
  .class Paladin
  .accept 3101 >>Accept Consecrated Letter (paladin) from Marshal McBride

step
  .goto Elwynn Forest,48.9,41.6
  .class Rogue
  .accept 3102 >>Accept Encrypted Letter (rogue) from Marshal McBride

step
  .goto Elwynn Forest,48.9,41.6
  .class Priest
  .accept 3103 >>Accept Hallowed Letter (priest) from Marshal McBride

step
  .goto Elwynn Forest,48.9,41.6
  .class Mage
  .accept 3104 >>Accept Glyphic Letter (mage) from Marshal McBride

step
  .goto Elwynn Forest,48.9,41.6
  .class Warlock
  .accept 3105 >>Accept Tainted Letter (warlock) from Marshal McBride

step
  .goto Elwynn Forest,48.2,42.9
  .accept 5261 >>Accept Eagan Peltskinner from Deputy Willem, outside the abbey door
  .xp 2
  .accept 18 >>Accept Brotherhood of Thieves (level 2 — the kobolds get you there)

step
  .goto Elwynn Forest,48.9,40.2
  .turnin 5261 >>Turn in Eagan Peltskinner to Eagan Peltskinner, by the abbey wall
  .accept 33 >>Accept Wolves Across the Border

-- Class trainers in the abbey --------------------------------------------------------------------

step
  .goto Elwynn Forest,50.2,42.3
  .class Warrior
  .turnin 3100 >>Turn in Simple Letter to Llane Beshere in the abbey and train
  .train Llane Beshere

step
  .goto Elwynn Forest,50.4,42.1
  .class Paladin
  .turnin 3101 >>Turn in Consecrated Letter to Brother Sammuel in the abbey and train
  .train Brother Sammuel

step
  .goto Elwynn Forest,50.3,39.9
  .class Rogue
  .turnin 3102 >>Turn in Encrypted Letter to Jorik Kerridan, upstairs in the abbey, and train
  .train Jorik Kerridan

step
  .goto Elwynn Forest,49.8,39.5
  .class Priest
  .turnin 3103 >>Turn in Hallowed Letter to Priestess Anetta, in the library wing, and train
  .train Priestess Anetta

step
  .goto Elwynn Forest,49.7,39.4
  .class Mage
  .turnin 3104 >>Turn in Glyphic Letter to Khelden Bremen, in the library wing, and train
  .train Khelden Bremen

step
  .goto Elwynn Forest,49.9,42.6
  .class Warlock
  .turnin 3105 >>Turn in Tainted Letter to Drusilla La Salle, in the cellar, and train
  .train Drusilla La Salle

step
  .goto Elwynn Forest,49.9,42.6
  .class Warlock
  .accept 1598 >>Accept The Stolen Tome from Drusilla La Salle (the books are at the vineyard, east)

-- Echo Ridge and the wolves ------------------------------------------------------------------------

step
  .goto Elwynn Forest,49.4,34.7
  .complete 15,1 >>Kill 10 Kobold Workers around the mouth of the Echo Ridge Mine, north of the abbey (lvl 3)
  .complete 33,1 >>Loot 8 Tough Wolf Meat from Young and Timber Wolves in the woods around the abbey (lvl 1-2)

step
  .goto Elwynn Forest,48.9,41.6
  .turnin 15 >>Turn in Investigate Echo Ridge to Marshal McBride
  .accept 21 >>Accept Skirmish at Echo Ridge

step
  .goto Elwynn Forest,48.9,40.2
  .turnin 33 >>Turn in Wolves Across the Border to Eagan Peltskinner

step
  .goto Elwynn Forest,49.3,28.3
  .complete 21,1 >>Kill 12 Kobold Laborers inside the Echo Ridge Mine (lvl 3-4)

step
  .goto Elwynn Forest,48.9,41.6
  .turnin 21 >>Turn in Skirmish at Echo Ridge to Marshal McBride
  .accept 54 >>Accept Report to Goldshire

-- The vineyard: Defias thugs, Garrick, Milly ------------------------------------------------------

step
  .goto Elwynn Forest,54.0,46.9
  .complete 18,1 >>Loot 6 Red Burlap Bandanas from Defias Thugs in the vineyard east of the abbey (lvl 3-4)

step
  .goto Elwynn Forest,48.2,42.9
  .turnin 18 >>Turn in Brotherhood of Thieves to Deputy Willem
  .accept 6 >>Accept Bounty on Garrick Padfoot
  .accept 3903 >>Accept Milly Osworth

step
  .goto Elwynn Forest,50.7,39.3
  .turnin 3903 >>Turn in Milly Osworth to Milly Osworth, at the vineyard behind the abbey
  .accept 3904 >>Accept Milly's Harvest

step
  .goto Elwynn Forest,53.9,48.8
  .complete 3904,1 >>Pick up 8 of Milly's Harvest — the baskets among the vines (Defias Thugs, lvl 3-4)

step
  .goto Elwynn Forest,57.5,48.3
  .complete 6,1 >>Kill Garrick Padfoot at the shack on the east edge of the vineyard (lvl 5) and take his head

step
  .goto Elwynn Forest,56.7,44.0
  .class Warlock
  .complete 1598,1 >>Take Powers of the Void from the Stolen Books, in the shed north of Garrick's shack

step
  .goto Elwynn Forest,50.7,39.3
  .turnin 3904 >>Turn in Milly's Harvest to Milly Osworth
  .accept 3905 >>Accept Grape Manifest

step
  .goto Elwynn Forest,49.5,41.6
  .turnin 3905 >>Turn in Grape Manifest to Brother Neals, upstairs in the abbey

step
  .goto Elwynn Forest,48.2,42.9
  .turnin 6 >>Turn in Bounty on Garrick Padfoot to Deputy Willem

step
  .goto Elwynn Forest,49.9,42.6
  .class Warlock
  .turnin 1598 >>Turn in The Stolen Tome to Drusilla La Salle

step
  .goto Elwynn Forest,49.8,39.5
  .class Priest
  .xp 5
  .accept 5623 >>Accept In Favor of the Light from Priestess Anetta (level 5) — a hand-off to Priestess Josetta in Goldshire

step
  .goto Elwynn Forest,48.9,41.6
  .xp 5 >>You should be level 5 leaving Northshire; kill kobolds or Defias Thugs if not, then take the road south out of the valley

-- Goldshire: first visit -----------------------------------------------------------------------------

step
  .goto Elwynn Forest,45.6,47.7
  .accept 2158 >>Accept Rest and Relaxation from Falkhaan Isenstrider, on the road south of Northshire

step
  .goto Elwynn Forest,42.1,65.9
  .turnin 54 >>Turn in Report to Goldshire to Marshal Dughan in Goldshire
  .accept 62 >>Accept The Fargodeep Mine

step
  .goto Elwynn Forest,42.1,67.3
  .accept 47 >>Accept Gold Dust Exchange from Remy "Two Times", next to Dughan

step
  .goto Elwynn Forest,43.3,65.7
  .accept 60 >>Accept Kobold Candles from William Pestle, in the shop next to the inn

step
  .goto Elwynn Forest,43.8,65.8
  .turnin 2158 >>Turn in Rest and Relaxation to Innkeeper Farley in the Lion's Pride Inn
  .hs Goldshire >>Set your hearthstone at the Lion's Pride Inn

step
  .goto Elwynn Forest,43.3,65.7
  .class Priest
  .turnin 5623 >>Turn in In Favor of the Light to Priestess Josetta, upstairs in the inn
  .accept 5624 >>Accept Garments of the Light

step
  .goto Elwynn Forest,48.1,68.0
  .class Priest
  .complete 5624,1 >>Cast Lesser Heal and Power Word: Fortitude on Guard Roberts, on the road east of Goldshire (friendly — just buff and heal him)

step
  .goto Elwynn Forest,43.3,65.7
  .class Priest
  .turnin 5624 >>Turn in Garments of the Light to Priestess Josetta

step
  .goto Elwynn Forest,41.1,65.8
  .class Warrior
  .train Lyria Du Lac >>Train at Lyria Du Lac, the warrior trainer behind the smithy

step
  .goto Elwynn Forest,41.1,66.0
  .class Paladin
  .train Brother Wilhelm >>Train at Brother Wilhelm, the paladin trainer behind the smithy

step
  .goto Elwynn Forest,43.9,65.9
  .class Rogue
  .train Keryn Sylvius >>Train at Keryn Sylvius, the rogue trainer behind the inn

step
  .goto Elwynn Forest,43.3,65.7
  .class Priest
  .train Priestess Josetta >>Train at Priestess Josetta, upstairs in the inn

step
  .goto Elwynn Forest,43.2,66.2
  .class Mage
  .train Zaldimar Wefhellt >>Train at Zaldimar Wefhellt, the mage trainer upstairs in the inn

step
  .goto Elwynn Forest,44.4,66.2
  .class Warlock
  .train Maximillian Crowe >>Train at Maximillian Crowe, the warlock trainer in the cellar of the inn

-- South: the Maclure and Stonefield farms, the Fargodeep Mine ----------------------------------------

step
  .goto Elwynn Forest,43.2,89.6
  .accept 106 >>Accept Young Lovers from Maybell Maclure at the Maclure Vineyard, south of Goldshire

step
  .goto Elwynn Forest,29.8,86.0
  .turnin 106 >>Turn in Young Lovers to Tommy Joe Stonefield, by the river west of the Stonefield Farm
  .accept 111 >>Accept Speak with Gramma

step
  .goto Elwynn Forest,34.9,83.9
  .turnin 111 >>Turn in Speak with Gramma to Gramma Stonefield at the farmhouse
  .accept 107 >>Accept Note to William

step
  .goto Elwynn Forest,34.5,84.3
  .accept 85 >>Accept Lost Necklace from "Auntie" Bernice Stonefield, outside the farmhouse

step
  .goto Elwynn Forest,34.7,84.5
  .xp 6
  .accept 88 >>Accept Princess Must Die! from Ma Stonefield (level 6) — Princess lives at the pumpkin patch far to the east; it is turned in here later

step
  .goto Elwynn Forest,43.1,85.7
  .turnin 85 >>Turn in Lost Necklace to Billy Maclure at the Maclure Vineyard
  .accept 86 >>Accept Pie for Billy

step
  .goto Elwynn Forest,38.8,78.6
  .complete 86,1 >>Loot 4 Chunks of Boar Meat from Stonetusk Boars between the two farms (lvl 5-6)

step
  .goto Elwynn Forest,34.5,84.3
  .turnin 86 >>Turn in Pie for Billy to "Auntie" Bernice Stonefield
  .accept 84 >>Accept Back to Billy

step
  .goto Elwynn Forest,43.1,85.7
  .turnin 84 >>Turn in Back to Billy to Billy Maclure
  .accept 87 >>Accept Goldtooth

step
  .goto Elwynn Forest,40.6,82.3
  .complete 62,1 >>Walk into the Fargodeep Mine, west of the Maclure Vineyard (Kobold Tunnelers, lvl 5-6)

step
  .goto Elwynn Forest,39.7,80.2
  .complete 62,2 >>Follow the tunnels to the far chamber of the mine

step
  .goto Elwynn Forest,39.0,81.3
  .complete 47,1 >>Loot 10 Gold Dust from the Kobold Tunnelers and Miners in and around the mine (lvl 5-7)
  .complete 60,1 >>Loot 8 Large Candles from the same kobolds

step
  .goto Elwynn Forest,41.7,78.0
  .complete 87,1 >>Kill Goldtooth in the mine (lvl 8 — he patrols the tunnels) and loot Bernice's Necklace

step
  .goto Elwynn Forest,34.5,84.3
  .turnin 87 >>Turn in Goldtooth to "Auntie" Bernice Stonefield

-- Goldshire: second visit --------------------------------------------------------------------------------

step
  .goto Elwynn Forest,42.1,65.9
  .turnin 62 >>Turn in The Fargodeep Mine to Marshal Dughan (hearth to Goldshire)
  .accept 76 >>Accept The Jasperlode Mine

step
  .goto Elwynn Forest,42.1,67.3
  .turnin 47 >>Turn in Gold Dust Exchange to Remy "Two Times"
  .xp 7
  .accept 40 >>Accept A Fishy Peril (level 7)

step
  .goto Elwynn Forest,42.1,65.9
  .turnin 40 >>Turn in A Fishy Peril to Marshal Dughan
  .accept 35 >>Accept Further Concerns — for Guard Thomas at the Eastvale Logging Camp

step
  .goto Elwynn Forest,43.3,65.7
  .turnin 60 >>Turn in Kobold Candles to William Pestle
  .turnin 107 >>Turn in Note to William
  .accept 61 >>Accept Shipment to Stormwind — for Morgan Pestle in Stormwind
  .accept 112 >>Accept Collecting Kelp

step
  .goto Elwynn Forest,43.8,65.8
  .vendor >>Sell junk at the vendors around the inn and buy food and water

-- East: Crystal Lake, the Jasperlode Mine, Stone Cairn Lake, Eastvale -------------------------------------

step
  .goto Elwynn Forest,52.0,66.2
  .complete 112,1 >>Loot 4 Crystal Kelp Fronds from Murlocs and Murloc Streamrunners around Crystal Lake, east of Goldshire (lvl 6-7)

step
  .goto Elwynn Forest,43.3,65.7
  .turnin 112 >>Turn in Collecting Kelp to William Pestle (a short run back to Goldshire)
  .accept 114 >>Accept The Escape — for Maybell Maclure; it is turned in on the Hogger loop later

step
  .goto Elwynn Forest,60.2,49.2
  .complete 76,1 >>Walk into the Jasperlode Mine, north-east of Crystal Lake (Mine Spiders and Kobold Geomancers, lvl 7-9)

step
  .goto Elwynn Forest,61.8,47.1
  .complete 76,2 >>Follow the tunnel to the back chamber of the mine

step
  .goto Elwynn Forest,74.0,72.2
  .turnin 35 >>Turn in Further Concerns to Guard Thomas at the Eastvale Logging Camp bridge
  .accept 37 >>Accept Find the Lost Guards
  .accept 46 >>Accept Bounty on Murlocs
  .accept 52 >>Accept Protect the Frontier

step
  .goto Elwynn Forest,79.5,68.8
  .accept 83 >>Accept Red Linen Goods from Sara Timberlain at the logging camp

step
  .goto Elwynn Forest,81.4,66.1
  .accept 5545 >>Accept A Bundle of Trouble from Supervisor Raelen at the logging camp

step
  .goto Elwynn Forest,80.2,60.0
  .complete 5545,1 >>Pick up 8 Bundles of Wood — they lie among the felled trees north of the camp

step
  .goto Elwynn Forest,78.4,62.7
  .complete 52,1 >>Kill 8 Prowlers in the woods north of the camp (lvl 9-10)
  .complete 52,2 >>Kill 5 Young Forest Bears — they roam the same woods, between the camp and the lake (lvl 8-9)

step
  .goto Elwynn Forest,78.3,58.0
  .complete 46,1 >>Loot 12 Torn Murloc Fins from Murloc Foragers and Lurkers on the lake shore north of the camp (lvl 9-10)

step
  .goto Elwynn Forest,72.7,60.3
  .turnin 37 >>Find the half-eaten body on the west side of the lake and turn in Find the Lost Guards
  .accept 45 >>Accept Discover Rolf's Fate from the body

step
  .goto Elwynn Forest,79.8,55.5
  .turnin 45 >>Find Rolf's corpse among the murlocs on the north-east shore and turn in Discover Rolf's Fate
  .accept 71 >>Accept Report to Thomas

step
  .goto Elwynn Forest,72.3,55.0
  .complete 83,1 >>Loot 6 Red Linen Bandanas from Defias Rogue Wizards around Stone Cairn Lake, north-west of the murlocs (lvl 9-10)

step
  .goto Elwynn Forest,79.5,68.8
  .turnin 83 >>Turn in Red Linen Goods to Sara Timberlain

step
  .goto Elwynn Forest,81.4,66.1
  .turnin 5545 >>Turn in A Bundle of Trouble to Supervisor Raelen

step
  .goto Elwynn Forest,74.0,72.2
  .turnin 71 >>Turn in Report to Thomas to Guard Thomas
  .turnin 46 >>Turn in Bounty on Murlocs
  .turnin 52 >>Turn in Protect the Frontier
  .accept 39 >>Accept Deliver Thomas' Report — for Marshal Dughan

step
  .goto Elwynn Forest,69.7,79.6
  .xp 8
  .complete 88,1 >>Kill Princess at the Brackwell Pumpkin Patch, south-west of the camp (lvl 9 — a boar with two Porcine Entourage pigs, lvl 8) and take the Brass Collar

-- Goldshire: third visit, then west to Westbrook Garrison and Hogger -------------------------------------------

step
  .goto Elwynn Forest,42.1,65.9
  .turnin 39 >>Turn in Deliver Thomas' Report to Marshal Dughan (hearth to Goldshire)
  .turnin 76 >>Turn in The Jasperlode Mine
  .accept 239 >>Accept Westbrook Garrison Needs Help!

step
  .goto Elwynn Forest,42.1,65.9
  .optional >>Cloth and Leather Armor is a hand-off back to Sara Timberlain at Eastvale — only if you are going that way again
  .accept 59 >>Accept Cloth and Leather Armor from Marshal Dughan

step
  .goto Elwynn Forest,79.5,68.8
  .optional >>Cloth and Leather Armor
  .turnin 59 >>Turn in Cloth and Leather Armor to Sara Timberlain at the Eastvale Logging Camp

step
  .goto Elwynn Forest,41.1,65.8
  .class Warrior
  .xp 10
  .accept 1638 >>Accept A Warrior's Training from Lyria Du Lac (level 10) — a hand-off to Harry Burlguard in Stormwind

step
  .goto Elwynn Forest,44.5,66.3
  .class Warlock
  .xp 10
  .accept 1685 >>Accept Gakin's Summons from Remen Marcot, in the inn (level 10) — the voidwalker quests start in Stormwind

step
  .goto Elwynn Forest,43.2,66.2
  .class Mage
  .xp 10
  .accept 1860 >>Accept Speak with Jennea from Zaldimar Wefhellt (level 10) — for Jennea Cannon in Stormwind

step
  .goto Elwynn Forest,43.9,65.9
  .class Rogue
  .xp 10
  .accept 2205 >>Accept Seek out SI: 7 from Keryn Sylvius (level 10) — for Master Mathias Shaw in Stormwind

step
  .goto Elwynn Forest,43.3,65.7
  .class Priest
  .xp 10
  .accept 5635 >>Accept Desperate Prayer from Priestess Josetta (level 10) — for High Priestess Laurena in Stormwind

step
  .goto Elwynn Forest,43.8,65.8
  .train >>Train new skills at your class trainer in Goldshire, sell and repair

step
  .goto Elwynn Forest,24.2,74.4
  .turnin 239 >>Turn in Westbrook Garrison Needs Help! to Deputy Rainer at Westbrook Garrison, at the west end of the road
  .accept 11 >>Accept Riverpaw Gnoll Bounty

step
  .goto Elwynn Forest,24.5,74.7
  .accept 176 >>Read the Wanted Poster outside the garrison and accept Wanted: "Hogger"

step
  .goto Elwynn Forest,31.6,80.6
  .complete 11,1 >>Loot 8 Painted Gnoll Armbands from Riverpaw Runts and Outrunners in the gnoll camps south of the garrison (lvl 8-10)

step
  .goto Elwynn Forest,25.8,89.8
  .optional >>Hogger is an elite (lvl 11) with Gruff Swiftbite (lvl 12) beside him — find a group or come back at 12; the armbands alone are worth the trip
  .complete 176,1 >>Kill Hogger at the camp in the south-west corner of the forest and take the Huge Gnoll Claw

step
  .goto Elwynn Forest,25.8,89.8
  .optional >>The Collector: the Gold Pickup Schedule drops from Gruff Swiftbite and the Riverpaw gnolls; Morgan the Collector lives at the pumpkin patch far to the east
  .item 1307
  .accept 123 >>Read the Gold Pickup Schedule and accept The Collector

step
  .goto Elwynn Forest,24.2,74.4
  .turnin 11 >>Turn in Riverpaw Gnoll Bounty to Deputy Rainer

step
  .goto Elwynn Forest,34.7,84.5
  .turnin 88 >>Turn in Princess Must Die! to Ma Stonefield at the Stonefield Farm, on the way back east

step
  .goto Elwynn Forest,43.2,89.6
  .turnin 114 >>Turn in The Escape to Maybell Maclure at the Maclure Vineyard

step
  .goto Elwynn Forest,42.1,65.9
  .turnin 176 >>Turn in Wanted: "Hogger" to Marshal Dughan in Goldshire

step
  .goto Elwynn Forest,42.1,65.9
  .optional >>The Collector
  .turnin 123 >>Turn in The Collector to Marshal Dughan
  .accept 147 >>Accept Manhunt

step
  .goto Elwynn Forest,71.1,80.6
  .optional >>Manhunt
  .complete 147,1 >>Kill Morgan the Collector in the house at the Brackwell Pumpkin Patch (lvl 10) and take his ring

step
  .goto Elwynn Forest,42.1,65.9
  .optional >>Manhunt
  .turnin 147 >>Turn in Manhunt to Marshal Dughan

step
  .goto Elwynn Forest,42.1,65.9
  .xp 10 >>You should be level 10-11 now; the Riverpaw gnolls and the Defias around Stone Cairn Lake are good XP if you are short. Take the road north out of Goldshire to Stormwind

-- Stormwind ---------------------------------------------------------------------------------------------------

step
  .goto Stormwind City,56.2,64.6
  .turnin 61 >>Turn in Shipment to Stormwind to Morgan Pestle, the alchemist in the Trade District

step
  .goto Stormwind City,66.3,62.1
  .text >>Talk to Dungar Longdrink, the gryphon master on the platform above the Trade District, to learn the Stormwind flight path

step
  .goto Stormwind City,74.3,37.3
  .class Warrior
  .turnin 1638 >>Turn in A Warrior's Training to Harry Burlguard in the Pig and Whistle tavern, Old Town
  .accept 1639 >>Accept Bartleby the Drunk

step
  .goto Stormwind City,73.8,36.3
  .class Warrior
  .turnin 1639 >>Turn in Bartleby the Drunk to Bartleby, at the bar
  .accept 1640 >>Accept Beat Bartleby

step
  .goto Stormwind City,73.8,36.3
  .class Warrior
  .complete 1640 >>Duel Bartleby and beat him down (he yields at low health)

step
  .goto Stormwind City,73.8,36.3
  .class Warrior
  .turnin 1640 >>Turn in Beat Bartleby to Bartleby
  .accept 1665 >>Accept Bartleby's Mug

step
  .goto Stormwind City,74.3,37.3
  .class Warrior
  .turnin 1665 >>Turn in Bartleby's Mug to Harry Burlguard

step
  .goto Stormwind City,74.3,37.3
  .class Warrior
  .optional >>Marshal Haggard: Dead-tooth Jack lives in the far south-east corner of Elwynn — a long detour for a level 10 blue weapon
  .accept 1666 >>Accept Marshal Haggard from Harry Burlguard

step
  .goto Elwynn Forest,84.6,69.4
  .class Warrior
  .optional >>Marshal Haggard
  .turnin 1666 >>Turn in Marshal Haggard to Marshal Haggard at his house east of the Eastvale Logging Camp
  .accept 1667 >>Accept Dead-tooth Jack

step
  .goto Elwynn Forest,89.3,79.0
  .class Warrior
  .optional >>Marshal Haggard
  .complete 1667,2 >>Kill Dead-Tooth Jack at the camp in the south-east corner of the forest (lvl 11) for his key
  .complete 1667,1 >>Open Dead-tooth's Strongbox next to him for Marshal Haggard's Badge

step
  .goto Elwynn Forest,84.6,69.4
  .class Warrior
  .optional >>Marshal Haggard
  .turnin 1667 >>Turn in Dead-tooth Jack to Marshal Haggard

step
  .goto Stormwind City,78.5,45.7
  .class Warrior
  .train Ilsa Corbin >>Train at Ilsa Corbin in the Command Center, Old Town

step
  .goto Stormwind City,25.3,78.6
  .class Warlock
  .turnin 1685 >>Turn in Gakin's Summons to Gakin the Darkbinder in the Slaughtered Lamb cellar, Mage Quarter
  .accept 1688 >>Accept Surena Caledon — she lives at the Brackwell Pumpkin Patch in Elwynn; do it on your next trip east, or skip it until the voidwalker quest at 10 matters to you

step
  .goto Elwynn Forest,71.0,80.8
  .class Warlock
  .optional >>Surena Caledon: the voidwalker chain sends you back to the pumpkin patch in eastern Elwynn
  .complete 1688,1 >>Kill Surena Caledon in the house at the Brackwell Pumpkin Patch (lvl 9) and take her choker

step
  .goto Stormwind City,25.3,78.6
  .class Warlock
  .optional >>Surena Caledon
  .turnin 1688 >>Turn in Surena Caledon to Gakin the Darkbinder
  .accept 1689 >>Accept The Binding

step
  .goto Stormwind City,25.3,78.6
  .class Warlock
  .optional >>Surena Caledon
  .complete 1689,1 >>Use the choker at the summoning circle in the Slaughtered Lamb cellar and kill the Summoned Voidwalker (lvl 10)

step
  .goto Stormwind City,25.3,78.6
  .class Warlock
  .optional >>Surena Caledon
  .turnin 1689 >>Turn in The Binding to Gakin the Darkbinder for your voidwalker

step
  .goto Stormwind City,25.3,78.2
  .class Warlock
  .train Demisette Cloyce >>Train at Demisette Cloyce in the Slaughtered Lamb

step
  .goto Stormwind City,38.6,79.3
  .class Mage
  .turnin 1860 >>Turn in Speak with Jennea to Jennea Cannon in the Wizard's Sanctum, Mage Quarter
  .train Jennea Cannon

step
  .goto Stormwind City,75.8,59.8
  .class Rogue
  .turnin 2205 >>Turn in Seek out SI: 7 to Master Mathias Shaw in the SI:7 building, Old Town

step
  .goto Stormwind City,74.6,52.8
  .class Rogue
  .train Osborne the Night Man >>Train at Osborne the Night Man in SI:7

step
  .goto Stormwind City,38.6,26.1
  .class Priest
  .turnin 5635 >>Turn in Desperate Prayer to High Priestess Laurena in the Cathedral of Light

step
  .goto Stormwind City,42.1,30.0
  .class Priest
  .train Brother Benjamin >>Train at Brother Benjamin in the cathedral

step
  .goto Stormwind City,38.7,32.8
  .class Paladin
  .train Arthur the Faithful >>Train at Arthur the Faithful in the cathedral

-- Paladin: the Tome of Divinity (Redemption, level 12) ---------------------------------------------------------
-- A paladin who is not 12 yet can leave this for the Stormwind visit in the Westfall guide: Rall keeps the quest.

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .xp 12
  .accept 1641 >>Accept The Tome of Divinity from Duthorian Rall in the cathedral (level 12 — the Redemption chain; the Riverpaw gnolls or the Defias at Stone Cairn Lake get you there if you are short)

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .turnin 1641 >>Turn in The Tome of Divinity to Duthorian Rall — he hands you the Tome itself

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .item 6775
  .accept 1642 >>Read the Tome of Divinity in your bags and accept The Tome of Divinity

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .turnin 1642 >>Turn in The Tome of Divinity to Duthorian Rall
  .accept 1643 >>Accept The Tome of Divinity — Stephanie Turner in the Trade District

step
  .goto Stormwind City,57.1,61.7
  .class Paladin
  .turnin 1643 >>Turn in The Tome of Divinity to Stephanie Turner, the tailoring supplier in the Trade District
  .accept 1644 >>Accept The Tome of Divinity — she wants 10 Linen Cloth (you have some by now; the auction house is next door if not)

step
  .goto Stormwind City,57.1,61.7
  .class Paladin
  .turnin 1644 >>Turn in The Tome of Divinity to Stephanie Turner
  .accept 1780 >>Accept The Tome of Divinity

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .turnin 1780 >>Turn in The Tome of Divinity to Duthorian Rall
  .accept 1781 >>Accept The Tome of Divinity

step
  .goto Stormwind City,38.6,26.6
  .class Paladin
  .turnin 1781 >>Turn in The Tome of Divinity to Gazin Tenorm, next to Rall
  .accept 1786 >>Accept The Tome of Divinity — Henze Faulk at Stone Cairn Lake in Elwynn

step
  .goto Elwynn Forest,72.6,51.4
  .class Paladin
  .turnin 1786 >>Turn in The Tome of Divinity to Henze Faulk, lying on the island in Stone Cairn Lake (kill the Defias Rogue Wizards around him, lvl 9-10)
  .accept 1787 >>Accept The Tome of Divinity

step
  .goto Elwynn Forest,72.3,55.0
  .class Paladin
  .complete 1787,1 >>Loot a Defias Script from the Defias Rogue Wizards around the lake, then use the Symbol of Life on Henze Faulk to revive him

step
  .goto Stormwind City,38.6,26.6
  .class Paladin
  .turnin 1787 >>Turn in The Tome of Divinity to Gazin Tenorm in the cathedral (hearth to Goldshire and walk, or fly if you can)
  .accept 1788 >>Accept The Tome of Divinity

step
  .goto Stormwind City,39.8,29.8
  .class Paladin
  .turnin 1788 >>Turn in The Tome of Divinity to Duthorian Rall for Redemption

-- On to Westfall -------------------------------------------------------------------------------------------------

step
  .goto Stormwind City,52.6,65.7
  .xp 11 >>Train at your class trainer, sell and repair. Elwynn's quests run out around 11; Westfall's start at 10, so head out now (the Riverpaw gnolls near Westbrook are good XP if you want 12 first)

step
  .zone Westfall >>Hearth to Goldshire and take the road west past Westbrook Garrison into Westfall — the Furlbrow farm is just past the border
]], "Lodestar_Guides_Alliance")

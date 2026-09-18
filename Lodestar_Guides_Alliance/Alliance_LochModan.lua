-- Lodestar Guides: Alliance — Loch Modan (levels 12-20), the continuation of the Dwarf and Gnome route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Thelsamar loops: Thelsamar and a free gryphon ride to
-- Ironforge for the trainers, the Silver Stream Mine, Stonesplinter Valley, the road east to
-- Ironband's Excavation and the Farstrider Lodge, an Ironforge trip for the powder, the escort to
-- Ironband, the Mo'grosh Stronghold, the dam and the Algaz pass into the Wetlands. Every quest id
-- and position comes from the data; the order still has to be verified in play (/lode record).
-- Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance 12-20: Loch Modan
#faction Alliance
#levels 12-19
#next Alliance 20-25: Wetlands
#author Lodestar
-- #levels stops at 19 so the auto-pick hands a level 20 character to the next guide; the route itself runs to 20.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Thelsamar: first visit, and the gryphon ride to Ironforge --------------------------------------------------

step
  .goto Loch Modan,32.7,49.7
  .turnin 414 >>Turn in Stout to Kadrell to Mountaineer Kadrell, who walks the road through Thelsamar (if you brought it from Dun Morogh)
  .accept 416 >>Accept Rat Catching
  .accept 1339 >>Accept Mountaineer Stormpike's Task

step
  .goto Loch Modan,34.8,49.3
  .accept 418 >>Accept Thelsamar Blood Sausages from Vidra Hearthstove, outside the inn

step
  .goto Loch Modan,35.5,48.4
  .hs Thelsamar >>Set your hearthstone at the Thelsamar inn (Innkeeper Hearthstove)
  .vendor

step
  .goto Loch Modan,37.0,47.8
  .race Dwarf,Gnome
  .accept 6387 >>Accept Honor Students from Brock Stoneseeker, up the hill east of the inn — a free gryphon ride to Ironforge and back

step
  .goto Loch Modan,33.9,51.0
  .race Dwarf,Gnome
  .turnin 6387 >>Turn in Honor Students to Thorgrum Borrelson, the gryphon master south of the inn
  .accept 6391 >>Accept Ride to Ironforge — he flies you there for free

step
  .goto Loch Modan,33.9,51.0
  .fly Ironforge >>Fly to Ironforge with Thorgrum Borrelson (dwarves and gnomes fly free with Ride to Ironforge) — the only class trainers until Menethil Harbor

step
  .goto Ironforge,51.5,26.3
  .race Dwarf,Gnome
  .turnin 6391 >>Turn in Ride to Ironforge to Golnir Bouldertoe, the mining supplier in the Great Forge
  .accept 6388 >>Accept Gryth Thurden

step
  .goto Ironforge,65.9,88.4
  .class Warrior
  .train Bilban Tosslespanner >>Train at Bilban Tosslespanner in the Military Ward

step
  .goto Ironforge,23.1,6.1
  .class Paladin
  .train Brandur Ironhammer >>Train at Brandur Ironhammer in the Hall of Mysteries

step
  .goto Ironforge,23.5,8.3
  .race Dwarf
  .class Paladin
  .turnin 1784 >>Turn in The Tome of Divinity to Muiredon Battleforge in the Hall of Mysteries (if you revived Narm Faulk in Dun Morogh)
  .accept 1785 >>Accept The Tome of Divinity

step
  .goto Ironforge,27.6,12.2
  .race Dwarf
  .class Paladin
  .turnin 1785 >>Turn in The Tome of Divinity to Tiza Battleforge for Redemption

step
  .goto Ironforge,69.9,82.9
  .class Hunter
  .train Regnus Thundergranite >>Train at Regnus Thundergranite in the Military Ward

step
  .goto Ironforge,51.5,15.3
  .class Rogue
  .train Fenthwick >>Train at Fenthwick in the Forlorn Cavern

step
  .goto Ironforge,24.4,9.2
  .class Priest
  .train Braenna Flintcrag >>Train at Braenna Flintcrag in the Hall of Mysteries

step
  .goto Ironforge,27.2,8.3
  .class Mage
  .train Bink >>Train at Bink in the Hall of Mysteries

step
  .goto Ironforge,50.3,5.7
  .class Warlock
  .train Briarthorn >>Train at Briarthorn in the Forlorn Cavern

step
  .goto Ironforge,55.5,47.7
  .race Dwarf,Gnome
  .turnin 6388 >>Turn in Gryth Thurden to Gryth Thurden, the gryphon master in the Great Forge
  .accept 6392 >>Accept Return to Brock — a free flight back to Thelsamar

step
  .goto Ironforge,55.5,47.7
  .fly Thelsamar >>Sell and repair in the Commons, then fly back to Thelsamar

step
  .goto Loch Modan,37.0,47.8
  .race Dwarf,Gnome
  .turnin 6392 >>Turn in Return to Brock to Brock Stoneseeker

-- North: the Silver Stream Mine ----------------------------------------------------------------------------------

step
  .goto Loch Modan,24.8,18.4
  .turnin 1339 >>Turn in Mountaineer Stormpike's Task to Mountaineer Stormpike at the camp by the Silver Stream Mine, up the road north of Thelsamar
  .accept 307 >>Accept Filthy Paws

step
  .goto Loch Modan,35.7,24.3
  .complete 307,1 >>Open 6 Miners' League Crates inside the Silver Stream Mine, east of the camp (Tunnel Rats, lvl 10-13)
  .complete 416,1 >>Loot 10 Tunnel Rat Ears from the Tunnel Rat Vermin, Scouts, Geomancers and Diggers in the mine

step
  .goto Loch Modan,24.8,18.4
  .turnin 307 >>Turn in Filthy Paws to Mountaineer Stormpike

step
  .goto Loch Modan,32.7,49.7
  .turnin 416 >>Turn in Rat Catching to Mountaineer Kadrell in Thelsamar (hearth)

-- South-west: Stonesplinter Valley ---------------------------------------------------------------------------------

step
  .goto Loch Modan,22.1,73.1
  .accept 224 >>Accept In Defense of the King's Lands from Mountaineer Cobbleflint at the Valley of Kings outpost, south-west of Thelsamar (Forest Lurkers, Elder Black Bears and Mountain Boars on the way drop the Blood Sausages ingredients)

step
  .goto Loch Modan,23.2,73.7
  .accept 267 >>Accept The Trogg Threat from Captain Rugelfuss, next to him

step
  .goto Loch Modan,32.2,70.4
  .complete 224,1 >>Kill 10 Stonesplinter Troggs at the mouth of Stonesplinter Valley, east of the outpost (lvl 11-12)
  .complete 224,2 >>Kill 10 Stonesplinter Scouts there too (lvl 11-12)
  .complete 267,1 >>Loot 10 Trogg Stone Teeth from any Stonesplinter trogg

step
  .goto Loch Modan,22.1,73.1
  .turnin 224 >>Turn in In Defense of the King's Lands to Mountaineer Cobbleflint

step
  .goto Loch Modan,23.5,76.4
  .accept 237 >>Accept In Defense of the King's Lands (part 2) from Mountaineer Gravelgaw, south of the outpost

step
  .goto Loch Modan,36.8,77.7
  .xp 13
  .complete 237,1 >>Kill 10 Stonesplinter Skullthumpers deeper in the valley (lvl 13-14)
  .complete 237,2 >>Kill 10 Stonesplinter Seers there too (lvl 13-14 — casters; kill them first)

step
  .goto Loch Modan,23.5,76.4
  .turnin 237 >>Turn in In Defense of the King's Lands to Mountaineer Gravelgaw

step
  .goto Loch Modan,23.5,74.5
  .accept 263 >>Accept In Defense of the King's Lands (part 3) from Mountaineer Wallbang

step
  .goto Loch Modan,23.2,73.7
  .turnin 267 >>Turn in The Trogg Threat to Captain Rugelfuss

step
  .goto Loch Modan,37.5,86.1
  .xp 14
  .complete 263,1 >>Kill 10 Stonesplinter Bonesnappers at the south end of the valley (lvl 15-16)
  .complete 263,2 >>Kill 10 Stonesplinter Shamans there too (lvl 15-16 — casters)

step
  .goto Loch Modan,23.5,74.5
  .turnin 263 >>Turn in In Defense of the King's Lands to Mountaineer Wallbang

step
  .goto Loch Modan,23.2,73.7
  .optional >>Grawmug (lvl 17) sits at the very end of the valley with two wolves — a group quest, or come back at 18
  .accept 217 >>Accept In Defense of the King's Lands (part 4) from Captain Rugelfuss

step
  .goto Loch Modan,34.8,90.5
  .optional >>Grawmug
  .complete 217,1 >>Kill Grawmug at the cave at the south end of Stonesplinter Valley (lvl 17)
  .complete 217,2 >>Kill Gnasher, his wolf (lvl 16)
  .complete 217,3 >>Kill Brawler, his other wolf (lvl 16)

step
  .goto Loch Modan,23.2,73.7
  .optional >>Grawmug
  .turnin 217 >>Turn in In Defense of the King's Lands to Captain Rugelfuss

step
  .goto Loch Modan,40.4,71.7
  .complete 418,2 >>Loot 3 Bear Meat from Elder Black Bears in the hills east of the valley (lvl 11-12)
  .complete 418,1 >>Loot 3 Boar Intestines from Mountain Boars around the loch (lvl 12-15)
  .complete 418,3 >>Loot 3 Spider Ichor from Forest Lurkers in the woods (lvl 10-11)

-- Thelsamar: second visit ------------------------------------------------------------------------------------------------

step
  .goto Loch Modan,34.8,49.3
  .turnin 418 >>Turn in Thelsamar Blood Sausages to Vidra Hearthstove in Thelsamar

step
  .goto Loch Modan,37.2,47.4
  .xp 13
  .accept 436 >>Accept Ironband's Excavation from Jern Hornhelm, up the hill east of the inn (level 13)

step
  .goto Loch Modan,35.5,48.4
  .vendor >>Sell junk at the vendors in Thelsamar and buy food and water

-- East: Ironband's Excavation and the Farstrider Lodge ---------------------------------------------------------------------

step
  .goto Loch Modan,65.9,65.6
  .accept 298 >>Accept Excavation Progress Report from Prospector Ironband at Ironband's Excavation, down the road south-east of Thelsamar and along the south shore of the loch

step
  .goto Loch Modan,64.9,66.7
  .turnin 436 >>Turn in Ironband's Excavation to Magmar Fellhew, next to him
  .accept 297 >>Accept Gathering Idols

step
  .goto Loch Modan,83.5,65.5
  .accept 257 >>Accept A Hunter's Boast from Daryl the Youngling at the Farstrider Lodge, east of the excavation

step
  .goto Loch Modan,81.8,61.7
  .accept 385 >>Accept Crocolisk Hunting from Marek Ironheart, inside the lodge

step
  .goto Loch Modan,74.7,67.7
  .complete 257,1 >>Kill 10 Mountain Buzzards around the lodge (lvl 15-16)

step
  .goto Loch Modan,83.5,65.5
  .turnin 257 >>Turn in A Hunter's Boast to Daryl the Youngling
  .accept 258 >>Accept A Hunter's Challenge

step
  .goto Loch Modan,74.8,50.7
  .xp 16
  .complete 258,1 >>Kill 5 Elder Mountain Boars in the hills north of the lodge (lvl 16-17)

step
  .goto Loch Modan,62.0,45.4
  .complete 385,1 >>Loot 6 Crocolisk Meat from Loch Crocolisks on the east shore of the loch (lvl 14-15 — they hit hard; fight at the water's edge)
  .complete 385,2 >>Loot 3 Crocolisk Skins from them too

step
  .goto Loch Modan,81.8,61.7
  .turnin 385 >>Turn in Crocolisk Hunting to Marek Ironheart at the lodge

step
  .goto Loch Modan,83.5,65.5
  .turnin 258 >>Turn in A Hunter's Challenge to Daryl the Youngling

step
  .goto Loch Modan,81.7,64.1
  .accept 271 >>Accept Vyrin's Revenge from Vyrin Swiftwind, outside the lodge — Ol' Sooty lives in the hills west, by the road back to Thelsamar

step
  .goto Loch Modan,70.6,64.8
  .complete 297,1 >>Loot 8 Carved Stone Idols from the Stonesplinter Geomancers, Diggers and Berserk Troggs at the excavation (lvl 17-20 — pull carefully, the Berserkers hit hard)

step
  .goto Loch Modan,64.9,66.7
  .turnin 297 >>Turn in Gathering Idols to Magmar Fellhew at the excavation

step
  .goto Loch Modan,42.5,64.7
  .xp 17
  .complete 271,1 >>Kill Ol' Sooty in the hills south of the road, west of the loch (lvl 20 — a big bear with a lot of health; use cooldowns) and take his head

-- Thelsamar: third visit, the Ironforge trip and the escort ---------------------------------------------------------------------

step
  .goto Loch Modan,37.2,47.4
  .turnin 298 >>Turn in Excavation Progress Report to Jern Hornhelm in Thelsamar
  .accept 301 >>Accept Report to Ironforge

step
  .goto Loch Modan,34.6,44.5
  .accept 255 >>Accept Mercenaries from Magistrate Bluntnose in the town hall (level 15) — the Mo'grosh ogres, after the escort

step
  .goto Loch Modan,37.3,46.5
  .optional >>WANTED: Chok'sul is a level 22 elite in the Mo'grosh cave — a group quest
  .accept 256 >>Read the WANTED poster outside the town hall and accept WANTED: Chok'sul

step
  .goto Loch Modan,33.9,51.0
  .fly Ironforge >>Fly to Ironforge with Thorgrum Borrelson

step
  .goto Ironforge,74.6,11.7
  .turnin 301 >>Turn in Report to Ironforge to Prospector Stormpike in the Hall of Explorers
  .accept 302 >>Accept Powder to Ironband

step
  .goto Ironforge,55.5,47.7
  .train >>Train new skills at your class trainer in Ironforge, sell and repair, then fly back to Thelsamar
  .fly Thelsamar

step
  .goto Loch Modan,37.2,47.4
  .turnin 302 >>Turn in Powder to Ironband to Jern Hornhelm in Thelsamar
  .accept 273 >>Accept Resupplying the Excavation

step
  .goto Loch Modan,52.2,69.3
  .turnin 273 >>Turn in Resupplying the Excavation to Huldar at the ambushed wagon on the road south-east of Thelsamar
  .accept 454 >>Accept After the Ambush — an escort along the road to the excavation (Dark Iron ambushes, lvl 16-18; keep both dwarves alive)

step
  .goto Loch Modan,52.2,69.4
  .complete 454 >>Escort Huldar and Miran with the wagon to Ironband's Excavation

step
  .goto Loch Modan,52.2,69.4
  .turnin 454 >>Turn in After the Ambush to Miran when the escort ends
  .accept 309 >>Accept Protecting the Shipment

step
  .goto Loch Modan,65.9,65.6
  .turnin 309 >>Turn in Protecting the Shipment to Prospector Ironband at the excavation

step
  .goto Loch Modan,83.5,65.5
  .turnin 271 >>Turn in Vyrin's Revenge to Daryl the Youngling at the Farstrider Lodge
  .accept 531 >>Accept Vyrin's Revenge (part 2)

step
  .goto Loch Modan,81.7,64.1
  .turnin 531 >>Turn in Vyrin's Revenge to Vyrin Swiftwind

-- North-east: the Mo'grosh Stronghold, then the dam and the Algaz pass --------------------------------------------------------------

step
  .goto Loch Modan,69.7,25.2
  .xp 18
  .complete 255,1 >>Kill 4 Mo'grosh Ogres at the Mo'grosh Stronghold, up the north-east shore of the loch (lvl 18-19 — pull them one at a time)
  .complete 255,2 >>Kill 4 Mo'grosh Enforcers there too (lvl 18-19)
  .complete 255,3 >>Kill 4 Mo'grosh Brutes around the cave further north (lvl 19-20)

step
  .goto Loch Modan,79.6,14.6
  .optional >>WANTED: Chok'sul
  .complete 256,1 >>Kill Chok'sul at the back of the Mo'grosh cave with a group (lvl 22 elite) and take his head

step
  .goto Loch Modan,34.6,44.5
  .turnin 255 >>Turn in Mercenaries to Magistrate Bluntnose in Thelsamar (hearth)

step
  .goto Loch Modan,34.6,44.5
  .optional >>WANTED: Chok'sul
  .turnin 256 >>Turn in WANTED: Chok'sul to Magistrate Bluntnose

step
  .goto Loch Modan,32.7,49.7
  .xp 19
  .accept 468 >>Accept Report to Mountaineer Rockgar from Mountaineer Kadrell (level 19) — Rockgar guards the Algaz pass in the north

step
  .goto Loch Modan,35.5,48.4
  .xp 19 >>You should be level 19 by now; if not, the Mo'grosh ogres and the excavation troggs are good XP. Sell and repair, then take the road north along the west shore to the dam

step
  .goto Loch Modan,46.0,13.6
  .accept 250 >>Accept A Dark Threat Looms from Chief Engineer Hinderweir VII at the Stonewrought Dam

step
  .goto Loch Modan,56.1,13.2
  .turnin 250 >>Find the Suspicious Barrel at the east end of the dam and turn in A Dark Threat Looms
  .accept 199 >>Accept A Dark Threat Looms (part 2) from the barrel

step
  .goto Loch Modan,46.0,13.6
  .turnin 199 >>Turn in A Dark Threat Looms to Chief Engineer Hinderweir VII
  .accept 161 >>Accept A Dark Threat Looms (part 3) — for Ashlan Stonesmirk in the Wetlands

step
  .goto Loch Modan,25.4,10.4
  .turnin 468 >>Turn in Report to Mountaineer Rockgar to Mountaineer Rockgar at the mouth of the Algaz pass, north-west of the dam
  .accept 455 >>Accept The Algaz Gauntlet — the Dragonmaw orcs in the pass, turned in at Menethil Harbor. Follow the pass north through Dun Algaz into the Wetlands
]], "Lodestar_Guides_Alliance")

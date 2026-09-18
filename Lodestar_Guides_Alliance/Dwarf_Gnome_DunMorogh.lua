-- Lodestar Guides: Alliance — Dwarf and Gnome starting zone, Dun Morogh (levels 1-12).
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Dun Morogh route (Coldridge Valley → the tunnel to
-- Kharanos and Steelgrill's Depot → the bears, boars and the Grizzled Den south of the road →
-- Brewnall Village, Gnomeregan's leper gnomes, Frostmane Hold and Shimmer Ridge → Kharanos and the
-- Thunderbrew barrel → Ironforge → Amberstill Ranch, the Gol'Bolar Quarry and the North Gate pass
-- into Loch Modan). Every quest id and position comes from the data; the order still has to be
-- verified in play (/lode record). Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance/Dwarf,Gnome 1-12: Dun Morogh
#faction Alliance
#race Dwarf,Gnome
#levels 1-12
#next Alliance 12-20: Loch Modan
#author Lodestar
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Coldridge Valley ------------------------------------------------------------------------------

step
  .goto Dun Morogh,29.9,71.2
  .accept 179 >>Accept Dwarven Outfitters from Sten Stoutarm (right where you spawn)

step
  .goto Dun Morogh,28.8,73.8
  .complete 179,1 >>Loot 8 Tough Wolf Meat from Ragged Young and Timber Wolves around the valley (lvl 1-2)

step
  .goto Dun Morogh,29.9,71.2
  .turnin 179 >>Turn in Dwarven Outfitters to Sten Stoutarm
  .accept 233 >>Accept Coldridge Valley Mail Delivery

-- Class runes and memorandums (Sten hands them out after Dwarven Outfitters) ----------------------

step
  .goto Dun Morogh,29.9,71.2
  .class Warrior
  .race Dwarf
  .accept 3106 >>Accept Simple Rune (warrior) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Warrior
  .race Gnome
  .accept 3112 >>Accept Simple Memorandum (warrior) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Paladin
  .accept 3107 >>Accept Consecrated Rune (paladin) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Hunter
  .accept 3108 >>Accept Etched Rune (hunter) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Rogue
  .race Dwarf
  .accept 3109 >>Accept Encrypted Rune (rogue) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Rogue
  .race Gnome
  .accept 3113 >>Accept Encrypted Memorandum (rogue) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Priest
  .accept 3110 >>Accept Hallowed Rune (priest) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Mage
  .accept 3114 >>Accept Glyphic Memorandum (mage) from Sten Stoutarm

step
  .goto Dun Morogh,29.9,71.2
  .class Warlock
  .accept 3115 >>Accept Tainted Memorandum (warlock) from Sten Stoutarm

step
  .goto Dun Morogh,29.7,71.3
  .accept 170 >>Accept A New Threat from Balir Frosthammer, next to Sten

step
  .goto Dun Morogh,28.8,76.4
  .complete 170,1 >>Kill 6 Rockjaw Troggs south of Anvilmar (lvl 1-2)
  .complete 170,2 >>Kill 6 Burly Rockjaw Troggs there too (lvl 2)

step
  .goto Dun Morogh,29.7,71.3
  .turnin 170 >>Turn in A New Threat to Balir Frosthammer

-- Anvilmar: class trainers ----------------------------------------------------------------------

step
  .goto Dun Morogh,28.8,67.2
  .class Warrior
  .race Dwarf
  .turnin 3106 >>Turn in Simple Rune to Thran Khorman in Anvilmar and train
  .train Thran Khorman

step
  .goto Dun Morogh,28.8,67.2
  .class Warrior
  .race Gnome
  .turnin 3112 >>Turn in Simple Memorandum to Thran Khorman in Anvilmar and train
  .train Thran Khorman

step
  .goto Dun Morogh,28.8,68.3
  .class Paladin
  .turnin 3107 >>Turn in Consecrated Rune to Bromos Grummner in Anvilmar and train
  .train Bromos Grummner

step
  .goto Dun Morogh,29.2,67.5
  .class Hunter
  .turnin 3108 >>Turn in Etched Rune to Thorgas Grimson in Anvilmar and train
  .train Thorgas Grimson

step
  .goto Dun Morogh,28.4,67.5
  .class Rogue
  .race Dwarf
  .turnin 3109 >>Turn in Encrypted Rune to Solm Hargrin in Anvilmar and train
  .train Solm Hargrin

step
  .goto Dun Morogh,28.4,67.5
  .class Rogue
  .race Gnome
  .turnin 3113 >>Turn in Encrypted Memorandum to Solm Hargrin in Anvilmar and train
  .train Solm Hargrin

step
  .goto Dun Morogh,28.6,66.4
  .class Priest
  .turnin 3110 >>Turn in Hallowed Rune to Branstock Khalder in Anvilmar and train
  .train Branstock Khalder

step
  .goto Dun Morogh,28.7,66.4
  .class Mage
  .turnin 3114 >>Turn in Glyphic Memorandum to Marryk Nurribit in Anvilmar and train
  .train Marryk Nurribit

step
  .goto Dun Morogh,28.6,66.1
  .class Warlock
  .turnin 3115 >>Turn in Tainted Memorandum to Alamar Grimm in Anvilmar and train
  .train Alamar Grimm

step
  .goto Dun Morogh,28.6,66.1
  .class Warlock
  .accept 1599 >>Accept Beginnings from Alamar Grimm — Feather Charms from the Frostmane Novices at the troll cave in the south-east

step
  .goto Dun Morogh,28.5,67.6
  .xp 3
  .accept 3361 >>Accept A Refugee's Quandary from Felix Whindlebolt, outside Anvilmar (level 3 — the troggs get you there)

-- West side: Talin, Grelin, the troll cave ---------------------------------------------------------

step
  .goto Dun Morogh,22.6,71.4
  .turnin 233 >>Turn in Coldridge Valley Mail Delivery to Talin Keeneye at the camp in the west of the valley
  .accept 234 >>Accept Coldridge Valley Mail Delivery (part 2)
  .accept 183 >>Accept The Boar Hunter

step
  .goto Dun Morogh,22.7,72.3
  .complete 183,1 >>Kill 12 Small Crag Boars around Talin's camp (lvl 3)

step
  .goto Dun Morogh,22.6,71.4
  .turnin 183 >>Turn in The Boar Hunter to Talin Keeneye

step
  .goto Dun Morogh,20.9,76.1
  .complete 3361,1 >>Pick up Felix's Box, on the ground by the trogg camp south-west of Talin

step
  .goto Dun Morogh,25.1,75.7
  .turnin 234 >>Turn in Coldridge Valley Mail Delivery to Grelin Whitebeard at his camp south of the valley
  .accept 182 >>Accept The Troll Cave

step
  .goto Dun Morogh,22.8,80.0
  .complete 3361,2 >>Pick up Felix's Chest, south-west of Grelin's camp among the troll whelps

step
  .goto Dun Morogh,26.4,79.4
  .complete 182,1 >>Kill 14 Frostmane Troll Whelps around the cave south of Grelin's camp (lvl 3-4)

step
  .goto Dun Morogh,26.3,79.3
  .complete 3361,3 >>Pick up Felix's Bucket of Bolts, by the path to the troll cave

step
  .goto Dun Morogh,25.1,75.7
  .turnin 182 >>Turn in The Troll Cave to Grelin Whitebeard
  .accept 218 >>Accept The Stolen Journal

step
  .goto Dun Morogh,30.5,79.6
  .class Warlock
  .complete 1599,1 >>Loot 4 Feather Charms from the Frostmane Novices outside and inside the troll cave (lvl 3-4)

step
  .goto Dun Morogh,30.5,80.2
  .complete 218,1 >>Kill Grik'nir the Cold at the back of the troll cave (lvl 5) and take Grelin's journal

step
  .goto Dun Morogh,25.1,75.7
  .turnin 218 >>Turn in The Stolen Journal to Grelin Whitebeard
  .accept 282 >>Accept Senir's Observations — for Mountaineer Thalos at the tunnel

step
  .goto Dun Morogh,25.0,76.0
  .xp 4
  .accept 3364 >>Accept Scalding Mornbrew Delivery from Nori Pridedrift, next to Grelin (level 4) — the brew goes cold in 5 minutes, so head straight for Anvilmar now

-- Anvilmar again, then the tunnel to Kharanos ---------------------------------------------------------

step
  .goto Dun Morogh,28.5,67.6
  .turnin 3361 >>Turn in A Refugee's Quandary to Felix Whindlebolt at Anvilmar

step
  .goto Dun Morogh,28.8,66.4
  .turnin 3364 >>Turn in Scalding Mornbrew Delivery to Durnan Furcutter inside Anvilmar (it goes cold after 5 minutes — re-take it from Nori if it did)
  .accept 3365 >>Accept Bring Back the Mug

step
  .goto Dun Morogh,28.6,66.1
  .class Warlock
  .turnin 1599 >>Turn in Beginnings to Alamar Grimm for your imp

step
  .goto Dun Morogh,28.6,66.4
  .class Priest
  .xp 5
  .accept 5626 >>Accept In Favor of the Light from Branstock Khalder (level 5) — a hand-off to Maxan Anvol in Kharanos

step
  .goto Dun Morogh,28.8,67.2
  .xp 4
  .train >>Train new skills at your class trainer in Anvilmar (level 4)

step
  .goto Dun Morogh,25.0,76.0
  .optional >>Bring Back the Mug is a hand-in back at Nori's camp, away from the tunnel — small XP for a two-minute detour
  .turnin 3365 >>Turn in Bring Back the Mug to Nori Pridedrift

step
  .goto Dun Morogh,33.5,71.8
  .turnin 282 >>Turn in Senir's Observations to Mountaineer Thalos at the mouth of the tunnel out of the valley
  .accept 420 >>Accept Senir's Observations (part 2) — for Senir Whitebeard in Kharanos

step
  .goto Dun Morogh,33.8,72.2
  .accept 2160 >>Accept Supplies to Tannok from Hands Springsprocket, next to Thalos

step
  .goto Dun Morogh,33.5,71.8
  .xp 5 >>You should be level 5 leaving Coldridge Valley; kill troll whelps or boars if not, then walk through the tunnel to Kharanos

-- Kharanos: first visit -----------------------------------------------------------------------------------

step
  .goto Dun Morogh,46.7,53.8
  .turnin 420 >>Turn in Senir's Observations to Senir Whitebeard, outside the Thunderbrew Distillery in Kharanos

step
  .goto Dun Morogh,47.2,52.2
  .turnin 2160 >>Turn in Supplies to Tannok to Tannok Frosthammer inside the distillery

step
  .goto Dun Morogh,47.4,52.5
  .hs Kharanos >>Set your hearthstone at the Thunderbrew Distillery (Innkeeper Belm)
  .buy 2894 >>Buy a Rhapsody Malt from Innkeeper Belm (50 copper) for Beer Basted Boar Ribs

step
  .goto Dun Morogh,46.8,52.4
  .xp 5
  .accept 384 >>Accept Beer Basted Boar Ribs from Ragnar Thunderbrew, outside the distillery

step
  .goto Dun Morogh,46.0,51.7
  .accept 400 >>Accept Tools for Steelgrill from Tharek Blackstone, the smith across the road

step
  .goto Dun Morogh,47.3,52.2
  .class Priest
  .turnin 5626 >>Turn in In Favor of the Light to Maxan Anvol, upstairs in the distillery
  .accept 5625 >>Accept Garments of the Light

step
  .goto Dun Morogh,45.8,54.6
  .class Priest
  .complete 5625,1 >>Cast Lesser Heal and Power Word: Fortitude on Mountaineer Dolf, south of the distillery (friendly — just buff and heal him)

step
  .goto Dun Morogh,47.3,52.2
  .class Priest
  .turnin 5625 >>Turn in Garments of the Light to Maxan Anvol

step
  .goto Dun Morogh,47.4,52.6
  .class Warrior
  .train Granis Swiftaxe >>Train at Granis Swiftaxe, the warrior trainer in the distillery

step
  .goto Dun Morogh,47.6,52.1
  .class Paladin
  .train Azar Stronghammer >>Train at Azar Stronghammer, the paladin trainer in the distillery

step
  .goto Dun Morogh,45.8,53.0
  .class Hunter
  .train Grif Wildheart >>Train at Grif Wildheart, the hunter trainer in the house south of the distillery

step
  .goto Dun Morogh,47.6,52.6
  .class Rogue
  .train Hogral Bakkan >>Train at Hogral Bakkan, the rogue trainer in the distillery

step
  .goto Dun Morogh,47.3,52.2
  .class Priest
  .train Maxan Anvol >>Train at Maxan Anvol, upstairs in the distillery

step
  .goto Dun Morogh,47.5,52.1
  .class Mage
  .train Magis Sparkmantle >>Train at Magis Sparkmantle, the mage trainer upstairs in the distillery

step
  .goto Dun Morogh,47.3,53.7
  .class Warlock
  .train Gimrizz Shadowcog >>Train at Gimrizz Shadowcog, the warlock trainer behind the distillery

-- Steelgrill's Depot and the south loop -----------------------------------------------------------------------

step
  .goto Dun Morogh,50.4,49.1
  .turnin 400 >>Turn in Tools for Steelgrill to Beldin Steelgrill at Steelgrill's Depot, north-east of Kharanos

step
  .goto Dun Morogh,49.4,48.4
  .accept 317 >>Accept Stocking Jetsteam from Pilot Bellowfiz at the depot

step
  .goto Dun Morogh,49.6,48.6
  .accept 313 >>Accept The Grizzled Den from Pilot Stonegear

step
  .goto Dun Morogh,50.1,49.4
  .accept 5541 >>Accept Ammo for Rumbleshot from Loslor Rudge

step
  .goto Dun Morogh,44.7,55.4
  .complete 317,2 >>Loot 4 Thick Bear Fur from Young Black Bears south of Kharanos (lvl 5-6)

step
  .goto Dun Morogh,44.2,59.4
  .complete 317,1 >>Loot 8 Chunks of Boar Meat from Crag Boars in the same woods (lvl 5-6)
  .complete 384,1 >>Loot 6 Crag Boar Ribs from them too

step
  .goto Dun Morogh,44.1,56.9
  .complete 5541,1 >>Pick up Rumbleshot's Ammo from the Ammo Crate by the wrecked cart, south-west of Kharanos

step
  .goto Dun Morogh,40.7,65.1
  .turnin 5541 >>Turn in Ammo for Rumbleshot to Hegnar Rumbleshot, at the hut on the road south-west

step
  .goto Dun Morogh,41.8,54.5
  .complete 313,1 >>Loot 8 Wendigo Manes from the Young Wendigos and Wendigos in the Grizzled Den, the cave west of Kharanos (lvl 5-7)

step
  .goto Dun Morogh,46.8,52.4
  .turnin 384 >>Turn in Beer Basted Boar Ribs to Ragnar Thunderbrew in Kharanos

step
  .goto Dun Morogh,46.7,53.8
  .xp 7
  .accept 287 >>Accept Frostmane Hold from Senir Whitebeard (level 7)

step
  .goto Dun Morogh,49.4,48.4
  .turnin 317 >>Turn in Stocking Jetsteam to Pilot Bellowfiz at Steelgrill's Depot
  .accept 318 >>Accept Evershine — for Rejold Barleybrew in Brewnall Village

step
  .goto Dun Morogh,49.6,48.6
  .turnin 313 >>Turn in The Grizzled Den to Pilot Stonegear

step
  .goto Dun Morogh,45.8,49.4
  .accept 412 >>Accept Operation Recombobulation from Razzle Sprysprocket, by the road north of Kharanos

-- Brewnall Village and the west --------------------------------------------------------------------------------

step
  .goto Dun Morogh,30.2,45.7
  .turnin 318 >>Turn in Evershine to Rejold Barleybrew in Brewnall Village, west along the road
  .accept 319 >>Accept A Favor for Evershine
  .accept 315 >>Accept The Perfect Stout

step
  .goto Dun Morogh,30.2,45.5
  .accept 310 >>Accept Bitter Rivals from Marleth Barleybrew, next to Rejold — the barrel is back in Kharanos

step
  .goto Dun Morogh,26.1,40.7
  .complete 412,1 >>Loot 8 Restabilization Cogs from Leper Gnomes around the entrance to Gnomeregan, north-west of Brewnall (lvl 8-10)
  .complete 412,2 >>Loot 8 Gyromechanic Gears from them too

step
  .goto Dun Morogh,25.4,50.9
  .complete 287,1 >>Kill 5 Frostmane Headhunters around Frostmane Hold, south-west of Brewnall (lvl 8-9)

step
  .goto Dun Morogh,21.3,54.3
  .complete 287,2 >>Walk into Frostmane Hold, the cave at the west end of the valley

step
  .goto Dun Morogh,34.6,51.7
  .accept 312 >>Accept Tundra MacGrann's Stolen Stash from Tundra MacGrann at the hut south-east of Brewnall

step
  .goto Dun Morogh,38.5,53.9
  .complete 312,1 >>Take MacGrann's Dried Meats from the Meat Locker in the hollow east of the hut — wait for Old Icebeard (lvl 11) to walk away from it

step
  .goto Dun Morogh,34.6,51.7
  .turnin 312 >>Turn in Tundra MacGrann's Stolen Stash to Tundra MacGrann

step
  .goto Dun Morogh,38.5,43.5
  .complete 319,2 >>Kill 6 Ice Claw Bears in the hills north of the lake, between Brewnall and Kharanos (lvl 7-8)
  .complete 319,3 >>Kill 6 Snow Leopards — they roam the same hills (lvl 7-8)

step
  .goto Dun Morogh,42.5,36.4
  .complete 315,1 >>Loot 6 Shimmerweed from the Shimmerweed Baskets at the Frostmane camp on Shimmer Ridge, north of the road (Frostmane Seers, lvl 8-9)

step
  .goto Dun Morogh,45.3,42.6
  .complete 319,1 >>Kill 6 Elder Crag Boars in the woods north of the road, east of Shimmer Ridge (lvl 7-8)

step
  .goto Dun Morogh,30.2,45.7
  .turnin 319 >>Turn in A Favor for Evershine to Rejold Barleybrew in Brewnall
  .turnin 315 >>Turn in The Perfect Stout
  .accept 320 >>Accept Return to Bellowfiz

-- Kharanos: the Thunderbrew barrel, then Steelgrill's Depot again -----------------------------------------------

step
  .goto Dun Morogh,46.7,53.8
  .turnin 287 >>Turn in Frostmane Hold to Senir Whitebeard in Kharanos (hearth to Kharanos)
  .accept 291 >>Accept The Reports — for Senator Barin Redstone in Ironforge

step
  .goto Dun Morogh,47.7,52.7
  .turnin 310 >>Turn in Bitter Rivals at the Guarded Thunder Ale Barrel inside the distillery, behind Jarven Thunderbrew
  .accept 403 >>Accept Guarded Thunderbrew Barrel from the barrel

step
  .goto Dun Morogh,47.4,52.5
  .buy 2686 >>Buy a Thunder Ale from Innkeeper Belm (50 copper)

step
  .goto Dun Morogh,47.7,52.7
  .turnin 403 >>Turn in Guarded Thunderbrew Barrel at the barrel
  .accept 308 >>Accept Distracting Jarven from Jarven Thunderbrew

step
  .goto Dun Morogh,47.6,52.7
  .turnin 308 >>Give Jarven Thunderbrew the Thunder Ale and turn in Distracting Jarven

step
  .goto Dun Morogh,47.7,52.7
  .accept 311 >>Accept Return to Marleth from the now Unguarded Thunder Ale Barrel

step
  .goto Dun Morogh,47.4,52.5
  .vendor >>Sell junk at the vendors in the distillery and buy food and water

step
  .goto Dun Morogh,49.4,48.4
  .turnin 320 >>Turn in Return to Bellowfiz to Pilot Bellowfiz at Steelgrill's Depot
  .xp 8
  .accept 415 >>Accept Rejold's New Brew (level 8)

step
  .goto Dun Morogh,45.8,49.4
  .turnin 412 >>Turn in Operation Recombobulation to Razzle Sprysprocket

step
  .goto Dun Morogh,30.2,45.7
  .turnin 415 >>Turn in Rejold's New Brew to Rejold Barleybrew in Brewnall
  .accept 413 >>Accept Shimmer Stout — for Mountaineer Barleybrew at the North Gate pass, on the way to Loch Modan

step
  .goto Dun Morogh,30.2,45.5
  .turnin 311 >>Turn in Return to Marleth to Marleth Barleybrew

step
  .goto Dun Morogh,47.4,52.5
  .xp 10 >>Hearth to Kharanos. You should be level 10 by now; if not, the Frostmane trolls on Shimmer Ridge north of the road are quick XP

step
  .goto Dun Morogh,47.4,52.6
  .class Warrior
  .accept 1679 >>Accept Muren Stormpike from Granis Swiftaxe in the distillery (level 10) — a hand-off to the Military Ward in Ironforge

step
  .goto Dun Morogh,47.5,52.1
  .class Mage
  .accept 1879 >>Accept Speak with Bink from Magis Sparkmantle, upstairs in the distillery (level 10) — a hand-off to Ironforge

step
  .goto Dun Morogh,47.6,52.6
  .class Rogue
  .accept 2218 >>Accept Road to Salvation from Hogral Bakkan in the distillery (level 10) — a hand-off to Ironforge

step
  .goto Dun Morogh,47.4,52.5
  .train >>Train new skills at your class trainer in Kharanos, then take the road north to Ironforge

-- Ironforge -----------------------------------------------------------------------------------------------------

step
  .goto Ironforge,39.5,57.5
  .turnin 291 >>Turn in The Reports to Senator Barin Redstone in the High Seat, Ironforge

step
  .goto Ironforge,55.5,47.7
  .text >>Talk to Gryth Thurden, the gryphon master in the Great Forge, to learn the Ironforge flight path

step
  .goto Ironforge,70.8,90.3
  .class Warrior
  .turnin 1679 >>Turn in Muren Stormpike to Muren Stormpike in the Military Ward (he starts the Bartleby-style chain for a level 10 weapon; do it next time you are here)

step
  .goto Ironforge,65.9,88.4
  .class Warrior
  .train Bilban Tosslespanner >>Train at Bilban Tosslespanner in the Military Ward

step
  .goto Ironforge,23.1,6.1
  .class Paladin
  .train Brandur Ironhammer >>Train at Brandur Ironhammer in the Hall of Mysteries

step
  .goto Ironforge,27.2,8.3
  .class Mage
  .turnin 1879 >>Turn in Speak with Bink to Bink in the Hall of Mysteries
  .train Bink

step
  .goto Ironforge,52.0,14.8
  .class Rogue
  .turnin 2218 >>Turn in Road to Salvation to Hulfdan Blackbeard in the Forlorn Cavern

step
  .goto Ironforge,52.0,14.8
  .class Rogue
  .optional >>Simple Subterfugin': Onin MacHammar stands at the Gnomeregan entrance in the far west of Dun Morogh — a long loop for a lockpicking lesson; the next time you hearth to Kharanos is a better moment
  .accept 2238 >>Accept Simple Subterfugin' from Hulfdan Blackbeard

step
  .goto Dun Morogh,25.2,44.5
  .class Rogue
  .optional >>Simple Subterfugin'
  .turnin 2238 >>Turn in Simple Subterfugin' to Onin MacHammar at the Gnomeregan entrance, north-west of Brewnall
  .accept 2239 >>Accept Onin's Report

step
  .goto Ironforge,52.0,14.8
  .class Rogue
  .optional >>Simple Subterfugin'
  .turnin 2239 >>Turn in Onin's Report to Hulfdan Blackbeard in the Forlorn Cavern

step
  .goto Ironforge,51.5,15.3
  .class Rogue
  .train Fenthwick >>Train at Fenthwick in the Forlorn Cavern

step
  .goto Ironforge,24.4,9.2
  .class Priest
  .train Braenna Flintcrag >>Train at Braenna Flintcrag in the Hall of Mysteries

step
  .goto Ironforge,50.3,5.7
  .class Warlock
  .train Briarthorn >>Train at Briarthorn in the Forlorn Cavern

-- Hunter: the pet quests (level 10) -----------------------------------------------------------------------------------

step
  .goto Ironforge,70.9,83.6
  .class Hunter
  .xp 10
  .accept 6074 >>Accept The Hunter's Path from Olmin Burningbeard in the Military Ward (level 10) — the pet quests are at Grif in Kharanos

step
  .goto Ironforge,69.9,82.9
  .class Hunter
  .train Regnus Thundergranite >>Train at Regnus Thundergranite in the Military Ward

step
  .goto Dun Morogh,45.8,53.0
  .class Hunter
  .turnin 6074 >>Turn in The Hunter's Path to Grif Wildheart in Kharanos (hearth)
  .accept 6064 >>Accept Taming the Beast (Large Crag Boar)

step
  .goto Dun Morogh,48.1,47.2
  .class Hunter
  .complete 6064 >>Use the Taming Rod on a Large Crag Boar around Steelgrill's Depot (lvl 6-7) and keep it alive until the channel ends

step
  .goto Dun Morogh,45.8,53.0
  .class Hunter
  .turnin 6064 >>Turn in Taming the Beast to Grif Wildheart
  .accept 6084 >>Accept Taming the Beast (Snow Leopard)

step
  .goto Dun Morogh,48.3,56.5
  .class Hunter
  .complete 6084 >>Use the Taming Rod on a Snow Leopard south of Kharanos (lvl 7-8)

step
  .goto Dun Morogh,45.8,53.0
  .class Hunter
  .turnin 6084 >>Turn in Taming the Beast to Grif Wildheart
  .accept 6085 >>Accept Taming the Beast (Ice Claw Bear)

step
  .goto Dun Morogh,46.3,63.3
  .class Hunter
  .complete 6085 >>Use the Taming Rod on an Ice Claw Bear in the woods south of Kharanos (lvl 7-8)

step
  .goto Dun Morogh,45.8,53.0
  .class Hunter
  .turnin 6085 >>Turn in Taming the Beast to Grif Wildheart
  .accept 6086 >>Accept Training the Beast — Belia Thundergranite in Ironforge teaches you to tame for real

step
  .goto Ironforge,70.9,85.8
  .class Hunter
  .turnin 6086 >>Turn in Training the Beast to Belia Thundergranite in the Military Ward (walk back up the road to Ironforge)

-- Paladin: the Tome of Divinity (Redemption, level 12) -------------------------------------------------------------------
-- A paladin who is not 12 yet can leave this for the Ironforge visit in the Loch Modan guide: Tiza keeps the quest.

step
  .goto Ironforge,27.6,12.2
  .class Paladin
  .xp 12
  .accept 1645 >>Accept The Tome of Divinity from Tiza Battleforge in the Hall of Mysteries (level 12 — the Redemption chain; the Rockjaw troggs at the Gol'Bolar Quarry get you there if you are short)

step
  .goto Ironforge,27.6,12.2
  .class Paladin
  .turnin 1645 >>Turn in The Tome of Divinity to Tiza Battleforge — she hands you the Tome itself

step
  .goto Ironforge,27.6,12.2
  .class Paladin
  .item 6916
  .accept 1646 >>Read the Tome of Divinity in your bags and accept The Tome of Divinity

step
  .goto Ironforge,27.6,12.2
  .class Paladin
  .turnin 1646 >>Turn in The Tome of Divinity to Tiza Battleforge
  .accept 1647 >>Accept The Tome of Divinity — John Turner in the Commons

step
  .goto Ironforge,23.3,61.9
  .class Paladin
  .turnin 1647 >>Turn in The Tome of Divinity to John Turner in the Commons, by the bank
  .accept 1648 >>Accept The Tome of Divinity — he wants 10 Linen Cloth (you have some by now; the auction house is across the way if not)

step
  .goto Ironforge,23.3,61.9
  .class Paladin
  .turnin 1648 >>Turn in The Tome of Divinity to John Turner
  .accept 1778 >>Accept The Tome of Divinity

step
  .goto Ironforge,27.6,12.2
  .class Paladin
  .turnin 1778 >>Turn in The Tome of Divinity to Tiza Battleforge in the Hall of Mysteries
  .accept 1779 >>Accept The Tome of Divinity

step
  .goto Ironforge,23.5,8.3
  .class Paladin
  .turnin 1779 >>Turn in The Tome of Divinity to Muiredon Battleforge, next to Tiza
  .accept 1783 >>Accept The Tome of Divinity — Narm Faulk lies south-east of the Gol'Bolar Quarry, on the way east

step
  .goto Ironforge,18.2,51.4
  .xp 10 >>Sell and repair in the Commons. Leave Ironforge by the front gate and follow the road east: Amberstill Ranch first, then the Gol'Bolar Quarry

-- East: Amberstill Ranch, the Gol'Bolar Quarry, the North Gate pass -----------------------------------------------------

step
  .goto Dun Morogh,63.1,49.8
  .accept 314 >>Accept Protecting the Herd from Rudra Amberstill at Amberstill Ranch, east of Ironforge along the road

step
  .goto Dun Morogh,62.6,46.0
  .complete 314,1 >>Kill Vagash in the cave up the hill north of the ranch (lvl 11 — pull him out of the cave) and take his fang

step
  .goto Dun Morogh,63.1,49.8
  .turnin 314 >>Turn in Protecting the Herd to Rudra Amberstill

step
  .goto Dun Morogh,68.7,56.0
  .accept 433 >>Accept The Public Servant from Senator Mehr Stonehallow at the Gol'Bolar Quarry, east of the ranch

step
  .goto Dun Morogh,69.1,56.3
  .accept 432 >>Accept Those Blasted Troggs! from Foreman Stonebrow, next to the senator

step
  .goto Dun Morogh,71.0,55.1
  .complete 432,1 >>Kill 10 Rockjaw Skullthumpers in the quarry (lvl 8-9)

step
  .goto Dun Morogh,72.8,54.0
  .complete 433,1 >>Kill 10 Rockjaw Bonesnappers deeper in the quarry and the cave at its east end (lvl 9-10)

step
  .goto Dun Morogh,69.1,56.3
  .turnin 432 >>Turn in Those Blasted Troggs! to Foreman Stonebrow

step
  .goto Dun Morogh,68.7,56.0
  .turnin 433 >>Turn in The Public Servant to Senator Mehr Stonehallow

step
  .goto Dun Morogh,78.3,58.1
  .class Paladin
  .turnin 1783 >>Turn in The Tome of Divinity to Narm Faulk, lying at the Dark Iron camp south-east of the quarry (Dark Iron Spies, lvl 9-10)
  .accept 1784 >>Accept The Tome of Divinity

step
  .goto Dun Morogh,77.4,61.3
  .class Paladin
  .complete 1784,1 >>Loot a Dark Iron Script from the Dark Iron Spies around the camp, then use the Symbol of Life on Narm Faulk to revive him — the turn-in is in Ironforge, on the Loch Modan guide's flight there

step
  .goto Dun Morogh,83.9,39.2
  .xp 8
  .accept 419 >>Accept The Lost Pilot from Pilot Hammerfoot, at the crashed flying machine north of the road to the North Gate

step
  .goto Dun Morogh,79.7,36.2
  .turnin 419 >>Find the Dwarven Corpse in the snow west of Hammerfoot and turn in The Lost Pilot
  .accept 417 >>Accept A Pilot's Revenge from the corpse

step
  .goto Dun Morogh,78.3,37.8
  .complete 417,1 >>Kill Mangeclaw, the bear prowling around the corpse (lvl 11) and take his claw

step
  .goto Dun Morogh,83.9,39.2
  .turnin 417 >>Turn in A Pilot's Revenge to Pilot Hammerfoot

step
  .goto Dun Morogh,86.3,48.8
  .turnin 413 >>Turn in Shimmer Stout to Mountaineer Barleybrew at the North Gate Outpost, where the road turns into the pass
  .accept 414 >>Accept Stout to Kadrell — Mountaineer Kadrell in Thelsamar, Loch Modan

step
  .goto Dun Morogh,86.3,48.8
  .xp 11 >>Dun Morogh's quests run out around level 11; Loch Modan's start at 10, so head out now (the Rockjaw troggs in the quarry are good XP if you want 12 first). Follow the pass east and south through the South Gate into Loch Modan

step
  .zone Loch Modan >>Follow the pass through the South Gate Outpost into Loch Modan — Thelsamar lies down the road to the south-east
]], "Lodestar_Guides_Alliance")

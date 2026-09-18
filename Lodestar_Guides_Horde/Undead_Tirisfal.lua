-- Lodestar Guides: Horde — Tirisfal Glades (levels 5-12), Brill and the surrounding loops.
--
-- Quest ids and positions come from the built-in Vanilla database (Data/Vanilla.lua). Order follows
-- the classic Brill loops: west (Darkhounds, zombies, Garren's Haunt), north-west (Scarlet camp,
-- murlocs, Agamand Mills), then south and east (Scarlet Crusade, Balnir, Venomweb Vale), with an
-- Undercity trip for the Prodigal Lich chain at the end. Forever-only quests are not in here yet.
--
-- Speed run vs completionist: steps marked .optional (the Calvin duel, Rear Guard Patrol, The Family
-- Crypt, Captain Melrache, the Prodigal Lich / Gunther's Retreat chain, professions, camp and cooking)
-- are skipped unless "Completionist" is on (right-click the guide window, or /lode guide completionist).
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde/Undead 5-12: Tirisfal Glades
#faction Horde
#race Undead
#levels 5-12
#next Horde 12-20: Silverpine Forest
#author Lodestar
#note Positions from the Vanilla database. Forever-only quests are not in this route yet.

-- Road to Brill ----------------------------------------------------------------------------------

step
  .goto Tirisfal Glades,38.2,56.8
  .accept 8 >>Accept A Rogue's Deal from Calvin Montague on the road east of Deathknell

step
  .goto Tirisfal Glades,40.9,54.2
  .accept 365 >>Accept Fields of Grief from Deathguard Simmer

step
  .goto Tirisfal Glades,43.1,54.7
  .accept 5481 >>Accept Gordo's Task from Gordo

step
  .goto Tirisfal Glades,44.5,54.8
  .complete 365,1 >>Pick 10 Tirisfal Pumpkins in the fields along the road (Solliden Farmstead)

step
  .goto Tirisfal Glades,48.7,54.9
  .complete 5481,1 >>Gather 6 Gloom Weed — glowing plants beside the road to Brill

-- Brill: first visit ----------------------------------------------------------------------------

step
  .goto Tirisfal Glades,60.6,51.8
  .turnin 383 >>Turn in Vital Intelligence to Executor Zygand in Brill
  .accept 427 >>Accept At War With The Scarlet Crusade

step
  .goto Tirisfal Glades,59.4,52.4
  .turnin 365 >>Turn in Fields of Grief to Apothecary Johaan
  .accept 407 >>Accept Fields of Grief (part 2)
  .accept 367 >>Accept A New Plague

step
  .goto Tirisfal Glades,62.0,51.3
  .turnin 407 >>Turn in Fields of Grief to the Captured Scarlet Zealot in the cage next to the town hall

step
  .goto Tirisfal Glades,61.7,52.0
  .turnin 8 >>Turn in A Rogue's Deal to Innkeeper Renee
  .hs Brill >>Set your hearthstone at the Brill inn

step
  .goto Tirisfal Glades,61.7,52.0
  .optional >>Forever camp and cooking buffs — skip on a speed run
  .camp >>Set up camp at the inn's fire before heading out (Forever camp buff)
  .cook >>Cook the meat you have looted for the well-fed XP buff

step
  .goto Tirisfal Glades,57.4,48.8
  .turnin 5481 >>Turn in Gordo's Task to Junior Apothecary Holland (north end of Brill)
  .accept 5482 >>Accept Doom Weed

step
  .goto Tirisfal Glades,58.2,51.4
  .accept 404 >>Accept A Putrid Task from Deathguard Dillinger

step
  .goto Tirisfal Glades,61.3,50.8
  .accept 358 >>Accept Graverobbers from Magistrate Sevren in the town hall

-- Class trainers in Brill (the guide window also flags "New spells available" on its own)

step
  .goto Tirisfal Glades,61.9,52.5
  .class Warrior
  .train Austil de Mon >>Train new skills at Austil de Mon, the warrior trainer by the inn

step
  .goto Tirisfal Glades,61.8,52.0
  .class Rogue
  .train Marion Call >>Train new skills at Marion Call, the rogue trainer at the inn

step
  .goto Tirisfal Glades,61.6,52.2
  .class Priest
  .train Dark Cleric Beryl >>Train new skills at Dark Cleric Beryl, the priest trainer at the inn

step
  .goto Tirisfal Glades,62.0,52.5
  .class Mage
  .train Cain Firesong >>Train new skills at Cain Firesong, the mage trainer by the inn

step
  .goto Tirisfal Glades,61.6,52.4
  .class Warlock
  .train Rupert Boch >>Train new skills at Rupert Boch, the warlock trainer at the inn

step
  .goto Tirisfal Glades,61.7,52.3
  .class Paladin
  .train Shan Stillwell >>Train new skills at Shan Stillwell, the paladin trainer in Brill (new on Forever — look around the inn)

step
  .goto Tirisfal Glades,61.0,52.4
  .vendor >>Sell junk to Abigail Shiel (trade supplies) next to the inn

step
  .goto Tirisfal Glades,61.0,52.4
  .optional >>Professions cost time early; a speed run skips them
  .profession Skinning,Herbalism >>Optional: learn Skinning and Herbalism. The trainers are in the Undercity (Killian Hagey in the Rogues' Quarter, Martha Alliestar in the Apothecarium) — click Next to pick them up on the Undercity trip later

-- West loop: Darkhounds, zombies, Garren's Haunt ------------------------------------------------

step
  .goto Tirisfal Glades,52.9,52.8
  .complete 404,1 >>Loot 7 Putrid Claws from Rotting Dead and Ravaged Corpses west of Brill (lvl 5-7)
  .complete 367,1 >>Collect 5 Darkhound Blood from Decrepit Darkhounds around the same fields (lvl 5-6)

step
  .goto Tirisfal Glades,56.9,39.9
  .complete 5482,1 >>Gather 6 Doom Weed around Garren's Haunt (north of Brill)

step
  .goto Tirisfal Glades,58.8,38.5
  .complete 358,1 >>Kill 8 Rot Hide Mongrels at Garren's Haunt (lvl 7-8)
  .complete 358,2 >>Kill 8 Rot Hide Graverobbers (lvl 6-7)
  .complete 358,3 >>Loot 5 Embalming Ichor from the Rot Hide gnolls

step
  .goto Tirisfal Glades,60.7,51.5
  .xp 6
  .accept 398 >>Accept Wanted: Maggot Eye from the poster by the town hall once you are level 6 (grab it now if you are)

step
  .goto Tirisfal Glades,58.7,30.8
  .complete 398,1 >>Kill Maggot Eye in the hut at the north end of Garren's Haunt (lvl 10 — pull him alone) and loot his paw

-- Brill: second visit ---------------------------------------------------------------------------

step
  .goto Tirisfal Glades,57.4,48.8
  .turnin 5482 >>Turn in Doom Weed to Junior Apothecary Holland

step
  .goto Tirisfal Glades,58.2,51.4
  .turnin 404 >>Turn in A Putrid Task to Deathguard Dillinger
  .accept 426 >>Accept The Mills Overrun

step
  .goto Tirisfal Glades,59.4,52.4
  .turnin 367 >>Turn in A New Plague to Apothecary Johaan
  .accept 368 >>Accept A New Plague (part 2)

step
  .goto Tirisfal Glades,60.6,51.8
  .turnin 398 >>Turn in Wanted: Maggot Eye to Executor Zygand

step
  .goto Tirisfal Glades,61.3,50.8
  .turnin 358 >>Turn in Graverobbers to Magistrate Sevren
  .accept 359 >>Accept Forsaken Duties

step
  .goto Tirisfal Glades,61.3,50.8
  .optional >>Starts the Undercity / Gunther's Retreat chain at the end of the guide
  .accept 405 >>Accept The Prodigal Lich from Magistrate Sevren (for the Undercity trip later)

step
  .goto Tirisfal Glades,61.7,52.3
  .xp 7
  .accept 354 >>Accept Deaths in the Family from Coleman Farthing at the inn (level 7)
  .accept 362 >>Accept The Haunted Mills
  .accept 355 >>Accept Speak with Sevren

step
  .goto Tirisfal Glades,61.9,52.7
  .accept 375 >>Accept The Chill of Death from Gretchen Dedmar

step
  .goto Tirisfal Glades,61.3,50.8
  .turnin 355 >>Turn in Speak with Sevren to Magistrate Sevren

-- North-west loop: Calvin, Scarlet camp, murlocs, Agamand Mills ---------------------------------

step
  .goto Tirisfal Glades,51.4,49.5
  .complete 375,2 >>Loot 5 Duskbat Pelts from Greater Duskbats west of Brill (lvl 6-7); the Coarse Thread comes from a vendor in Brill later

step
  .goto Tirisfal Glades,38.2,56.8
  .optional >>A duel for a few silver and little XP — skip on a speed run
  .accept 590 >>Accept A Rogue's Deal from Calvin Montague

step
  .goto Tirisfal Glades,38.2,56.8
  .optional >>A duel for a few silver and little XP — skip on a speed run
  .complete 590 >>Beat Calvin Montague in a duel (lvl 5)
  .turnin 590 >>Turn in A Rogue's Deal to Calvin

step
  .goto Tirisfal Glades,32.8,48.3
  .complete 427,1 >>Kill 10 Scarlet Warriors at the Scarlet camp west of the lake (lvl 6-7)

step
  .goto Tirisfal Glades,36.2,39.2
  .complete 368,1 >>Loot 5 Vile Fin Scales from the Vile Fin murlocs on the lake shore (lvl 7-9)

step
  .goto Tirisfal Glades,47.3,40.8
  .complete 362,1 >>Kill Devlin Agamand at the south end of Agamand Mills (lvl 9) and loot his remains

step
  .goto Tirisfal Glades,45.8,40.4
  .complete 426,1 >>Loot 5 Notched Ribs from Rattlecage and Cracked Skull Soldiers in Agamand Mills (lvl 6-9)
  .complete 426,2 >>Loot 3 Blackened Skulls from Darkeye Bonecasters (lvl 7-8)

step
  .goto Tirisfal Glades,49.7,36.3
  .complete 354,1 >>Kill Nissa Agamand at the mill (lvl 10) for her remains

step
  .goto Tirisfal Glades,44.0,33.6
  .complete 354,3 >>Kill Thurman Agamand on the west side (lvl 10) for his remains

step
  .goto Tirisfal Glades,46.7,29.3
  .complete 354,2 >>Kill Gregor Agamand at the north end (lvl 10) for his remains

-- Brill: third visit ----------------------------------------------------------------------------

step
  .goto Tirisfal Glades,61.7,52.3
  .turnin 354 >>Turn in Deaths in the Family to Coleman Farthing
  .turnin 362 >>Turn in The Haunted Mills

step
  .goto Tirisfal Glades,58.2,51.4
  .turnin 426 >>Turn in The Mills Overrun to Deathguard Dillinger

step
  .goto Tirisfal Glades,59.4,52.4
  .turnin 368 >>Turn in A New Plague to Apothecary Johaan
  .accept 369 >>Accept A New Plague (part 3)

step
  .goto Tirisfal Glades,60.6,51.8
  .turnin 427 >>Turn in At War With The Scarlet Crusade to Executor Zygand
  .accept 370 >>Accept At War With The Scarlet Crusade (part 2)

step
  .goto Tirisfal Glades,60.9,52.0
  .accept 374 >>Accept Proof of Demise from Deathguard Burgess (Scarlet rings drop from any Scarlet Crusader)

step
  .goto Tirisfal Glades,61.3,50.8
  .train >>Train, sell and repair in Brill before the long loop
  .repair

-- South then east: Scarlet Crusade, Balnir Farmstead, Venomweb Vale -----------------------------

step
  .goto Tirisfal Glades,50.2,67.0
  .complete 370,1 >>Kill 8 Scarlet Missionaries at the Scarlet camp south-west of Brill (lvl 7-8)

step
  .goto Tirisfal Glades,51.2,67.8
  .complete 370,3 >>Kill Captain Perrine in the tent (lvl 9)

step
  .goto Tirisfal Glades,65.5,60.3
  .turnin 359 >>Turn in Forsaken Duties to Deathguard Linnea on the road south-east of Brill
  .accept 360 >>Accept Return to the Magistrate

step
  .goto Tirisfal Glades,65.5,60.3
  .optional >>20 kills at Balnir Farmstead for one turn-in — decent XP, but off the fast line
  .accept 356 >>Accept Rear Guard Patrol from Deathguard Linnea

step
  .goto Tirisfal Glades,70.2,53.7
  .complete 375,2 >>Finish the Duskbat Pelts on Vampiric Duskbats east of Brill if you still need some (lvl 8-9)

step
  .goto Tirisfal Glades,76.1,61.1
  .optional >>Rear Guard Patrol
  .complete 356,1 >>Kill 10 Bleeding Horrors at the Balnir Farmstead (lvl 9-10)
  .complete 356,2 >>Kill 10 Wandering Spirits (lvl 10-11)

step
  .goto Tirisfal Glades,76.2,55.2
  .complete 370,2 >>Kill 8 Scarlet Zealots on the road north of Balnir (lvl 8-9)
  .complete 374,1 >>Loot 8 Scarlet Insignia Rings from any Scarlet Crusaders

step
  .goto Tirisfal Glades,86.0,52.5
  .complete 369,1 >>Loot 5 Vicious Night Web Spider Venom in Venomweb Vale, far east (lvl 9-10)

step
  .goto Tirisfal Glades,65.5,60.3
  .optional >>Rear Guard Patrol
  .turnin 356 >>Turn in Rear Guard Patrol to Deathguard Linnea

-- Brill: fourth visit ---------------------------------------------------------------------------

step
  .goto Tirisfal Glades,61.3,50.8
  .turnin 360 >>Turn in Return to the Magistrate to Magistrate Sevren

step
  .goto Tirisfal Glades,60.6,51.8
  .turnin 370 >>Turn in At War With The Scarlet Crusade to Executor Zygand
  .accept 371 >>Accept At War With The Scarlet Crusade (part 3)

step
  .goto Tirisfal Glades,60.9,52.0
  .turnin 374 >>Turn in Proof of Demise to Deathguard Burgess

step
  .goto Tirisfal Glades,59.4,52.4
  .turnin 369 >>Turn in A New Plague to Apothecary Johaan
  .accept 492 >>Accept A New Plague (part 4)

step
  .goto Tirisfal Glades,61.9,51.4
  .turnin 492 >>Turn in A New Plague to the Captured Mountaineer in the cage

step
  .goto Tirisfal Glades,61.0,52.4
  .buy 2320,1 >>Buy Coarse Thread from Abigail Shiel, the trade supplier by the inn (for The Chill of Death)

step
  .goto Tirisfal Glades,61.9,52.7
  .turnin 375 >>Turn in The Chill of Death to Gretchen Dedmar

-- East again: Scarlet Friars and Captain Vachon --------------------------------------------------

step
  .goto Tirisfal Glades,78.8,56.1
  .complete 371,2 >>Kill Captain Vachon at the Scarlet camp north of Balnir (lvl 11)

step
  .goto Tirisfal Glades,86.6,44.9
  .complete 371,1 >>Kill 8 Scarlet Friars on the road toward the Monastery (lvl 9-10)

step
  .goto Tirisfal Glades,60.6,51.8
  .turnin 371 >>Turn in At War With The Scarlet Crusade to Executor Zygand (hearth to Brill)

step
  .goto Tirisfal Glades,60.6,51.8
  .optional >>Captain Melrache (lvl 12) sits in the far north-east; do it on the way to the Monastery or with a group
  .accept 372 >>Accept At War With The Scarlet Crusade (part 4) from Executor Zygand — Captain Melrache, for later

-- Undercity and Gunther's Retreat: the Prodigal Lich (completionist) --------------------------------
-- Two Undercity round trips and an island loop for four turn-ins; a speed run skips the whole chain.

step
  .goto Tirisfal Glades,65.7,68.8
  .optional >>Undercity trip: the Prodigal Lich chain
  .turnin 405 >>Turn in The Prodigal Lich to Bethor Iceshard in the Undercity (Magic Quarter)
  .accept 357 >>Accept The Lich's Identity

step
  .goto Tirisfal Glades,65.7,68.8
  .optional >>Undercity trip
  .train >>Train at your class trainer in the Undercity while you are here

step
  .goto Undercity,70.2,59.2
  .optional >>Undercity trip: professions
  .profession Skinning,Herbalism >>Learn Skinning from Killian Hagey (Rogues' Quarter) and Herbalism from Martha Alliestar (Apothecarium) while you are in the Undercity

step
  .goto Tirisfal Glades,68.0,42.1
  .optional >>Gunther's Retreat chain
  .complete 357,1 >>Pick up The Lich's Spellbook from Gunther's Books on the island north-east of Brill (Gunther's Retreat)

step
  .goto Tirisfal Glades,65.7,68.8
  .optional >>Gunther's Retreat chain
  .turnin 357 >>Turn in The Lich's Identity to Bethor Iceshard
  .accept 366 >>Accept Return the Book

step
  .goto Tirisfal Glades,68.2,41.9
  .optional >>Gunther's Retreat chain
  .turnin 366 >>Turn in Return the Book to Gunther Arcanus at Gunther's Retreat
  .accept 409 >>Accept Proving Allegiance

step
  .goto Tirisfal Glades,68.2,42.0
  .optional >>Gunther's Retreat chain
  .accept 431 >>Take a Candle of Beckoning from the Crate of Candles next to Gunther

step
  .goto Tirisfal Glades,66.6,44.9
  .optional >>Gunther's Retreat chain
  .accept 410 >>Use the candle at Lillith's Dinner Table in the house south-west of the tower
  .complete 409 >>Kill Lillith Nefara when she appears (lvl 12)

step
  .goto Tirisfal Glades,68.2,41.9
  .optional >>Gunther's Retreat chain
  .turnin 409 >>Turn in Proving Allegiance to Gunther Arcanus
  .accept 411 >>Accept The Prodigal Lich Returns

step
  .goto Tirisfal Glades,65.7,68.8
  .optional >>Gunther's Retreat chain
  .turnin 411 >>Turn in The Prodigal Lich Returns to Bethor Iceshard in the Undercity

step
  .goto Tirisfal Glades,59.4,52.4
  .xp 11
  .accept 445 >>Accept Delivery to Silverpine Forest from Apothecary Johaan in Brill (level 9+)

step
  .goto Tirisfal Glades,61.3,50.8
  .optional >>A level 13 elite-area quest (Captain Dargol in the Agamand crypt); needs a partner or level 12+
  .accept 408 >>Accept The Family Crypt from Magistrate Sevren — do it now with a partner or come back at 12

step
  .zone Silverpine Forest >>Head south-west out of Brill along the road into Silverpine Forest (The Sepulcher)
]], "Lodestar_Guides_Horde")

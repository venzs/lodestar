-- Lodestar Guides: Horde — Silverpine Forest (levels 12-20), the continuation of the Undead route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Sepulcher loops: north (Deep Elem Mine, the Dead
-- Fields, the Skittering Dark, the Deathstalker camp at Ivar's Patch), an Undercity flight for the
-- apothecaries, south (the Dalaran crate, Pyrewood Village), north again (Arugal's Folly, Ivar the
-- Foul, the Decrepit Ferry), Ambermill and Pyrewood at night, then Fenris Isle. Shadowfang Keep is
-- optional. Every quest id and position comes from the data; the order still has to be verified in
-- play (/lode record). Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde 12-20: Silverpine Forest
#faction Horde
#levels 12-19
#next Horde 20-25: Hillsbrad Foothills
#author Lodestar
-- #levels stops at 19 so the auto-pick hands a level 20 character to the next guide; the route itself runs to 20.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- The Sepulcher: first visit ------------------------------------------------------------------------------

step
  .goto Silverpine Forest,42.8,40.9
  .turnin 445 >>Turn in Delivery to Silverpine Forest to Apothecary Renferrel in the Sepulcher (if you brought it from Brill)
  .accept 447 >>Accept A Recipe For Death

step
  .goto Silverpine Forest,43.4,40.9
  .accept 428 >>Accept Lost Deathstalkers from High Executor Hadrec
  .accept 437 >>Accept The Dead Fields

step
  .goto Silverpine Forest,44.2,39.8
  .accept 421 >>Accept Prove Your Worth from Dalar Dawnweaver, up the stairs

step
  .goto Silverpine Forest,44.0,40.9
  .accept 477 >>Accept Border Crossings from Shadow Priest Allister

step
  .goto Silverpine Forest,43.2,41.3
  .hs The Sepulcher >>Set your hearthstone at the Sepulcher inn (Innkeeper Bates)
  .vendor

-- Undead only: the wind rider chain, a free flight to the Undercity and back ---------------------------------

step
  .goto Silverpine Forest,43.4,41.7
  .race Undead
  .accept 6321 >>Accept Supplying the Sepulcher from Deathguard Podrig, by the inn

step
  .goto Silverpine Forest,45.6,42.6
  .race Undead
  .turnin 6321 >>Turn in Supplying the Sepulcher to Karos Razok, the bat handler east of the town
  .accept 6323 >>Accept Ride to the Undercity — he flies you there for free

step
  .goto Undercity,61.5,41.8
  .race Undead
  .turnin 6323 >>Turn in Ride to the Undercity to Gordon Wendham in the Undercity's Trade Quarter
  .accept 6322 >>Accept Michael Garrett

step
  .goto Undercity,63.3,48.6
  .race Undead
  .turnin 6322 >>Turn in Michael Garrett to Michael Garrett, the bat handler
  .accept 6324 >>Accept Return to Podrig — a free flight back to the Sepulcher

step
  .goto Undercity,63.3,48.6
  .race Undead
  .train >>Train new skills at your class trainer in the Undercity while you are here (War Quarter for warriors, the Magic Quarter for mages, warlocks and priests, the Rogues' Quarter)

step
  .goto Silverpine Forest,43.4,41.7
  .race Undead
  .turnin 6324 >>Turn in Return to Podrig to Deathguard Podrig in the Sepulcher (fly back with Michael Garrett)

-- North loop: Deep Elem Mine, the bears, the Dead Fields, the Skittering Dark, Ivar's Patch ---------------------

step
  .goto Silverpine Forest,52.8,28.5
  .complete 421,1 >>Kill 8 Moonrage Whitescalps in and around the Deep Elem Mine, north-east of the Sepulcher (lvl 10-11)

step
  .goto Silverpine Forest,48.8,32.9
  .complete 447,1 >>Loot 5 Grizzled Bear Hearts from Ferocious Grizzled Bears in the woods north of the Sepulcher (lvl 11-12)

step
  .goto Silverpine Forest,45.4,21.2
  .complete 437 >>Walk into the Dead Fields (the open field north of the road) and kill Nightlash when she appears (lvl 14 — she casts; interrupt or burst her) for her essence

step
  .goto Silverpine Forest,35.7,14.9
  .complete 447,2 >>Loot 5 Skittering Blood from Moss Stalkers and Mist Creepers around the Skittering Dark, the cave in the north-west corner (lvl 12-14)

step
  .goto Silverpine Forest,53.5,13.4
  .turnin 428 >>Turn in Lost Deathstalkers to Rane Yorick at the Deathstalker camp on the hill at Ivar's Patch, north-east
  .accept 429 >>Accept Wild Hearts

step
  .goto Silverpine Forest,56.2,9.2
  .accept 435 >>Accept Escorting Erland from Deathstalker Erland, on the road north of the camp — escort him back to Rane (worgs attack on the way, lvl 10-12)

step
  .goto Silverpine Forest,53.5,13.4
  .turnin 435 >>Turn in Escorting Erland to Rane Yorick
  .accept 449 >>Accept The Deathstalkers' Report

step
  .goto Silverpine Forest,54.9,13.6
  .complete 429,1 >>Loot 8 Discolored Worg Hearts from Mottled Worgs and Worgs around Ivar's Patch (lvl 10-12)

-- The Sepulcher: second visit ---------------------------------------------------------------------------------

step
  .goto Silverpine Forest,43.4,40.9
  .turnin 449 >>Turn in The Deathstalkers' Report to High Executor Hadrec (hearth to the Sepulcher)
  .turnin 437 >>Turn in The Dead Fields
  .accept 3221 >>Accept Speak with Renferrel
  .accept 438 >>Accept The Decrepit Ferry

step
  .goto Silverpine Forest,42.8,40.9
  .turnin 3221 >>Turn in Speak with Renferrel to Apothecary Renferrel
  .turnin 429 >>Turn in Wild Hearts
  .accept 430 >>Accept Return to Quinn
  .accept 1359 >>Accept Zinge's Delivery — for the Undercity

step
  .goto Silverpine Forest,44.2,39.8
  .turnin 421 >>Turn in Prove Your Worth to Dalar Dawnweaver
  .accept 422 >>Accept Arugal's Folly

-- Undercity: the apothecaries (fly from Karos Razok) -----------------------------------------------------------

step
  .goto Silverpine Forest,45.6,42.6
  .fly Undercity >>Fly to the Undercity with Karos Razok

step
  .goto Undercity,48.8,69.3
  .turnin 447 >>Turn in A Recipe For Death to Master Apothecary Faranell in the Apothecarium
  .accept 450 >>Accept A Recipe For Death (part 2) — Berard's journal in Pyrewood Village

step
  .goto Undercity,50.1,68.0
  .turnin 1359 >>Turn in Zinge's Delivery to Apothecary Zinge, next to Faranell (she offers a follow-up for the Barrens; leave it)

step
  .goto Undercity,63.3,48.6
  .train >>Train new skills at your class trainer in the Undercity, sell and repair, then fly back to the Sepulcher with Michael Garrett
  .fly The Sepulcher

-- South loop: the Dalaran crate, Pyrewood Village -------------------------------------------------------------

step
  .goto Silverpine Forest,49.9,60.3
  .turnin 477 >>Open the Dalaran Crate at the ambushed wagon on the road south of the Sepulcher and turn in Border Crossings
  .accept 478 >>Accept Maps and Runes from the crate

step
  .goto Silverpine Forest,43.0,73.2
  .complete 450,1 >>Take Berard's Journal from Berard's Bookshelf in the house on the west side of Pyrewood Village (the villagers are friendly by day and worgen by night, lvl 13-15)

step
  .goto Silverpine Forest,46.5,74.4
  .accept 452 >>Accept Pyrewood Ambush from Deathstalker Faerleia, hidden in the house on the south side of Pyrewood

step
  .goto Silverpine Forest,46.5,74.4
  .complete 452 >>Tell Faerleia you are ready and kill the three Pyrewood Councilmen she summons one after another (lvl 15 — use potions and cooldowns; fight next to the door so you can leave)

step
  .goto Silverpine Forest,46.5,74.4
  .turnin 452 >>Turn in Pyrewood Ambush to Deathstalker Faerleia

-- The Sepulcher: third visit -----------------------------------------------------------------------------------

step
  .goto Silverpine Forest,44.0,40.9
  .turnin 478 >>Turn in Maps and Runes to Shadow Priest Allister (hearth to the Sepulcher)
  .accept 481 >>Accept Dalar's Analysis

step
  .goto Silverpine Forest,44.2,39.8
  .turnin 481 >>Turn in Dalar's Analysis to Dalar Dawnweaver
  .accept 482 >>Accept Dalaran's Intentions

step
  .goto Silverpine Forest,44.0,40.9
  .turnin 482 >>Turn in Dalaran's Intentions to Shadow Priest Allister
  .accept 479 >>Accept Ambermill Investigations

step
  .goto Silverpine Forest,42.8,40.9
  .turnin 450 >>Turn in A Recipe For Death to Apothecary Renferrel

step
  .goto Silverpine Forest,42.8,40.9
  .optional >>A Recipe For Death (part 3): lake mosses on Fenris Isle plus a 5% Hardened Tumor from the Vile Fin murlocs — good XP, bad luck
  .accept 451 >>Accept A Recipe For Death (part 3) from Apothecary Renferrel

-- North loop 2: the Remedy, Ivar the Foul, the Decrepit Ferry --------------------------------------------------------

step
  .goto Silverpine Forest,52.8,28.6
  .xp 13
  .complete 422,1 >>Take the Remedy of Arugal from the Dusty Spellbooks at the back of the Deep Elem Mine, north-east of the Sepulcher (Moonrage Whitescalps, lvl 10-11)

step
  .goto Silverpine Forest,53.4,12.6
  .turnin 430 >>Turn in Return to Quinn to Quinn Yorick at the Deathstalker camp at Ivar's Patch

step
  .goto Silverpine Forest,53.5,13.4
  .accept 425 >>Accept Ivar the Foul from Rane Yorick

step
  .goto Silverpine Forest,51.5,13.9
  .complete 425,1 >>Kill Ivar the Foul in the barn at Ivar's Patch, below the camp (lvl 13) and take his head

step
  .goto Silverpine Forest,53.5,13.4
  .turnin 425 >>Turn in Ivar the Foul to Rane Yorick

step
  .goto Silverpine Forest,58.4,34.9
  .turnin 438 >>Use the Corpse Laden Boat on the lake shore east of the road (north-east of the Sepulcher) and turn in The Decrepit Ferry
  .accept 439 >>Accept Rot Hide Clues from the boat

-- The Sepulcher: fourth visit, then the Moonrage shackles --------------------------------------------------------------

step
  .goto Silverpine Forest,44.2,39.8
  .turnin 422 >>Turn in Arugal's Folly to Dalar Dawnweaver (hearth to the Sepulcher)
  .accept 423 >>Accept Arugal's Folly (part 3)

step
  .goto Silverpine Forest,43.4,40.9
  .turnin 439 >>Turn in Rot Hide Clues to High Executor Hadrec (he also offers The Engraved Ring, a hand-off chain through Brill and the Undercity — skip it)
  .accept 443 >>Accept Rot Hide Ichor

step
  .goto Silverpine Forest,46.6,28.4
  .complete 423,1 >>Loot a Glutton Shackle from Moonrage Gluttons north of the Sepulcher (lvl 12-13)

step
  .goto Silverpine Forest,43.5,32.1
  .complete 423,2 >>Loot a Darksoul Shackle from Moonrage Darksouls, north-west of the town (lvl 13-14)

step
  .goto Silverpine Forest,44.2,39.8
  .xp 14
  .turnin 423 >>Turn in Arugal's Folly to Dalar Dawnweaver
  .accept 424 >>Accept Arugal's Folly (part 4) — Grimson the Pale

-- Grimson, Ambermill, Pyrewood at night ---------------------------------------------------------------------------------

step
  .goto Silverpine Forest,58.6,44.9
  .complete 424,1 >>Kill Grimson the Pale by the lake shore, east of the road and south of the ferry (lvl 15) and take his head

step
  .goto Silverpine Forest,58.7,63.5
  .complete 479,1 >>Loot 20 Dalaran Pendants from the Dalaran Protectors and Mages at Ambermill, south-east (lvl 14-16; the Conjurors deeper in are 17-18)

step
  .goto Silverpine Forest,44.2,39.8
  .xp 15
  .turnin 424 >>Turn in Arugal's Folly to Dalar Dawnweaver (hearth to the Sepulcher)
  .accept 99 >>Accept Arugal's Folly (part 5) — Pyrewood Shackles

step
  .goto Silverpine Forest,44.0,40.9
  .turnin 479 >>Turn in Ambermill Investigations to Shadow Priest Allister (his follow-up The Weaver, Archmage Ataeric lvl 22 at Ambermill, is a group quest for later)

step
  .goto Silverpine Forest,45.3,72.4
  .complete 99,1 >>Loot a Pyrewood Shackle from the Pyrewood Watchers, Sentries and Elders in Pyrewood Village at night (lvl 13-15; by day they are friendly villagers — wait for dusk, or fight the Moonrage worgen on the road meanwhile)

step
  .goto Silverpine Forest,44.2,39.8
  .turnin 99 >>Turn in Arugal's Folly to Dalar Dawnweaver (hearth to the Sepulcher)

-- Fenris Isle -------------------------------------------------------------------------------------------------------------

step
  .goto Silverpine Forest,65.8,29.1
  .xp 16
  .complete 443,1 >>Swim to Fenris Isle from the ferry and loot 5 Rot Hide Ichor from the Rot Hide gnolls around the keep (Brutes and Plague Weavers lvl 16-18 on the shore, Savages and Raging Rot Hides lvl 18-19 further in)

step
  .goto Silverpine Forest,71.5,36.2
  .optional >>A Recipe For Death (part 3)
  .complete 451,1 >>Loot 5 Lake Skulker Moss from Lake Skulkers on the eastern shore of Lordamere Lake (lvl 15-17)
  .complete 451,2 >>Loot 5 Lake Creeper Moss from Lake Creepers further north along the shore (lvl 17-19)
  .complete 451,3 >>Loot a Hardened Tumor from the Vile Fin murlocs on the north shore of the lake (lvl 12-14, 5% drop)

step
  .goto Silverpine Forest,42.8,40.9
  .turnin 443 >>Turn in Rot Hide Ichor to Apothecary Renferrel (hearth to the Sepulcher)
  .accept 444 >>Accept Rot Hide Origins — for Bethor Iceshard in the Undercity

step
  .goto Silverpine Forest,45.6,42.6
  .fly Undercity >>Fly to the Undercity

step
  .goto Undercity,84.1,17.4
  .turnin 444 >>Turn in Rot Hide Origins to Bethor Iceshard in the Magic Quarter
  .accept 446 >>Accept Thule Ravenclaw — a hand-off back to Renferrel

step
  .goto Undercity,48.8,69.3
  .optional >>A Recipe For Death (part 3)
  .turnin 451 >>Turn in A Recipe For Death to Master Apothecary Faranell in the Apothecarium

step
  .goto Undercity,63.3,48.6
  .xp 17
  .train >>Train new skills in the Undercity, sell and repair, then fly back to the Sepulcher
  .fly The Sepulcher

step
  .goto Silverpine Forest,42.8,40.9
  .turnin 446 >>Turn in Thule Ravenclaw to Apothecary Renferrel
  .accept 448 >>Accept Report to Hadrec

step
  .goto Silverpine Forest,43.4,40.9
  .turnin 448 >>Turn in Report to Hadrec to High Executor Hadrec

step
  .goto Silverpine Forest,43.4,40.9
  .optional >>Assault on Fenris Isle: Thule Ravenclaw (lvl 24) in Fenris Keep — a group quest
  .accept 442 >>Accept Assault on Fenris Isle from High Executor Hadrec

step
  .goto Silverpine Forest,65.7,23.7
  .optional >>Assault on Fenris Isle
  .complete 442,1 >>Kill Thule Ravenclaw at the top of Fenris Keep (lvl 24, with Rot Hide guards) and take his head

step
  .goto Silverpine Forest,43.4,40.9
  .optional >>Assault on Fenris Isle
  .turnin 442 >>Turn in Assault on Fenris Isle to High Executor Hadrec

-- Shadowfang Keep (optional) and the road to Hillsbrad ------------------------------------------------------------------------

step
  .goto Silverpine Forest,44.2,39.8
  .xp 18
  .optional >>Shadowfang Keep (lvl 18-25 dungeon): Arugal Must Die, and Hadrec's Deathstalkers in Shadowfang (turned in inside the keep), are worth a group run at 18+
  .accept 1014 >>Accept Arugal Must Die from Dalar Dawnweaver (level 18)

step
  .goto Silverpine Forest,44.2,39.8
  .optional >>Shadowfang Keep
  .complete 1014,1 >>Kill Archmage Arugal at the top of Shadowfang Keep with a group and take his head

step
  .goto Silverpine Forest,44.2,39.8
  .optional >>Shadowfang Keep
  .turnin 1014 >>Turn in Arugal Must Die to Dalar Dawnweaver

step
  .goto Silverpine Forest,43.2,41.3
  .xp 19 >>You should be level 19 by now; if not, kill Rot Hides on Fenris Isle or Dalaran mages at Ambermill until you are

step
  .goto Silverpine Forest,42.8,40.9
  .accept 493 >>Accept Journey to Hillsbrad Foothills from Apothecary Renferrel (level 19) — Apothecary Lydon in Tarren Mill

step
  .zone Hillsbrad Foothills >>Take the road south-east from the Sepulcher, past Ambermill, into Hillsbrad Foothills — Tarren Mill lies in its north-east
]], "Lodestar_Guides_Horde")

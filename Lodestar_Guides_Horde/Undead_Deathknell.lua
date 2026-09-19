-- Lodestar Guides: Horde — Undead starting area (levels 1-5).
--
-- Quest ids, NPC and objective positions come from the built-in Vanilla database (Data/Vanilla.lua);
-- the order is the classic Deathknell loop. Forever adds quests this file does not know about yet
-- (Undead paladins, for one) — smart mode and `/lode record` pick those up.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde/Undead 1-5: Deathknell
#faction Horde
#race Undead
#levels 1-5
#next Horde/Undead 5-12: Tirisfal Glades
#author Lodestar
#note Positions from the Vanilla database. Forever-only quests are not in this route yet.

step
  .goto Tirisfal Glades,30.2,71.7
  .accept 363 >>Accept Rude Awakening from Undertaker Mordo (behind you when you spawn)

step
  .goto Tirisfal Glades,30.8,66.2
  .turnin 363 >>Turn in Rude Awakening to Shadow Priest Sarvis
  .accept 364 >>Accept The Mindless Ones

step
  .goto Tirisfal Glades,32.3,63.6
  .complete 364 >>Kill 8 Mindless and Wretched Zombies in the graveyard north-east of the chapel (lvl 1-2)

step
  .goto Tirisfal Glades,30.8,66.2
  .turnin 364 >>Turn in The Mindless Ones
  .accept 3901 >>Accept Rattling the Rattlecages

step
  .goto Tirisfal Glades,30.8,66.2
  .class Warrior
  .accept 3095 >>Accept Simple Scroll (warrior) from Sarvis

step
  .goto Tirisfal Glades,30.8,66.2
  .class Rogue
  .accept 3096 >>Accept Encrypted Scroll (rogue) from Sarvis

step
  .goto Tirisfal Glades,30.8,66.2
  .class Priest
  .accept 3097 >>Accept Hallowed Scroll (priest) from Sarvis

step
  .goto Tirisfal Glades,30.8,66.2
  .class Mage
  .accept 3098 >>Accept Glyphic Scroll (mage) from Sarvis

step
  .goto Tirisfal Glades,30.8,66.2
  .class Warlock
  .accept 3099 >>Accept Tainted Scroll (warlock) from Sarvis

-- Undead Paladin is new on Forever, so its scroll is a quest no database has: not pfQuest, which
-- predates it, and not ATT. Named without an id and without a position rather than guessed at --
-- an arrow pointing at a guess is worse than no arrow, and a wrong quest id would have the engine
-- waiting forever for something that never completes. The id arrives the first time a paladin
-- accepts it with Lodestar running, and then this becomes an ordinary .accept step.
step
  .class Paladin
  .text >>Ask Shadow Priest Sarvis for your class scroll too — Undead Paladin is new on Forever and its quest is not in any database yet, so Lodestar cannot point at it. Taking it while this is running is what records it for everyone else.

step
  .goto Tirisfal Glades,30.9,66.1
  .xp 2
  .accept 376 >>Accept The Damned from Novice Elreth (next to Sarvis) — it needs level 2, which the zombies give you

step
  .goto Tirisfal Glades,32.7,65.6
  .class Warrior
  .turnin 3095 >>Turn in Simple Scroll to Dannal Stern and train
  .train

step
  .goto Tirisfal Glades,32.5,65.7
  .class Rogue
  .turnin 3096 >>Turn in Encrypted Scroll to David Trias and train
  .train

step
  .goto Tirisfal Glades,31.1,66.0
  .class Priest
  .turnin 3097 >>Turn in Hallowed Scroll to Dark Cleric Duesten and train
  .train

step
  .goto Tirisfal Glades,30.9,66.1
  .class Mage
  .turnin 3098 >>Turn in Glyphic Scroll to Isabella and train
  .train

step
  .goto Tirisfal Glades,30.9,66.3
  .class Warlock
  .turnin 3099 >>Turn in Tainted Scroll to Maximillion and train
  .train

-- The other half of the same gap: no .goto either, because Deathknell's paladin trainer is new on
-- Forever and nothing records where they stand. A position invented to fill the line would send
-- every Undead paladin to the wrong corner of the village with confidence.
step
  .class Paladin
  .text >>Hand your scroll back to the paladin trainer and train. They are new on Forever, so Lodestar does not know their name or where they stand yet — walking up to them is what puts them on the map.

step
  .goto Tirisfal Glades,32.8,61.8
  .complete 3901,1 >>Kill 8 Rattlecage Skeletons around the graveyard (lvl 2-3)

step
  .goto Tirisfal Glades,30.1,65.4
  .complete 376,1 >>Collect 6 Duskbat Wings — Duskbats fly around Deathknell (lvl 1-2)
  .complete 376,2 >>Collect 6 Scavenger Paws — Young Scavengers north of the chapel (lvl 1)

step
  .goto Tirisfal Glades,30.8,66.2
  .turnin 3901 >>Turn in Rattling the Rattlecages to Sarvis

step
  .goto Tirisfal Glades,30.9,66.1
  .turnin 376 >>Turn in The Damned to Novice Elreth
  .xp 3
  .accept 6395 >>Accept Marla's Last Wish (level 3)

step
  .goto Tirisfal Glades,31.6,65.6
  .accept 3902 >>Accept Scavenging Deathknell from Deathguard Saltain

step
  .goto Tirisfal Glades,32.2,66.0
  .accept 380 >>Accept Night Web's Hollow from Executor Arren

step
  .goto Tirisfal Glades,32.8,63.1
  .complete 3902,1 >>Loot 6 Scavenged Goods from the Equipment Boxes in the ruined houses east of the chapel

step
  .goto Tirisfal Glades,36.6,61.6
  .complete 6395,2 >>Kill Samuel Fipps (lvl 5, east end of the ruins) for Samuel's Remains

step
  .goto Tirisfal Glades,31.2,65.1
  .complete 6395 >>Use Samuel's Remains at Marla's Grave, behind the chapel

step
  .goto Tirisfal Glades,28.3,57.4
  .complete 380,1 >>Kill 10 Young Night Web Spiders at the mouth of Night Web's Hollow (lvl 2-3)

step
  .goto Tirisfal Glades,24.8,59.7
  .complete 380,2 >>Kill 8 Night Web Spiders deeper in the cave (lvl 3-4)

step
  .goto Tirisfal Glades,30.9,66.1
  .turnin 6395 >>Turn in Marla's Last Wish to Novice Elreth

step
  .goto Tirisfal Glades,31.6,65.6
  .turnin 3902 >>Turn in Scavenging Deathknell to Deathguard Saltain

step
  .goto Tirisfal Glades,32.2,66.0
  .turnin 380 >>Turn in Night Web's Hollow to Executor Arren
  .accept 381 >>Accept The Scarlet Crusade

step
  .goto Tirisfal Glades,37.6,67.5
  .complete 381,1 >>Collect 12 Scarlet Armbands from Scarlet Converts and Initiates at the camp south-east of Deathknell (lvl 3-4)

step
  .goto Tirisfal Glades,32.2,66.0
  .turnin 381 >>Turn in The Scarlet Crusade to Executor Arren
  .accept 382 >>Accept The Red Messenger

step
  .goto Tirisfal Glades,36.5,68.8
  .complete 382,1 >>Kill Meven Korgal in the big tent at the Scarlet camp (lvl 5) and loot the documents

step
  .goto Tirisfal Glades,32.2,66.0
  .turnin 382 >>Turn in The Red Messenger to Executor Arren
  .accept 383 >>Accept Vital Intelligence — it sends you to Brill

step
  .goto Tirisfal Glades,32.2,66.0
  .xp 5 >>Kill Scarlet Initiates and skeletons until level 5 if you are not there yet, then head east to Brill
]], "Lodestar_Guides_Horde")

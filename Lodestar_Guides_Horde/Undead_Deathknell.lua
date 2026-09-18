-- Lodestar Guides: Horde — Undead starting area.
--
-- DRAFT. Quest IDs and coordinates come from the Classic-era Deathknell layout; WoW: Forever is
-- built on that world but may have changed quests. Play it with `/lode record start` on and export
-- the recording to replace this file with verified data.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde/Undead 1-5: Deathknell
#faction Horde
#race Undead
#levels 1-5
#next Horde/Undead 5-12: Tirisfal Glades
#author Lodestar
#note DRAFT from Classic-era data — verify in Forever with /lode record.

step
  .goto 18,30.8,66.2
  .accept 3901 >>Accept Rude Awakening from Shadow Priest Sarvis

step
  .goto 18,31.0,65.9
  .turnin 3901 >>Turn in Rude Awakening to Undertaker Mordo
  .accept 3903 >>Accept Rattling the Rattlecages

step
  .goto 18,30.8,66.2
  .accept 364 >>Accept The Mindless Ones from Shadow Priest Sarvis

step
  .goto 18,30.4,68.9
  .complete 364,1 >>Kill Mindless Zombies (lvl 1-2)
  .complete 3903,1 >>Kill Rattlecage Skeletons (lvl 1-2)

step
  .goto 18,30.8,66.2
  .turnin 364 >>Turn in The Mindless Ones
  .xp 3

step
  .goto 18,31.0,65.9
  .turnin 3903 >>Turn in Rattling the Rattlecages
  .accept 376 >>Accept Marla's Last Wish

step
  .goto 18,32.0,65.9
  .accept 3902 >>Accept Scavenging Deathknell from Deathguard Saltain

step
  .goto 18,31.6,64.3
  .accept 365 >>Accept Night Web's Hollow from Novice Elreth

step
  .goto 18,33.5,66.5
  .complete 3902,1 >>Collect Scavenged Goods from the ruined houses

step
  .goto 18,32.2,63.6
  .complete 376,1 >>Recover Samuel's Remains (Samuel Fipps, east of the chapel)

step
  .goto 18,29.0,58.9
  .complete 365,1 >>Kill Young Night Web Spiders in Night Web's Hollow
  .complete 365,2 >>Kill Night Web Spiders deeper in the cave

step
  .goto 18,31.6,64.3
  .turnin 365 >>Turn in Night Web's Hollow

step
  .goto 18,32.0,65.9
  .turnin 3902 >>Turn in Scavenging Deathknell

step
  .goto 18,31.0,65.9
  .turnin 376 >>Turn in Marla's Last Wish

step
  .goto 18,32.2,66.6
  .accept 363 >>Accept The Damned from Executor Arren
  .accept 3905 >>Accept Vital Intelligence (leads to Brill)

step
  .goto 18,35.0,64.0
  .complete 363,1 >>Kill Scourge in the fields east of Deathknell
  .complete 363,2

step
  .goto 18,32.2,66.6
  .turnin 363 >>Turn in The Damned
  .xp 5

step
  .zone Tirisfal Glades >>Head east on the road toward Brill with Vital Intelligence
]], "Lodestar_Guides_Horde")

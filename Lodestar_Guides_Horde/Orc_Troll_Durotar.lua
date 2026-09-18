-- Lodestar Guides: Horde — Orc and Troll starting zone, Durotar (levels 1-12).
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Durotar route (Valley of Trials → Sen'jin Village and
-- the coast → Razor Hill and Tiragarde Keep → Echo Isles → the Razormane grounds → Thunder Ridge and
-- Drygulch Ravine → Skull Rock → Orgrimmar). Every quest id and position comes from the data; the
-- order still has to be verified in play (/lode record). Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Horde/Orc,Troll 1-12: Durotar
#faction Horde
#race Orc,Troll
#levels 1-12
#next Horde 12-20: The Barrens
#author Lodestar
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Valley of Trials ------------------------------------------------------------------------------

step
  .goto Durotar,43.3,68.5
  .accept 4641 >>Accept Your Place In The World from Kaltunk (right where you spawn)

step
  .goto Durotar,42.1,68.3
  .turnin 4641 >>Turn in Your Place In The World to Gornek in the big hut
  .accept 788 >>Accept Cutting Teeth

step
  .goto Durotar,44.5,65.0
  .complete 788,1 >>Kill 10 Mottled Boars around the valley floor (lvl 1-2)

step
  .goto Durotar,42.1,68.3
  .turnin 788 >>Turn in Cutting Teeth to Gornek
  .accept 789 >>Accept Sting of the Scorpid

-- Class scrolls (Gornek hands them out after Cutting Teeth) ---------------------------------------

step
  .goto Durotar,42.1,68.3
  .class Warrior
  .race Orc
  .accept 2383 >>Accept Simple Parchment (warrior) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Warrior
  .race Troll
  .accept 3065 >>Accept Simple Tablet (warrior) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Hunter
  .race Orc
  .accept 3087 >>Accept Etched Parchment (hunter) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Hunter
  .race Troll
  .accept 3082 >>Accept Etched Tablet (hunter) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Rogue
  .race Orc
  .accept 3088 >>Accept Encrypted Parchment (rogue) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Rogue
  .race Troll
  .accept 3083 >>Accept Encrypted Tablet (rogue) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Shaman
  .race Orc
  .accept 3089 >>Accept Rune-Inscribed Parchment (shaman) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Shaman
  .race Troll
  .accept 3084 >>Accept Rune-Inscribed Tablet (shaman) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Priest
  .accept 3085 >>Accept Hallowed Tablet (priest) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Mage
  .accept 3086 >>Accept Glyphic Tablet (mage) from Gornek

step
  .goto Durotar,42.1,68.3
  .class Warlock
  .accept 3090 >>Accept Tainted Parchment (warlock) from Gornek

step
  .goto Durotar,42.7,67.2
  .accept 4402 >>Accept Galgar's Cactus Apple Surprise from Galgar, outside the hut

step
  .goto Durotar,42.8,69.1
  .class Warrior,Hunter,Rogue,Priest,Shaman,Mage
  .xp 2
  .accept 792 >>Accept Vile Familiars from Zureetha Fargaze (level 2 — the boars get you there)

step
  .goto Durotar,42.6,69.0
  .class Warlock
  .accept 1485 >>Accept Vile Familiars (warlock version) from Ruzan, next to Zureetha

-- Class trainers in the valley ------------------------------------------------------------------

step
  .goto Durotar,42.9,69.4
  .class Warrior
  .race Orc
  .turnin 2383 >>Turn in Simple Parchment to Frang and train
  .train Frang

step
  .goto Durotar,42.9,69.4
  .class Warrior
  .race Troll
  .turnin 3065 >>Turn in Simple Tablet to Frang and train
  .train Frang

step
  .goto Durotar,42.8,69.3
  .class Hunter
  .race Orc
  .turnin 3087 >>Turn in Etched Parchment to Jen'shan and train
  .train Jen'shan

step
  .goto Durotar,42.8,69.3
  .class Hunter
  .race Troll
  .turnin 3082 >>Turn in Etched Tablet to Jen'shan and train
  .train Jen'shan

step
  .goto Durotar,41.3,68.0
  .class Rogue
  .race Orc
  .turnin 3088 >>Turn in Encrypted Parchment to Rwag (west side of the valley) and train
  .train Rwag

step
  .goto Durotar,41.3,68.0
  .class Rogue
  .race Troll
  .turnin 3083 >>Turn in Encrypted Tablet to Rwag (west side of the valley) and train
  .train Rwag

step
  .goto Durotar,42.4,69.0
  .class Shaman
  .race Orc
  .turnin 3089 >>Turn in Rune-Inscribed Parchment to Shikrik and train
  .train Shikrik

step
  .goto Durotar,42.4,69.0
  .class Shaman
  .race Troll
  .turnin 3084 >>Turn in Rune-Inscribed Tablet to Shikrik and train
  .train Shikrik

step
  .goto Durotar,42.4,68.8
  .class Priest
  .turnin 3085 >>Turn in Hallowed Tablet to Ken'jai and train
  .train Ken'jai

step
  .goto Durotar,42.5,69.0
  .class Mage
  .turnin 3086 >>Turn in Glyphic Tablet to Mai'ah and train
  .train Mai'ah

step
  .goto Durotar,40.7,68.5
  .class Warlock
  .turnin 3090 >>Turn in Tainted Parchment to Nartok (west end of the valley) and train
  .train Nartok

-- West side: cactus apples, scorpids, Sarkoth -----------------------------------------------------

step
  .goto Durotar,43.6,63.0
  .complete 4402,1 >>Pick 7 Cactus Apples — the small cacti with a sparkle, all over the valley floor

step
  .goto Durotar,40.6,62.6
  .accept 790 >>Accept Sarkoth from Hana'zua, the injured troll in the north-west corner

step
  .goto Durotar,41.4,63.1
  .complete 789,1 >>Loot 8 Scorpid Worker Tails from Scorpid Workers on the west side (lvl 3)

step
  .goto Durotar,40.5,66.8
  .complete 790,1 >>Kill Sarkoth in the little canyon south of Hana'zua (lvl 4) and loot his claw

step
  .goto Durotar,40.6,62.6
  .turnin 790 >>Turn in Sarkoth to Hana'zua
  .accept 804 >>Accept Sarkoth (part 2), a hand-off to Gornek

step
  .goto Durotar,42.1,68.3
  .turnin 789 >>Turn in Sting of the Scorpid to Gornek
  .turnin 804 >>Turn in Sarkoth

step
  .goto Durotar,42.7,67.2
  .turnin 4402 >>Turn in Galgar's Cactus Apple Surprise to Galgar

step
  .goto Durotar,44.6,68.7
  .xp 3
  .accept 5441 >>Accept Lazy Peons from Foreman Thazz'ril, east side of the valley (level 3 — kill a few more boars if you are short)

step
  .goto Durotar,45.6,65.7
  .complete 5441,1 >>Whack 5 sleeping Lazy Peons with the Foreman's Blackjack — they doze under the trees around the valley (lvl 4, they do not fight back)

step
  .goto Durotar,44.6,68.7
  .turnin 5441 >>Turn in Lazy Peons to Foreman Thazz'ril
  .accept 6394 >>Accept Thazz'ril's Pick

step
  .goto Durotar,42.4,69.2
  .class Shaman
  .xp 4
  .accept 1516 >>Accept Call of Earth from Canaga Earthcaller (level 4 — the first shaman totem chain)

-- The Burning Blade cave in the north ------------------------------------------------------------

step
  .goto Durotar,44.2,55.3
  .class Warrior,Hunter,Rogue,Priest,Shaman,Mage
  .complete 792,1 >>Kill 12 Vile Familiars outside and inside the Burning Blade cave in the north of the valley (lvl 3-4)

step
  .goto Durotar,44.2,55.3
  .class Warlock
  .complete 1485,1 >>Loot 6 Vile Familiar Heads from Vile Familiars outside and inside the Burning Blade cave (lvl 3-4)

step
  .goto Durotar,44.3,54.1
  .class Shaman
  .complete 1516,1 >>Loot 4 Felstalker Hooves from Felstalkers at the cave (lvl 3-4)

step
  .goto Durotar,43.7,53.8
  .complete 6394,1 >>Pick up Thazz'ril's Pick from the floor inside the cave, first chamber on the left

-- Back to the valley, then Yarrog ----------------------------------------------------------------

step
  .goto Durotar,42.8,69.1
  .class Warrior,Hunter,Rogue,Priest,Shaman,Mage
  .turnin 792 >>Turn in Vile Familiars to Zureetha Fargaze
  .accept 794 >>Accept Burning Blade Medallion

step
  .goto Durotar,42.6,69.0
  .class Warlock
  .turnin 1485 >>Turn in Vile Familiars to Ruzan
  .accept 1499 >>Accept Vile Familiars (part 2), a hand-off to Zureetha

step
  .goto Durotar,42.8,69.1
  .class Warlock
  .turnin 1499 >>Turn in Vile Familiars to Zureetha Fargaze
  .accept 794 >>Accept Burning Blade Medallion

step
  .goto Durotar,44.6,68.7
  .turnin 6394 >>Turn in Thazz'ril's Pick to Foreman Thazz'ril

step
  .goto Durotar,42.4,69.2
  .class Shaman
  .turnin 1516 >>Turn in Call of Earth to Canaga Earthcaller
  .accept 1517 >>Accept Call of Earth (part 2)

step
  .goto Durotar,44.0,76.2
  .class Shaman
  .turnin 1517 >>Turn in Call of Earth to the Minor Manifestation of Earth, south of the valley past the peons — kill it when it turns hostile
  .accept 1518 >>Accept Call of Earth (part 3)

step
  .goto Durotar,42.4,69.2
  .class Shaman
  .turnin 1518 >>Turn in Call of Earth to Canaga Earthcaller for your Earth Totem

step
  .goto Durotar,42.7,53.0
  .complete 794,1 >>Back into the cave: kill Yarrog Baneshadow at the far end (lvl 5) and loot the Burning Blade Medallion

step
  .goto Durotar,42.8,69.1
  .turnin 794 >>Turn in Burning Blade Medallion to Zureetha Fargaze
  .accept 805 >>Accept Report to Sen'jin Village

step
  .goto Durotar,42.4,68.8
  .class Priest
  .xp 5
  .accept 5649 >>Accept In Favor of Spirituality from Ken'jai (level 5) — a hand-off to Tai'jin in Razor Hill

step
  .goto Durotar,42.8,69.1
  .xp 5 >>You should be level 5 leaving the valley; kill Scorpid Workers and boars if not, then head out of the valley to the east

-- Sen'jin Village and the coast -------------------------------------------------------------------

step
  .goto Durotar,52.1,68.3
  .accept 2161 >>Accept A Peon's Burden from Ukor on the road east of the valley

step
  .goto Durotar,55.9,74.7
  .turnin 805 >>Turn in Report to Sen'jin Village to Master Gadrin
  .accept 823 >>Accept Report to Orgnil
  .accept 826 >>Accept Zalazane
  .accept 808 >>Accept Minshina's Skull

step
  .goto Durotar,55.9,74.4
  .accept 818 >>Accept A Solvent Spirit from Master Vornal

step
  .goto Durotar,56.0,73.9
  .accept 817 >>Accept Practical Prey from Vel'rin Fang

step
  .goto Durotar,56.3,75.1
  .class Mage
  .train Un'Thuwa >>Train at Un'Thuwa, the mage trainer in Sen'jin (there is none in Razor Hill)

step
  .goto Durotar,61.3,61.8
  .complete 818,2 >>Loot 6 Crawler Mucus from Pygmy Surf Crawlers on the beach north-east of Sen'jin (lvl 5-6)

step
  .goto Durotar,62.1,68.9
  .complete 818,1 >>Loot 6 Intact Makrura Eyes from Makrura Clackers and Shellhides on the shore east of Sen'jin (lvl 6-7)

step
  .goto Durotar,55.9,74.4
  .turnin 818 >>Turn in A Solvent Spirit to Master Vornal

-- Razor Hill: first visit -------------------------------------------------------------------------

step
  .goto Durotar,51.5,41.6
  .turnin 2161 >>Turn in A Peon's Burden to Innkeeper Grosk in Razor Hill
  .hs Razor Hill >>Set your hearthstone at the Razor Hill inn

step
  .goto Durotar,52.2,43.2
  .turnin 823 >>Turn in Report to Orgnil to Orgnil Soulscar

step
  .goto Durotar,51.9,43.5
  .accept 784 >>Accept Vanquish the Betrayers from Gar'Thok, the watchtower by the road

step
  .goto Durotar,49.9,40.4
  .accept 791 >>Accept Carry Your Weight from Furl Scornbrow, north-west of the village

step
  .goto Durotar,54.3,42.9
  .class Priest
  .turnin 5649 >>Turn in In Favor of Spirituality to Tai'jin, the priest trainer
  .accept 5648 >>Accept Garments of Spirituality
  .train Tai'jin

step
  .goto Durotar,53.1,46.5
  .class Priest
  .complete 5648,1 >>Hand the robe to Grunt Kor'ja on the road south of Razor Hill (friendly — just talk to him)

step
  .goto Durotar,54.3,42.9
  .class Priest
  .turnin 5648 >>Turn in Garments of Spirituality to Tai'jin

step
  .goto Durotar,54.2,42.5
  .class Warrior
  .train Tarshaw Jaggedscar >>Train at Tarshaw Jaggedscar, the warrior trainer in the barracks

step
  .goto Durotar,51.8,43.5
  .class Hunter
  .train Thotar >>Train at Thotar, the hunter trainer by the watchtower

step
  .goto Durotar,52.0,43.7
  .class Rogue
  .train Kaplak >>Train at Kaplak, the rogue trainer by the watchtower

step
  .goto Durotar,54.4,42.6
  .class Shaman
  .train Swart >>Train at Swart, the shaman trainer in the barracks

step
  .goto Durotar,54.4,41.2
  .class Warlock
  .train Dhugru Gorelust >>Train at Dhugru Gorelust, the warlock trainer behind the barracks

step
  .goto Durotar,51.5,41.6
  .vendor >>Sell junk at the vendors around the inn and buy food and water

-- Tiragarde Keep ------------------------------------------------------------------------------------

step
  .goto Durotar,57.5,55.3
  .complete 784,1 >>Kill 10 Kul Tiras Sailors around Tiragarde Keep, south-east of Razor Hill (lvl 5-6)
  .complete 791,1 >>Loot 8 Canvas Scraps from the sailors and marines while you are at it

step
  .goto Durotar,59.2,56.7
  .complete 784,2 >>Kill 8 Kul Tiras Marines inside the keep (lvl 6-7)

step
  .goto Durotar,59.7,58.3
  .complete 784,3 >>Kill Lieutenant Benedict at the top of the keep (lvl 8 — pull him alone)

step
  .goto Durotar,59.3,57.6
  .accept 830 >>Open Benedict's Chest next to him and accept The Admiral's Orders from the Aged Envelope

step
  .goto Durotar,49.9,40.4
  .turnin 791 >>Turn in Carry Your Weight to Furl Scornbrow (hearth or run back to Razor Hill)

step
  .goto Durotar,51.9,43.5
  .turnin 784 >>Turn in Vanquish the Betrayers to Gar'Thok
  .turnin 830 >>Turn in The Admiral's Orders
  .xp 6
  .accept 825 >>Accept From The Wreckage....
  .accept 831 >>Accept The Admiral's Orders (part 2) — for Nazgrel in Orgrimmar later
  .accept 837 >>Accept Encroachment (level 6 — the Tiragarde sailors get you there)

step
  .goto Durotar,51.1,42.4
  .accept 815 >>Accept Break a Few Eggs from Cook Torka, by the inn (the eggs are on the Echo Isles)

-- Razormane grounds south-west of Razor Hill, then the Echo Isles loop ----------------------------

step
  .goto Durotar,48.8,48.9
  .complete 837,1 >>Kill 8 Razormane Quilboar in the grounds south-west of Razor Hill (lvl 6-7)
  .complete 837,2 >>Kill 8 Razormane Scouts there too (lvl 7-8)

step
  .goto Durotar,54.2,73.3
  .xp 7
  .accept 786 >>Accept Thwarting Kolkar Aggression from Lar Prowltusk in Sen'jin Village (if he has nothing for you, a Kolkar centaur at the camp south-west of the village drops the attack plans that start A Strategic Alliance — bring them to him first)

step
  .goto Durotar,49.8,81.3
  .complete 786,1 >>At the Kolkar centaur camp south-west of Sen'jin (lvl 6-8): burn the attack plan against the Valley of Trials, in the southern tent

step
  .goto Durotar,47.7,77.3
  .complete 786,2 >>Burn the attack plan against Sen'jin Village, north-west tent

step
  .goto Durotar,46.2,78.9
  .complete 786,3 >>Burn the attack plan against Orgrimmar, western tent

step
  .goto Durotar,54.2,73.3
  .turnin 786 >>Turn in Thwarting Kolkar Aggression to Lar Prowltusk

-- Echo Isles -------------------------------------------------------------------------------------

step
  .goto Durotar,64.6,85.0
  .complete 817,1 >>Swim to the Echo Isles: loot 6 Durotar Tiger Furs from Durotar Tigers on the first island (lvl 7-8)

step
  .goto Durotar,64.9,82.4
  .complete 815,1 >>Loot 6 Taillasher Eggs from the nests on the beaches of the isles (watch the Taillashers, lvl 6-8)

step
  .goto Durotar,67.3,84.9
  .complete 826,1 >>Kill Voodoo and Hexed Trolls on the eastern island (lvl 8-9): 8 of each
  .complete 826,2 >>Kill the Hexed Trolls

step
  .goto Durotar,67.4,87.8
  .complete 808,1 >>Free the Imprisoned Darkspear in the hut at the south end (a cage on the ground) for Minshina's Skull

step
  .goto Durotar,67.6,87.8
  .complete 826,3 >>Kill Zalazane in the same hut (lvl 10 — he casts; interrupt or burst him) and loot his head

step
  .goto Durotar,55.9,74.7
  .turnin 826 >>Turn in Zalazane to Master Gadrin in Sen'jin
  .turnin 808 >>Turn in Minshina's Skull

step
  .goto Durotar,56.0,73.9
  .turnin 817 >>Turn in Practical Prey to Vel'rin Fang

step
  .goto Durotar,63.8,53.0
  .complete 825,1 >>Run north along the beach past Tiragarde: loot 5 Gnomish Tools from the Gnomish Toolboxes in the shipwrecks (north-east of the keep)

-- Razor Hill: second visit (level 9-10) ---------------------------------------------------------------

step
  .goto Durotar,51.9,43.5
  .turnin 825 >>Turn in From The Wreckage.... to Gar'Thok (hearth to Razor Hill)

step
  .goto Durotar,51.1,42.4
  .turnin 815 >>Turn in Break a Few Eggs to Cook Torka

step
  .goto Durotar,52.2,43.2
  .accept 806 >>Accept Dark Storms from Orgnil Soulscar (Fizzle Darkstorm, lvl 12 — on the Thunder Ridge loop)

step
  .goto Durotar,51.5,41.6
  .train >>Train new skills at your class trainer in Razor Hill, sell and repair

-- West and north: the Razormane grounds, Thunder Ridge, Drygulch Ravine -------------------------------

step
  .goto Durotar,43.3,40.4
  .complete 837,3 >>Kill 8 Razormane Dustrunners in the western Razormane grounds, on the road to the Barrens (lvl 8-9)
  .complete 837,4 >>Kill 4 Razormane Battleguards there (lvl 9-10)

step
  .goto Durotar,43.1,30.2
  .xp 8
  .optional >>Kron's Amulet is a 7% drop from Dreadmaw Crocolisks along the river — only worth it if you like fishing for it
  .accept 816 >>Accept Lost But Not Forgotten from Misha Tor'kren, at the hut north of the Razormane grounds

step
  .goto Durotar,42.1,26.7
  .complete 806,1 >>Kill Fizzle Darkstorm on Thunder Ridge, the plateau west of Drygulch (lvl 12 — clear the Burning Blade Cultists around him first, lvl 10-11)

step
  .goto Durotar,46.4,22.9
  .xp 9
  .accept 834 >>Accept Winds in the Desert from Rezlak, the goblin at the mouth of Drygulch Ravine

step
  .goto Durotar,50.5,27.3
  .complete 834,1 >>Loot 8 Sacks of Supplies from the Stolen Supply Sacks scattered around the harpy camps in Drygulch Ravine (Dustwind harpies, lvl 9-11)

step
  .goto Durotar,46.4,22.9
  .turnin 834 >>Turn in Winds in the Desert to Rezlak
  .accept 835 >>Accept Securing the Lines

step
  .goto Durotar,53.3,23.7
  .complete 835,1 >>Kill 8 Dustwind Savages in the ravine (lvl 9-10)
  .complete 835,2 >>Kill 8 Dustwind Storm Witches (lvl 10-11)

step
  .goto Durotar,46.4,22.9
  .turnin 835 >>Turn in Securing the Lines to Rezlak

step
  .goto Durotar,34.4,44.2
  .optional >>Lost But Not Forgotten
  .complete 816,1 >>Kill Dreadmaw Crocolisks along the Southfury River, west of the Razormane grounds (lvl 9-11), until Kron's Amulet drops

step
  .goto Durotar,43.1,30.2
  .optional >>Lost But Not Forgotten
  .turnin 816 >>Turn in Lost But Not Forgotten to Misha Tor'kren

-- Razor Hill: third visit, then Skull Rock ---------------------------------------------------------------

step
  .goto Durotar,51.9,43.5
  .turnin 837 >>Turn in Encroachment to Gar'Thok (hearth to Razor Hill if it is up)

step
  .goto Durotar,52.2,43.2
  .turnin 806 >>Turn in Dark Storms to Orgnil Soulscar
  .accept 828 >>Accept Margoz

step
  .goto Durotar,50.8,43.6
  .xp 10
  .accept 840 >>Accept Conscript of the Horde from Takrin Pathseeker (level 10) — turned in at Far Watch Post in the Barrens

step
  .goto Durotar,54.4,41.3
  .class Warlock
  .accept 1506 >>Accept Gan'rul's Summons from Ophek (level 10) — the voidwalker quest starts in Orgrimmar

step
  .goto Durotar,52.0,43.7
  .class Rogue
  .accept 1859 >>Accept Therzok from Kaplak (level 10) — a hand-off in Orgrimmar

step
  .goto Durotar,54.4,42.6
  .class Shaman
  .accept 2983 >>Accept Call of Fire from Swart (level 10) — the fire totem chain, turned in at Far Watch Post in the Barrens

step
  .goto Durotar,54.2,42.5
  .class Warrior
  .accept 1505 >>Accept Veteran Uzzek from Tarshaw Jaggedscar (level 10) — turned in at Far Watch Post in the Barrens

-- Hunter pet quests (level 10) ------------------------------------------------------------------------

step
  .goto Durotar,56.1,74.2
  .class Hunter
  .accept 6069 >>Accept The Hunter's Path from Kali Remik in Sen'jin Village (a short run south from Razor Hill; it starts the pet quests at Thotar)

step
  .goto Durotar,51.8,43.5
  .class Hunter
  .turnin 6069 >>Turn in The Hunter's Path to Thotar in Razor Hill
  .accept 6062 >>Accept Taming the Beast (Surf Crawler)

step
  .goto Durotar,58.8,28.3
  .class Hunter
  .complete 6062 >>Use the Taming Rod on a Surf Crawler on the beach north-east of Razor Hill (lvl 7-8) and keep it alive until the channel ends

step
  .goto Durotar,51.8,43.5
  .class Hunter
  .turnin 6062 >>Turn in Taming the Beast to Thotar
  .accept 6083 >>Accept Taming the Beast (Armored Scorpid)

step
  .goto Durotar,54.8,36.6
  .class Hunter
  .complete 6083 >>Use the Taming Rod on an Armored Scorpid north of Razor Hill (lvl 7-8)

step
  .goto Durotar,51.8,43.5
  .class Hunter
  .turnin 6083 >>Turn in Taming the Beast to Thotar
  .accept 6082 >>Accept Taming the Beast (Dire Mottled Boar)

step
  .goto Durotar,48.3,45.9
  .class Hunter
  .complete 6082 >>Use the Taming Rod on a Dire Mottled Boar south-west of Razor Hill (lvl 6-7)

step
  .goto Durotar,51.8,43.5
  .class Hunter
  .turnin 6082 >>Turn in Taming the Beast to Thotar
  .accept 6081 >>Accept Training the Beast — Ormak Grimshot in Orgrimmar teaches you to tame for real

step
  .goto Durotar,56.3,75.1
  .class Mage
  .optional >>Ju-Ju Heaps: the level 10 mage quest means another trip to Sen'jin and the Echo Isles for one turn-in
  .accept 1884 >>Accept Ju-Ju Heaps from Un'Thuwa in Sen'jin Village

step
  .goto Durotar,68.5,84.2
  .class Mage
  .optional >>Ju-Ju Heaps
  .complete 1884,1 >>Search the Ju-Ju Heaps (piles of skulls) on the eastern Echo Isle until the Jaguero Idol drops

step
  .goto Durotar,56.3,75.1
  .class Mage
  .optional >>Ju-Ju Heaps
  .turnin 1884 >>Turn in Ju-Ju Heaps to Un'Thuwa

step
  .goto Durotar,51.5,41.6
  .vendor >>Sell and restock in Razor Hill; the Burning Blade camp north of the village (lvl 8-10) is good XP on the way to Margoz if you are not 11 yet

step
  .goto Durotar,56.4,20.0
  .turnin 828 >>Turn in Margoz to Margoz, at the hut on the north-east coast past the Burning Blade camp
  .accept 827 >>Accept Skull Rock

step
  .goto Durotar,51.9,10.8
  .complete 827,1 >>Loot 6 Searing Collars from the Burning Blade Fanatics and Apprentices inside Skull Rock, the cave north-east of Orgrimmar (lvl 9-11 — pull carefully, the cave is dense)

step
  .goto Durotar,56.4,20.0
  .turnin 827 >>Turn in Skull Rock to Margoz
  .accept 829 >>Accept Neeru Fireblade — a hand-off in Orgrimmar

-- Orgrimmar ---------------------------------------------------------------------------------------------

step
  .goto Orgrimmar,49.5,50.6
  .turnin 829 >>Turn in Neeru Fireblade to Neeru Fireblade in the Cleft of Shadow, Orgrimmar
  .accept 809 >>Accept Ak'Zeloth — turned in at Far Watch Post in the Barrens

step
  .goto Orgrimmar,32.3,35.8
  .turnin 831 >>Turn in The Admiral's Orders to Nazgrel in Grommash Hold (Valley of Wisdom)

step
  .goto Orgrimmar,48.2,45.3
  .class Warlock
  .turnin 1506 >>Turn in Gan'rul's Summons to Gan'rul Bloodeye in the Cleft of Shadow and follow the voidwalker quest he gives you

step
  .goto Orgrimmar,42.7,53.6
  .class Rogue
  .turnin 1859 >>Turn in Therzok to Therzok in the Cleft of Shadow

step
  .goto Orgrimmar,66.0,18.5
  .class Hunter
  .turnin 6081 >>Turn in Training the Beast to Ormak Grimshot in the Valley of Honor

step
  .goto Orgrimmar,45.1,63.9
  .text >>Talk to Doras, the wind rider master on the Valley of Strength tower, to learn the Orgrimmar flight path

step
  .goto Orgrimmar,54.1,68.4
  .train >>Train at your class trainer in Orgrimmar (Valley of Honor for warriors and hunters, the Cleft of Shadow for rogues, warlocks and mages, the Valley of Spirits for shamans and priests), then sell and repair

step
  .goto Orgrimmar,54.1,68.4
  .xp 11 >>Durotar's quests run out around level 11; the Barrens quests start at 10, so head out now (kill Burning Blade cultists at Skull Rock if you are short). Take the road west out of Orgrimmar's main gate toward the Barrens

step
  .zone The Barrens >>Follow the road south-west out of Durotar into the Barrens (Far Watch Post is just past the bridge)
]], "Lodestar_Guides_Horde")

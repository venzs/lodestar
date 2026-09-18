-- Lodestar Guides: Alliance — Westfall (levels 12-20), the continuation of the Human route.
--
-- DRAFT generated from the Vanilla database (Data/Vanilla.lua) with tools/router as the ordering
-- backbone; the hub order follows the classic Sentinel Hill loops: the Furlbrow and Saldean farms,
-- Sentinel Hill and a Stormwind trip for the trainers, the Jangolode Mine and the fields, the
-- Alexston Farmstead and the Gold Coast gnolls, Moonbrook and the Westfall Lighthouse, the Defias
-- Brotherhood chain (Lakeshire, SI:7, the Defias Messenger and the Traitor), the People's Militia
-- and the south coast, the Deadmines as an optional group run, then the road east through Duskwood
-- to Darkshire and on to Redridge. Every quest id and position comes from the data; the order still
-- has to be verified in play (/lode record). Forever-only quests are not in here yet.
local Guide = _G.Lodestar:GetModule("Guide")

Guide:RegisterGuide([[
#guide Alliance 12-20: Westfall
#faction Alliance
#levels 12-19
#next Alliance 20-25: Redridge Mountains
#author Lodestar
-- #levels stops at 19 so the auto-pick hands a level 20 character to the next guide; the route itself runs to 20.
#note DRAFT — generated from the Vanilla database + route optimizer; positions verified against the data, order to be verified in play.

-- Furlbrow's Pumpkin Farm and Saldean's Farm ----------------------------------------------------------------

step
  .goto Westfall,60.0,19.4
  .accept 109 >>Accept Report to Gryan Stoutmantle from Farmer Furlbrow at the Furlbrow farm, just inside Westfall (skip if Marshal Dughan already gave it to you)
  .accept 64 >>Accept The Forgotten Heirloom

step
  .goto Westfall,59.9,19.4
  .accept 36 >>Accept Westfall Stew from Verna Furlbrow
  .accept 151 >>Accept Poor Old Blanchy

step
  .goto Westfall,57.9,13.3
  .complete 151,1 >>Pick up 8 Handfuls of Oats from the Sacks of Oats around the Furlbrow farm, the road south and the Saldean fields (Rusty Harvest Golems, lvl 9-10)

step
  .goto Westfall,49.3,19.3
  .complete 64,1 >>Open Furlbrow's Wardrobe in the cottage north-west of the farm (Defias Smugglers and Trappers around it, lvl 11-13) for the pocket watch

step
  .goto Westfall,60.0,19.4
  .turnin 64 >>Turn in The Forgotten Heirloom to Farmer Furlbrow

step
  .goto Westfall,59.9,19.4
  .turnin 151 >>Turn in Poor Old Blanchy to Verna Furlbrow

step
  .goto Westfall,56.4,30.5
  .turnin 36 >>Turn in Westfall Stew to Salma Saldean at Saldean's Farm, down the road
  .accept 38 >>Accept Westfall Stew (part 2)
  .accept 22 >>Accept Goretusk Liver Pie

step
  .goto Westfall,56.0,31.2
  .accept 9 >>Accept The Killing Fields from Farmer Saldean

step
  .goto Westfall,45.9,36.1
  .complete 9,1 >>Kill 15 Harvest Watchers in the fields west of the farm (lvl 14-15 — they hit hard for their level; fight one at a time)

step
  .goto Westfall,50.4,29.4
  .complete 22,1 >>Loot 8 Goretusk Livers from Young Goretusks around the farm (lvl 12-13, 33% drop)
  .complete 38,3 >>Loot 3 Goretusk Snouts from them too

step
  .goto Westfall,56.4,30.5
  .turnin 22 >>Turn in Goretusk Liver Pie to Salma Saldean

step
  .goto Westfall,56.0,31.2
  .turnin 9 >>Turn in The Killing Fields to Farmer Saldean

-- Sentinel Hill: first visit, and the Stormwind trip -----------------------------------------------------------

step
  .goto Westfall,56.3,47.5
  .turnin 109 >>Turn in Report to Gryan Stoutmantle to Gryan Stoutmantle at the top of Sentinel Hill
  .accept 12 >>Accept The People's Militia

step
  .goto Westfall,56.4,47.6
  .accept 102 >>Accept Patrolling Westfall from Captain Danuvin, next to Gryan

step
  .goto Westfall,54.0,53.0
  .accept 153 >>Accept Red Leather Bandanas from Scout Galiaan, on the hill south-west of the tower

step
  .goto Westfall,52.9,53.7
  .hs Sentinel Hill >>Set your hearthstone at the Sentinel Hill inn (Innkeeper Heather)
  .vendor

step
  .goto Westfall,57.0,47.2
  .race Human
  .accept 6181 >>Accept A Swift Message from Quartermaster Lewis, by the tower — a free flight to Stormwind for the trainers

step
  .goto Westfall,56.6,52.6
  .race Human
  .turnin 6181 >>Turn in A Swift Message to Thor, the gryphon master below the hill
  .accept 6281 >>Accept Continue to Stormwind — Thor flies you there for free

step
  .goto Westfall,56.6,52.6
  .fly Stormwind >>Fly to Stormwind with Thor (humans fly free with Continue to Stormwind; everyone else pays the fare — it is the only class trainer trip until Lakeshire)

step
  .goto Stormwind City,74.3,47.2
  .race Human
  .turnin 6281 >>Turn in Continue to Stormwind to Osric Strang, the armorer in Old Town
  .accept 6261 >>Accept Dungar Longdrink

step
  .goto Stormwind City,78.5,45.7
  .class Warrior
  .train Ilsa Corbin >>Train at Ilsa Corbin in the Command Center, Old Town

step
  .goto Stormwind City,38.7,32.8
  .class Paladin
  .train Arthur the Faithful >>Train at Arthur the Faithful in the Cathedral of Light

step
  .goto Stormwind City,61.6,15.3
  .class Hunter
  .train Einris Brightspear >>Train at Einris Brightspear in the Dwarven District

step
  .goto Stormwind City,74.6,52.8
  .class Rogue
  .train Osborne the Night Man >>Train at Osborne the Night Man in SI:7, Old Town

step
  .goto Stormwind City,42.1,30.0
  .class Priest
  .train Brother Benjamin >>Train at Brother Benjamin in the Cathedral of Light

step
  .goto Stormwind City,38.6,79.3
  .class Mage
  .train Jennea Cannon >>Train at Jennea Cannon in the Wizard's Sanctum, Mage Quarter

step
  .goto Stormwind City,25.3,78.2
  .class Warlock
  .train Demisette Cloyce >>Train at Demisette Cloyce in the Slaughtered Lamb, Mage Quarter

step
  .goto Stormwind City,66.3,62.1
  .race Human
  .turnin 6261 >>Turn in Dungar Longdrink to Dungar Longdrink, the gryphon master above the Trade District
  .accept 6285 >>Accept Return to Lewis — a free flight back to Sentinel Hill

step
  .goto Stormwind City,66.3,62.1
  .fly Sentinel Hill >>Sell and repair, then fly back to Sentinel Hill

step
  .goto Westfall,57.0,47.2
  .race Human
  .turnin 6285 >>Turn in Return to Lewis to Quartermaster Lewis

-- North-west loop: the Jangolode Mine, the fields, the north coast -------------------------------------------------

step
  .goto Westfall,47.5,36.6
  .complete 12,1 >>Kill 15 Defias Smugglers around the Jangolode Mine, north-west of Sentinel Hill (lvl 11-12)
  .complete 12,2 >>Kill 15 Defias Trappers there too (lvl 12-13)
  .complete 153,1 >>Loot 10 Red Leather Bandanas from the same Defias

step
  .goto Westfall,43.2,49.1
  .complete 38,1 >>Loot 3 Stringy Vulture Meat from Fleshrippers around the fields (lvl 13-14)

step
  .goto Westfall,36.2,46.8
  .complete 38,4 >>Loot 3 Okra from Harvest Golems and Watchers in the fields west of the road (lvl 11-15)

step
  .goto Westfall,47.4,9.9
  .complete 38,2 >>Loot 3 Murloc Eyes from Murloc Coastrunners on the north coast, past the Jangolode Mine (lvl 12-13)

step
  .goto Westfall,46.4,15.1
  .complete 102,1 >>Loot 8 Gnoll Paws from Riverpaw Gnolls at the camps along the north coast (lvl 11-12; the Mongrels and Brutes to the west count too)

step
  .goto Westfall,56.4,30.5
  .turnin 38 >>Turn in Westfall Stew to Salma Saldean at Saldean's Farm (hearth to Sentinel Hill if it is up and walk north, or come by on the way back)

step
  .goto Westfall,56.3,47.5
  .turnin 12 >>Turn in The People's Militia to Gryan Stoutmantle at Sentinel Hill
  .accept 13 >>Accept The People's Militia (part 2)

step
  .goto Westfall,56.4,47.6
  .turnin 102 >>Turn in Patrolling Westfall to Captain Danuvin

step
  .goto Westfall,54.0,53.0
  .turnin 153 >>Turn in Red Leather Bandanas to Scout Galiaan

-- West loop: the Alexston Farmstead, the Gold Coast, Moonbrook, the lighthouse ------------------------------------------

step
  .goto Westfall,38.6,58.1
  .xp 13
  .complete 13,1 >>Kill 15 Defias Pillagers at the Alexston Farmstead, west of Sentinel Hill (lvl 14-15)
  .complete 13,2 >>Kill 15 Defias Looters there too (lvl 13-14)

step
  .goto Westfall,31.6,52.3
  .optional >>Captain Sander's treasure: the map is a rare drop from the Westfall murlocs; the footlocker is on the Gold Coast, the barrel by the Alexston Farmstead, the jug near the Jangolode Mine and the chest on the north coast
  .item 1357
  .accept 136 >>Read Captain Sander's Treasure Map and accept Captain Sander's Hidden Treasure

step
  .goto Westfall,25.9,47.8
  .optional >>Captain Sander's treasure
  .turnin 136 >>Open the Captain's Footlocker on the Gold Coast, west of the farmstead, and turn in Captain Sander's Hidden Treasure
  .accept 138 >>Accept the next part from the footlocker

step
  .goto Westfall,40.5,47.8
  .optional >>Captain Sander's treasure
  .turnin 138 >>Open the Broken Barrel north-east of the farmstead and turn in Captain Sander's Hidden Treasure
  .accept 139 >>Accept the next part from the barrel

step
  .goto Westfall,40.6,17.0
  .optional >>Captain Sander's treasure
  .turnin 139 >>Open the Old Jug west of the Jangolode Mine and turn in Captain Sander's Hidden Treasure
  .accept 140 >>Accept the last part from the jug

step
  .goto Westfall,26.0,16.9
  .optional >>Captain Sander's treasure
  .turnin 140 >>Open the Locked Chest on the north coast and turn in Captain Sander's Hidden Treasure

step
  .goto Westfall,44.6,80.3
  .xp 14
  .accept 117 >>Accept Thunderbrew from Grimbooze Thunderbrew at his still in the hills south of Moonbrook

step
  .goto Westfall,30.0,86.0
  .accept 103 >>Accept Keeper of the Flame from Captain Grayson at the Westfall Lighthouse, on the south-west coast
  .accept 152 >>Accept The Coast Isn't Clear

step
  .goto Westfall,30.0,86.0
  .xp 15
  .optional >>The Coastal Menace: Old Murk-Eye is a level 20 elite on the beach north of the lighthouse — a group quest, or come back at 20
  .accept 104 >>Accept The Coastal Menace from Captain Grayson (level 15)

step
  .goto Westfall,28.0,75.7
  .complete 152,2 >>Kill 6 Murloc Tidehunters on the beach north of the lighthouse (lvl 18-19)
  .complete 152,4 >>Kill 6 Murloc Oracles there too (lvl 17-18 — they heal; kill them first)

step
  .goto Westfall,29.0,35.6
  .complete 152,3 >>Kill 6 Murloc Warriors on the Gold Coast, further north (lvl 15-16)
  .complete 152,1 >>Kill 6 Murloc Coastrunners — the north coast, or the young ones mixed in on the Gold Coast (lvl 12-13)

step
  .goto Westfall,36.2,46.8
  .complete 103,1 >>Loot 5 Flasks of Oil from Harvest Golems and Watchers in the fields (lvl 11-15, 35% drop)
  .complete 117,1 >>Loot 5 Hops from the same golems — the Harvest Reapers south-east of Sentinel Hill drop them too (lvl 17-18)

step
  .goto Westfall,30.0,86.0
  .turnin 103 >>Turn in Keeper of the Flame to Captain Grayson at the lighthouse
  .turnin 152 >>Turn in The Coast Isn't Clear

step
  .goto Westfall,44.6,80.3
  .turnin 117 >>Turn in Thunderbrew to Grimbooze Thunderbrew

-- Sentinel Hill: the Defias Brotherhood chain (Lakeshire and SI:7) ---------------------------------------------------------

step
  .goto Westfall,56.3,47.5
  .turnin 13 >>Turn in The People's Militia to Gryan Stoutmantle at Sentinel Hill (hearth)
  .accept 14 >>Accept The People's Militia (part 3)
  .accept 65 >>Accept The Defias Brotherhood — for Wiley the Black in Lakeshire, Redridge

step
  .goto Westfall,56.6,52.6
  .xp 16
  .fly Stormwind >>Fly to Stormwind — the road from Stormwind east through Elwynn leads to Redridge and Lakeshire (a 6-minute walk past the Eastvale Logging Camp)

step
  .goto Redridge Mountains,26.5,45.3
  .turnin 65 >>Turn in The Defias Brotherhood to Wiley the Black, in the cellar of the Lakeshire inn
  .accept 132 >>Accept The Defias Brotherhood (part 2) — back to Gryan

step
  .goto Redridge Mountains,30.6,59.4
  .text >>Talk to Ariena Stormfeather, the gryphon master on the Lakeshire dock, to learn the Lakeshire flight path (Redridge is the next guide)

step
  .goto Redridge Mountains,30.6,59.4
  .fly Stormwind >>Fly back to Stormwind, then on to Sentinel Hill

step
  .goto Westfall,56.3,47.5
  .turnin 132 >>Turn in The Defias Brotherhood to Gryan Stoutmantle at Sentinel Hill
  .accept 135 >>Accept The Defias Brotherhood (part 3) — for Master Mathias Shaw in Stormwind

step
  .goto Westfall,56.6,52.6
  .fly Stormwind >>Fly to Stormwind again

step
  .goto Stormwind City,75.8,59.8
  .turnin 135 >>Turn in The Defias Brotherhood to Master Mathias Shaw in the SI:7 building, Old Town
  .accept 141 >>Accept The Defias Brotherhood (part 4) — back to Gryan

step
  .goto Stormwind City,65.4,21.2
  .optional >>Wilder Thistlenettle's two quests take you into the Deadmines tunnels below Moonbrook (undead miners, lvl 17-18) and back to Stormwind — good XP if you run the Deadmines later
  .accept 168 >>Accept Collecting Memories from Wilder Thistlenettle in the Dwarven District
  .accept 167 >>Accept Oh Brother. . .

step
  .goto Stormwind City,66.3,62.1
  .train >>Train new skills at your class trainer in Stormwind, sell and repair, then fly back to Sentinel Hill
  .fly Sentinel Hill

step
  .goto Westfall,56.3,47.5
  .turnin 141 >>Turn in The Defias Brotherhood to Gryan Stoutmantle at Sentinel Hill
  .accept 142 >>Accept The Defias Brotherhood (part 5) — the Defias Messenger

-- South: the Defias Messenger, Moonbrook, the Traitor ---------------------------------------------------------------------

step
  .goto Westfall,44.5,69.6
  .complete 142,1 >>Kill the Defias Messenger (lvl 14-15) — he walks the road between Moonbrook and the Alexston Farmstead — and take the Mysterious Message

step
  .goto Westfall,46.2,79.2
  .complete 14,1 >>Kill 15 Defias Pathstalkers in the Dagger Hills south of Moonbrook (lvl 15-16)
  .complete 14,3 >>Kill 15 Defias Knuckledusters there too (lvl 16-17)
  .complete 14,2 >>Kill 10 Defias Highwaymen (lvl 17-18)

step
  .goto Westfall,56.3,47.5
  .turnin 142 >>Turn in The Defias Brotherhood to Gryan Stoutmantle at Sentinel Hill (hearth)
  .turnin 14 >>Turn in The People's Militia

step
  .goto Westfall,55.7,47.5
  .accept 155 >>Accept The Defias Brotherhood (part 6) from The Defias Traitor, next to Gryan — he walks you to the Deadmines entrance below Moonbrook (Defias attack on the way, lvl 15-17; keep him alive)

step
  .goto Westfall,38.0,77.5
  .complete 155 >>Follow the Traitor to the mine entrance in Moonbrook until he points out the Deadmines

step
  .goto Westfall,56.3,47.5
  .xp 17
  .turnin 155 >>Turn in The Defias Brotherhood to Gryan Stoutmantle at Sentinel Hill (hearth if it is up; the Moonbrook Defias on the way back are the Red Silk Bandana droppers you come back for)

step
  .goto Westfall,56.7,47.3
  .accept 214 >>Accept Red Silk Bandanas from Scout Riell, next to Gryan (kill the Moonbrook Defias again if you did not pick the bandanas up on the way)

step
  .goto Westfall,56.3,47.5
  .optional >>The Deadmines (lvl 17-21 dungeon): The Defias Brotherhood (VanCleef), plus Collecting Memories and Oh Brother in the tunnels outside, are worth a group run at 17+
  .accept 166 >>Accept The Defias Brotherhood (part 7) from Gryan Stoutmantle — VanCleef's head

step
  .goto Westfall,42.2,74.5
  .complete 214,1 >>Loot 10 Red Silk Bandanas from the Defias in Moonbrook and the Deadmines tunnels (lvl 15-17)

step
  .goto Westfall,41.6,81.7
  .optional >>The Deadmines
  .complete 168,1 >>Loot 8 Miners' Union Cards from the Skeletal Miners, Undead Excavators and Dynamiters in the tunnels outside the Deadmines instance (lvl 17-18)
  .complete 167,1 >>Kill Foreman Thistlenettle in the tunnels (lvl 20) and take his badge

step
  .goto Westfall,42.2,82.6
  .optional >>The Deadmines
  .complete 166,1 >>Kill Edwin VanCleef at the end of the Deadmines with a group and take his head

step
  .goto Westfall,56.7,47.3
  .turnin 214 >>Turn in Red Silk Bandanas to Scout Riell at Sentinel Hill (hearth)

step
  .goto Westfall,56.3,47.5
  .optional >>The Deadmines
  .turnin 166 >>Turn in The Defias Brotherhood to Gryan Stoutmantle

step
  .goto Westfall,29.3,75.9
  .optional >>The Coastal Menace
  .complete 104,1 >>Kill Old Murk-Eye on the beach north of the lighthouse (lvl 20 elite, with a pack of Murloc Tidehunters) and take his scale

step
  .goto Westfall,30.0,86.0
  .optional >>The Coastal Menace
  .turnin 104 >>Turn in The Coastal Menace to Captain Grayson at the lighthouse

step
  .goto Stormwind City,65.4,21.2
  .optional >>The Deadmines
  .turnin 168 >>Turn in Collecting Memories to Wilder Thistlenettle in Stormwind (fly from Sentinel Hill)
  .turnin 167 >>Turn in Oh Brother. . .

-- Duskwood entry and the road to Redridge -------------------------------------------------------------------------------------

step
  .goto Westfall,52.9,53.7
  .xp 19 >>You should be level 19 by now; if not, the Defias in the Dagger Hills and the Harvest Reapers south-east of Sentinel Hill are good XP, and a Deadmines run gets you to 20. Sell, repair, then take the road east out of Westfall into Duskwood

step
  .goto Duskwood,77.5,44.3
  .text >>Follow the road east through Duskwood (Raven Hill, then the long road to Darkshire — the wolves and spiders are lvl 20-25, stay on the road) and talk to Felicia Maline, the gryphon master in Darkshire, to learn the flight path

step
  .goto Duskwood,75.3,48.7
  .xp 17
  .accept 163 >>Accept Raven Hill from Elaine Carevin in Darkshire — for Jitters at Raven Hill, when you come back for Duskwood at 20+. Then take the road north out of Darkshire, through the Three Corners crossing, into Redridge Mountains
]], "Lodestar_Guides_Alliance")

-- Generate a Lodestar guide for one map from the merged database.
--
--   lua5.1 tools/router/generate_route.lua <uiMapID> [options] > Lodestar_Guides_X/Zone.lua
--
--   --name "Skyborne 1-12: Zephras Isle"   guide name (#guide)
--   --faction Both|Horde|Alliance          default Both
--   --race Skyborne                        optional #race
--   --levels 1-12                          optional #levels
--   --next "Next guide name"               optional #next
--   --next-horde "Guide"                  #next for Horde characters only (neutral races)
--   --next-alliance "Guide"               #next for Alliance characters only
--   --zone "Zephras Isle"                  name used in .goto (default: the map id)
--   --max-level 12                         drop quests above this level
--   --min-level 18                       drop quests below this level (zone easter eggs)
--
-- This is the piece that makes Lodestar different from a guide pack: the route is DERIVED, so it
-- exists for content nobody has hand-authored. It reads the same three sources the addon does --
-- Vanilla (pfQuest), ATT (quest givers, objective providers, the sourceQuests chain) and the beta
-- harvest (titles, levels, objectives, positions players actually recorded) -- and orders them.
--
-- Ordering is precedence-first, travel-second, which is the only order that is ever correct:
--   1. A quest cannot be accepted before its prerequisites are turned in, so the chain graph is a
--      hard constraint and geography is a preference. Walking order that breaks a chain is not a
--      faster route, it is a broken one.
--   2. Among quests whose prerequisites are satisfied, take the nearest, and take everything the
--      giver you are standing in front of has to offer before moving on.
--   3. Turn a quest in when its objectives are done and you are passing its ender anyway.
--
-- What it cannot invent: a quest with no recorded giver is emitted as an optional note rather than
-- a step, because pointing an arrow at a guess is worse than saying nothing.
local args = { ... }

local function opt(name, default)
	for i = 1, #args - 1 do
		if args[i] == "--" .. name then return args[i + 1] end
	end
	return default
end

local mapID = tonumber(args[1])
if not mapID then
	io.stderr:write("usage: generate_route.lua <uiMapID> [--name ...] [--race ...] [--levels ...]\n")
	os.exit(2)
end

local NAME = opt("name", "Generated " .. mapID)
local FACTION = opt("faction", "Both")
local RACE = opt("race")
local LEVELS = opt("levels")
local NEXT = opt("next")
-- A neutral race needs two successors, not one: the Skyborne choose a faction at creation and
-- level 12 sends the two halves to different continents. Emitted as "#next Horde: <name>".
local NEXT_HORDE = opt("next-horde")
local NEXT_ALLIANCE = opt("next-alliance")
local ZONE = opt("zone", tostring(mapID))
local MAX_LEVEL = tonumber(opt("max-level", "99"))
-- Zones keep a few quests far below their own range -- an easter egg, a breadcrumb meant to be
-- picked up elsewhere. Without a floor, a 20-25 route opens on "Accept CLUCK! (lvl 1) from Chicken",
-- which is both wrong and the first thing anybody sees.
local MIN_LEVEL = tonumber(opt("min-level", "0"))
-- The levels the route claims to carry a character through. Used for the level estimate below, and
-- as the ceiling on what a quest may REQUIRE: a route that leaves you at 25 cannot include a quest
-- you are not allowed to accept until 26.
local START_LEVEL = tonumber((LEVELS or ""):match("^(%d+)")) or 1
local END_LEVEL = tonumber((LEVELS or ""):match("%-(%d+)")) or (START_LEVEL + 11)

-- Load the same data the addon loads ---------------------------------------------------------------

local Guide = {}
_G.Lodestar = { GetModule = function() return Guide end }
dofile("Lodestar_Guide/Data/Vanilla.lua")
dofile("Lodestar_Guide/Data/ATT.lua")
dofile("Lodestar_Guide/Data/Forever.lua")
local V, A, F = Guide.VanillaData, Guide.ATTData, Guide.ForeverData

-- Facts about a quest, from whichever source knows -------------------------------------------------

local function firstNPC(t) return t and t.npcs and t.npcs[1] or nil end

-- Forward declaration: factionNPC needs npcUsable, which is defined below with the other NPC
-- lookups, and Lua 5.1 resolves a local only after its declaration.
local npcUsable
local function factionNPC(t)
	if not (t and t.npcs) then return nil end
	for _, id in ipairs(t.npcs) do
		if npcUsable(id, FACTION) then return id end
	end
	return t.npcs[1]
end

--- Position of an NPC on this map: x, y (percent) or nil.
---
--- The two sources spell a coordinate differently and only one of them was being read. The harvest
--- writes { 0, x, y, m = uiMapID }; pfQuest writes { zoneID, x, y } with no m at all, so every
--- pfQuest position silently failed to match and the generator could only ever build a route for a
--- zone somebody had already walked. That is why it produced nothing for any vanilla zone.
---
--- The map id argument is therefore read in whichever namespace the entry uses -- a uiMapID for
--- harvested data, a pfQuest areaID for the vanilla database. They are separate numbering schemes
--- and a value can be valid in both; in practice the harvest only covers zones that exist on the
--- beta, so a collision would need the same number to name a beta zone and a vanilla one. Worth
--- knowing rather than worth guarding, and the step count in the header makes a wrong map obvious.
local function npcPos(id)
	if not id then return nil end
	for _, store in ipairs({ F.npcs, A.npcs, V.npcs }) do
		local e = store and store[id]
		if e then
			if e.c then
				for _, c in ipairs(e.c) do
					if c.m == mapID then return c[2], c[3] end
					if c.m == nil and c[1] == mapID then return c[2], c[3] end
				end
			end
			if e.map == mapID and e.x then return e.x, e.y end
		end
	end
	return nil
end

--- Which faction an NPC will talk to: "A", "H", "AH", or nil when the data does not say.
local function npcFaction(id)
	for _, store in ipairs({ A.npcs, V.npcs }) do
		local e = store and store[id]
		if e and e.f then return e.f end
	end
	return nil
end

--- Can a character of this faction take a quest from, or hand one to, this NPC?
---
--- The race bitmask on the quest is not enough and never was. Most quests carry no race restriction
--- at all -- in a contested zone the faction split is expressed by WHO stands there, not by a flag
--- on the quest. Filtering on the bitmask alone produced an "Alliance" Ashenvale route in which 22
--- of 57 quests were taken from Horde NPCs: Je'neu Sancrea at Zoram'gar, the whole Warsong Lumber
--- Camp chain, Senani Thunderheart at Splintertree. Every one of those is a corpse run.
---
--- Unknown is treated as usable. Three and a half thousand NPCs carry no faction in the data and
--- most of them are ordinary neutral quest givers; refusing those would empty the routes.
function npcUsable(id, faction)
	if faction == "Both" or not id then return true end
	local f = npcFaction(id)
	if not f or f == "AH" then return true end
	return f == faction:sub(1, 1)
end

local function npcName(id)
	for _, store in ipairs({ F.npcs, A.npcs, V.npcs }) do
		local e = store and store[id]
		if e and e.n then return e.n end
	end
	return nil
end

local quests = {}
-- Everything placeable in this zone, including what the level window will reject. Kept separately
-- because the window must not be allowed to sever a chain: see the selection pass below.
local candidates = {}

-- Classic's class bitmask. A quest with no class field is open to every class.
--
-- Without this a general route hands a warrior "Journey to the Marsh", which is a mage quest: the
-- step can never be completed and the guide parks on it. The engine already filters steps by class
-- (`.class Mage`), it was just never being told.
local CLASS_NAME = {
	[1] = "Warrior", [2] = "Paladin", [4] = "Hunter", [8] = "Rogue", [16] = "Priest",
	[64] = "Shaman", [128] = "Mage", [256] = "Warlock", [1024] = "Druid",
}

--- "Mage" / "Priest,Warlock" for a class bitmask, or nil when the quest is open to everyone.
local function classNames(mask)
	if not mask or mask == 0 then return nil end
	local out, bit, m = {}, 1, mask
	local all = 0
	for _ in pairs(CLASS_NAME) do all = all + 1 end
	for _ = 1, 11 do
		if (m % 2) == 1 and CLASS_NAME[bit] then out[#out + 1] = CLASS_NAME[bit] end
		m, bit = math.floor(m / 2), bit * 2
	end
	if #out == 0 or #out >= all then return nil end
	return table.concat(out, ",")
end

-- Classic's race bitmask, as pfQuest stores it. A quest with no race field is open to everyone.
local RACE_BIT = { human = 1, orc = 2, dwarf = 4, nightelf = 8, undead = 16, tauren = 32, gnome = 64, troll = 128 }
local FACTION_MASK = {
	Alliance = RACE_BIT.human + RACE_BIT.dwarf + RACE_BIT.nightelf + RACE_BIT.gnome,   -- 77
	Horde    = RACE_BIT.orc + RACE_BIT.undead + RACE_BIT.tauren + RACE_BIT.troll,      -- 178
}

--- Does a race bitmask include any race of this faction? Lua 5.1 has no bitwise operators, so this
--- walks the eight bits rather than pretending band exists.
local function maskAllows(mask, faction)
	if not mask or mask == 0 then return true end
	local want = FACTION_MASK[faction]
	if not want then return true end                    -- "Both": no filtering to do
	local m, w, bit = mask, want, 1
	for _ = 1, 8 do
		if (m % 2) == 1 and (w % 2) == 1 then return true end
		m, w, bit = math.floor(m / 2), math.floor(w / 2), bit * 2
	end
	return false
end

--- Where a quest's objectives are, according to the vanilla database.
---
--- pfQuest stores objectives as REFERENCES rather than coordinates -- `obj = { npcs, objs, items,
--- areas }` -- with the positions hanging off the NPC, object and area records instead. The harvest
--- and ATT both store `spots` already resolved, so the generator read only those two and every
--- vanilla zone emitted "go and do this" steps with nothing for the arrow to point at: 124 of them
--- across six routes, which was every no-`.goto` warning the guide lint reported. Prerequisites are
--- already taken as the union of ATT and pfQuest for exactly this reason -- the sources are partial
--- in different places -- and objective positions are no different.
---
--- A quest item is two hops out: the item names the NPCs that drop it and those NPCs carry the
--- positions. Worth following, because "collect 8 Mangy Claws" is the shape most kill objectives
--- take in the original game.
local function vanillaObjSpots(vq, map)
	if not (vq and vq.obj) then return nil end
	local found = {}
	local function take(list)
		for _, c in ipairs(list or {}) do
			-- Vanilla coordinates are {areaID, x, y}; the harvest's carry the map in `m`. Both shapes
			-- turn up here because the two databases were imported by different tools.
			if c.m == map or (c.m == nil and c[1] == map) then
				found[#found + 1] = { 0, c[2], c[3], m = map }
			end
		end
	end
	for _, id in ipairs(vq.obj.npcs or {}) do take(V.npcs and V.npcs[id] and V.npcs[id].c) end
	for _, id in ipairs(vq.obj.objs or {}) do take(V.objs and V.objs[id] and V.objs[id].c) end
	for _, id in ipairs(vq.obj.areas or {}) do take(V.areas and V.areas[id] and V.areas[id].c) end
	for _, id in ipairs(vq.obj.items or {}) do
		local it = V.items and V.items[id]
		for _, drop in ipairs(it and it.npcs or {}) do take(V.npcs and V.npcs[drop[1]] and V.npcs[drop[1]].c) end
		for _, drop in ipairs(it and it.objs or {}) do take(V.objs and V.objs[drop[1]] and V.objs[drop[1]].c) end
	end
	if #found == 0 then return nil end

	-- One position has to stand for the whole objective. An arbitrary spawn is a poor choice: a mob
	-- with sixty spawn points spread across the zone would send the arrow to whichever sorted first.
	-- Take the spawn with the most neighbours within a short radius -- the middle of the densest
	-- camp -- and take a REAL spawn rather than the average of several, because the average of two
	-- camps on opposite banks of a river is the river.
	local best, bestScore = found[1], -1
	for _, a in ipairs(found) do
		local score = 0
		for _, b in ipairs(found) do
			local dx, dy = a[2] - b[2], a[3] - b[3]
			if dx * dx + dy * dy <= 64 then score = score + 1 end
		end
		if score > bestScore then best, bestScore = a, score end
	end
	-- Keyed by objective index, like the harvest's own spots. One entry: pfQuest's references are
	-- per quest, not per objective, so claiming to know which objective this is would be a lie.
	return { [1] = { best } }
end

-- Every quest any source knows about. V.quests is the vanilla database and carries the 4,400-odd
-- quests of the original game; leaving it out of this union is why a contested or high-level zone
-- generated an empty route no matter which map id it was given.
local ids = {}
for qid in pairs(F.quests or {}) do ids[qid] = true end
for qid in pairs(A.quests or {}) do ids[qid] = true end
for qid in pairs(V.quests or {}) do ids[qid] = true end

for qid in pairs(ids) do
	local fq, aq, vq = (F.quests or {})[qid], (A.quests or {})[qid], (V.quests or {})[qid]
	-- Trimmed: a handful of titles in the source databases carry a trailing space ("Other Fish to
	-- Fry "), which ends up as trailing whitespace inside the guide's long string and trips luacheck.
	-- Better fixed where the text is read than papered over in the linter config.
	local title = (fq and fq.t) or (vq and vq.t)
	if type(title) == "string" then title = title:match("^%s*(.-)%s*$") end
	local lvl = (fq and fq.lvl) or (aq and aq.lvl) or (vq and vq.lvl)
	-- The FIRST giver of the right faction, not the first giver. A quest offered in every capital
	-- lists one NPC per city -- "Journey to the Marsh" names Ursyn Ghull in Orgrimmar and Bink in
	-- Ironforge -- and taking whichever happens to be first in the list sends half the players to a
	-- city they cannot enter.
	local giver = factionNPC(fq and fq.start) or factionNPC(aq and aq.start) or factionNPC(vq and vq.start)
	-- The ender, and whether one is actually known. Defaulting to the giver is right for the common
	-- case -- most quests are handed back to whoever gave them -- but not when the quest ends at a
	-- world OBJECT: a shrine or a strongbox is not an NPC, firstNPC finds nothing, and silently
	-- using the giver's position points the turn-in arrow across the zone.
	local enderNPC = factionNPC(fq and fq["end"]) or factionNPC(aq and aq["end"]) or factionNPC(vq and vq["end"])
	local enderObj = (vq and vq["end"] and vq["end"].objs and vq["end"].objs[1])
		or (aq and aq["end"] and aq["end"].objs and aq["end"].objs[1])
	local ender = enderNPC or (not enderObj and giver) or nil
	local gx, gy = npcPos(giver)
	if not gx then
		-- fall back to a recorded accept position even when the giver NPC is unknown
		local at = (fq and fq.acceptAt) or (aq and aq.acceptAt)
		if at and at.m == mapID then gx, gy = at[2], at[3] end
	end
	local ex, ey = npcPos(ender)
	if not ex and enderObj then
		-- The object database knows where a shrine or a chest stands; the NPC one never will.
		local o = V.objs and V.objs[enderObj]
		if o and o.c then
			for _, c in ipairs(o.c) do
				if c.m == mapID or (c.m == nil and c[1] == mapID) then ex, ey = c[2], c[3] break end
			end
		end
	end
	if not ex then
		-- A recorded turn-in position, even when the ender NPC itself was never identified. This is
		-- what the client's own arrow for a completed quest gives, so it exists for far more quests
		-- than a first-hand sighting of the ender does.
		local at = (fq and fq.turninAt) or (aq and aq.turninAt)
		if at and at.m == mapID then ex, ey = at[2], at[3] end
	end
	-- Both sources' prerequisites, not whichever one answers first. They disagree: for Underbelly
	-- Scales, ATT names quest 119 and pfQuest names 118, and taking ATT's answer alone let the route
	-- accept it while The Price of Shoes was still in the log. Neither list is wrong, they are
	-- partial, so the union is the real constraint.
	local prev
	do
		-- Written out rather than looped over { aq.pre, vq.pre }: when ATT has no prerequisites for
		-- a quest that list is { nil, {...} }, and ipairs stops dead at the first nil -- so pfQuest's
		-- answer was never read for exactly the quests where it was the only answer. Warsong Saw
		-- Blades got accepted twenty steps before Warsong Supplies because of it.
		local seen, union = {}, {}
		local function take(src)
			for _, p in ipairs(src or {}) do
				if not seen[p] then seen[p] = true union[#union + 1] = p end
			end
		end
		take(aq and aq.pre)
		take(vq and vq.pre)
		prev = #union > 0 and union or nil
	end
	-- objectives: text and count from the harvest, positions from either side
	local objectives = fq and fq.o or nil
	-- Where that objective actually is: harvest, then ATT, then the vanilla database resolved on the
	-- spot. The order is deliberate -- a position somebody walked to on this build beats a vanilla
	-- spawn table that predates whatever Forever changed about the zone, so pfQuest is the answer of
	-- last resort rather than the first.
	--
	-- A source counts only if it yields a position IN THIS ZONE. Chaining these with `or` on the
	-- mere presence of a `spots` table looks equivalent and is not: a quest the harvest saw in a
	-- neighbouring zone has a spots table full of coordinates that are all elsewhere, which
	-- short-circuits the chain and returns nothing, with a perfectly good vanilla position sitting
	-- unread. That was 31 steps still missing their arrow after the vanilla fallback went in.
	--
	-- Resolved once here rather than reached back into at flatten time: one place decides what a
	-- quest's objective position is, alongside the giver's and the ender's.
	local function spotIn(tbl)
		-- Any objective's position, not objective 1's. The indices are per objective and a quest
		-- whose first objective is off-map may well have a later one standing in this zone.
		for _, list in pairs(tbl or {}) do
			for _, spot in ipairs(list) do
				if spot.m == mapID then return spot[2], spot[3] end
			end
		end
	end
	local ox, oy = spotIn(fq and fq.spots)
	if not ox then ox, oy = spotIn(aq and aq.spots) end
	if not ox then ox, oy = spotIn(vanillaObjSpots(vq, mapID)) end
	-- A contested zone's quest list is two routes interleaved. Without this an Alliance guide for
	-- Ashenvale sends the player to Splintertree Post, which is a Horde camp that will kill them.
	-- Both tests, because they catch different things: the bitmask covers a quest restricted to
	-- particular races, and the NPC's own faction covers the far more common case of a quest that is
	-- open to everyone but given by somebody who will not speak to you.
	local allowed = maskAllows(vq and vq.race, FACTION)
		and npcUsable(giver, FACTION) and npcUsable(ender, FACTION)
	-- A quest whose hard minimum is above where this route leaves the player cannot be part of it:
	-- they would reach the end of the zone still unable to accept it. The balanced level may sit a
	-- little past the range (that is what --max-level is for); the minimum may not.
	local hardMin = (vq and vq.min) or (aq and aq.min)
	local reachable = not hardMin or hardMin <= END_LEVEL
	local inRange = reachable and (not lvl or (lvl <= MAX_LEVEL and lvl >= MIN_LEVEL))
	if gx and allowed then
		candidates[qid] = {
			inRange = inRange,
			id = qid, t = title, lvl = lvl, giver = giver, ender = ender,
			gx = gx, gy = gy, ex = ex or gx, ey = ey or gy,
			-- Whether that turn-in position is real or borrowed from the giver. "Elmore's Task" is
			-- taken in Redridge and handed in to Grimand Elmore, who stands in Ironforge; falling
			-- back to the giver's spot points the arrow at a patch of Lakeshire and calls it the
			-- turn-in. A step with no position says "this is elsewhere", which is true. A step with
			-- the wrong position says something false, confidently.
			-- Three different situations, and collapsing them loses the route.
			--   * the ender is known and stands here          -> point at it
			--   * the ender is known and stands somewhere else -> an optional breadcrumb, no arrow
			--   * the ender is not known at all               -> fall back to the giver and SAY so
			-- The third is the normal state for a freshly harvested zone: nobody has handed the
			-- quest in while Lodestar was watching, so there is no ender on record. Treating that
			-- as "somewhere else" turned every turn-in in Zephras Isle into an optional step with
			-- no arrow -- which in speed-run mode the engine skips entirely.
			enderOffMap = ex == nil and (enderNPC or enderObj) ~= nil,
			enderUnknown = ex == nil and (enderNPC or enderObj) == nil,
			prev = prev, o = objectives, ox = ox, oy = oy,
			-- The quest's own hard gate. `lvl` is the level it is BALANCED for and a route may
			-- reasonably offer that a little early; `min` is the level below which the client simply
			-- refuses to hand it over. Scheduling below `min` produces a step nobody can action.
			min = (vq and vq.min) or (aq and aq.min) or nil,
			classes = classNames(vq and vq.class),
		}
	end
end

-- Which candidates actually make the route ---------------------------------------------------------
--
-- The level window trims a zone's easter eggs and its out-of-range content, and it must not be
-- allowed to sever a chain. "The Hermit" is level 17 and Duskwood's route floors at 18, so the floor
-- dropped it -- and the route then went on to offer "Supplies from Darkshire", which the client will
-- not hand over until The Hermit has been turned in. A step nobody can action is worse than one a few
-- levels under, so a quest that opens something the route keeps comes back in regardless of the
-- window.
--
-- `prev` is a list of ALTERNATIVES, so only one of them needs pulling in: the one closest to the
-- window, being the one the player is likeliest to be the right level for. Run to a fixpoint,
-- because a prerequisite has prerequisites of its own.
for qid, q in pairs(candidates) do
	if q.inRange then quests[qid] = q end
end

local function levelGap(q)
	if not q or not q.lvl then return 0 end
	if q.lvl < MIN_LEVEL then return MIN_LEVEL - q.lvl end
	if q.lvl > MAX_LEVEL then return q.lvl - MAX_LEVEL end
	return 0
end

local pulled = true
while pulled do
	pulled = false
	for _, q in pairs(quests) do
		local satisfied, best = false, nil
		for _, p in ipairs(q.prev or {}) do
			if quests[p] then satisfied = true break end
			if candidates[p] and (not best or levelGap(candidates[p]) < levelGap(candidates[best])) then
				best = p
			end
		end
		if not satisfied and best then
			quests[best] = candidates[best]
			pulled = true
		end
	end
end

-- Order: precedence first, travel second -----------------------------------------------------------

local function dist(ax, ay, bx, by)
	if not (ax and bx) then return 1e6 end
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

--- Prerequisites that matter here: ones we are also going to do. A chain that starts off this map
--- is not a constraint we can satisfy, so it is not one we should enforce.
---
--- pfQuest's `pre` is a list of ALTERNATIVES -- any one of them opens the quest -- so a quest is
--- blocked only while none of the ones we are also doing has been turned in. Requiring all of them
--- would deadlock a route wherever two branches lead to the same quest and only one is walked.
local function blockers(q, all)
	local out = {}
	for _, p in ipairs(q.prev or {}) do
		if all[p] then out[#out + 1] = p end
	end
	return out
end

--- True while none of the prerequisites we are also scheduling has been turned in.
---
--- pfQuest's `pre` is a list of alternatives: any one of them opens the quest. Requiring all of
--- them was tried and is worse -- it deadlocks wherever two branches converge, and the deadlock
--- fallback then schedules something genuinely out of order, which is the failure this was meant to
--- prevent. The remaining cosmetic case (unblocked by one alternative while another is handed in
--- later) is handled as a preference in the sort below, not as a constraint.
local function stillBlocked(q, all, done)
	local list = blockers(q, all)
	if #list == 0 then return false end
	for _, p in ipairs(list) do
		if done[p] then return false end
	end
	return true
end

local pending = {}
local count = 0
for qid, q in pairs(quests) do pending[qid] = q count = count + 1 end

local order = {}
local accepted, done = {}, {}
local cx, cy                          -- where the route currently stands
local guard = 0

-- Level is a real constraint, not a tie-break. The first draft of this route opened with a level 5
-- quest because its giver stood two yards from the level 1 giver, and a character walking in at
-- level 1 simply cannot take it -- the step would sit there unfinishable while the rest of the zone
-- went undone. So the route carries an estimated level and will not schedule a quest far above it.
--
-- The estimate is deliberately crude: quests turned in, over a starting zone's rough pace. Nothing
-- better is available -- per-quest XP is only recorded where a player has actually turned that quest
-- in, and the XP-per-level table is thinner still -- and a crude estimate applied consistently beats
-- a precise one that exists for three quests out of seventeen.
-- How many quests a level costs, derived from the route's own claim rather than assumed.
--
-- A fixed 2.5 is about right for a starting zone and badly wrong everywhere else: levels get far
-- more expensive as they go, and a 20-25 route with sixty quests was emitting twenty-four level
-- checkpoints and claiming to carry the player to 44. The declared #levels range is the honest
-- number -- it is the designer's statement of what this route delivers -- so the pace is just the
-- quests available divided by the levels promised. The floor keeps a thin route (one somebody has
-- barely harvested yet) from claiming a level every quest.
local ACCEPT_GRACE = 3       -- a quest is offered a few levels before its own level
local MIN_QUESTS_PER_LEVEL = 2.5

-- Where the character is when they walk in. This used to be hard-coded to 1, which is right for a
-- starting zone and wrong for every other route: a 20-25 guide estimated its player at level 1 and
-- so refused to schedule anything above level 4 until it had ordered a dozen quests, which reversed
-- the route. The declared #levels range is the answer and it is already on the command line.
local QUESTS_PER_LEVEL = MIN_QUESTS_PER_LEVEL
if END_LEVEL > START_LEVEL and count > 0 then
	QUESTS_PER_LEVEL = math.max(MIN_QUESTS_PER_LEVEL, count / (END_LEVEL - START_LEVEL))
end

--- Where a character is estimated to be this far into the route, never past what it promises.
local function estimatedLevel(turnedIn)
	local level = START_LEVEL + math.floor(turnedIn / QUESTS_PER_LEVEL)
	return math.min(level, END_LEVEL)
end

local turnedIn = 0
local announcedLevel = START_LEVEL

while count > 0 and guard < 500 do
	guard = guard + 1
	-- Everything whose prerequisites are already turned in.
	local ready = {}
	for qid, q in pairs(pending) do
		-- Against `quests`, the whole set, not against `pending`. A quest leaves `pending` the moment
		-- it is ACCEPTED, so asking "is my prerequisite still pending?" answers no as soon as it has
		-- been picked up -- and the route then schedules the dependent quest before the prerequisite
		-- has been handed in. That is how Redridge ended up accepting Underbelly Scales while The
		-- Price of Shoes was still in the log. `done` is the only thing that means turned in.
		if not stillBlocked(q, quests, done) then ready[#ready + 1] = q end
	end
	-- Of those, the ones a character this far into the zone could actually accept. If that leaves
	-- nothing, the estimate is behind the content rather than the content being wrong, so the lowest
	-- remaining level is taken anyway -- never stall the route over a guess.
	local level = estimatedLevel(turnedIn)
	local inLevel = {}
	for _, q in ipairs(ready) do
		-- Grace applies to the balanced level only. The hard minimum is not negotiable: a step that
		-- says "accept this" for a quest the character cannot be given is a wall, not a hint.
		if (q.lvl or 1) <= level + ACCEPT_GRACE and (q.min or 1) <= level then
			inLevel[#inLevel + 1] = q
		end
	end
	if #inLevel > 0 then
		ready = inLevel
	else
		-- Nothing left that this character could accept yet. That is not a reason to schedule it
		-- anyway and pretend: it is the moment a guide says "you should be 25 by now, and if you are
		-- not, go and make up the difference". Raise the checkpoint to what the remaining content
		-- actually requires and say why, which is what the hand-written routes do at the same point.
		local needed
		for _, q in ipairs(ready) do
			local m = q.min or q.lvl or 1
			if not needed or m < needed then needed = m end
		end
		if needed and needed > announcedLevel then
			announcedLevel = needed
			order[#order + 1] = { kind = "xp", level = needed, grind = true }
		end
	end
	if #ready == 0 then
		-- A cycle, or a chain whose head we cannot see: take the lowest level and carry on rather
		-- than dropping quests silently.
		for _, q in pairs(pending) do ready[#ready + 1] = q end
		table.sort(ready, function(a, b) return (a.lvl or 99) < (b.lvl or 99) end)
		ready = { ready[1] }
	end
	-- Nearest ready quest, with content above the estimated level costing extra to visit. A pure
	-- distance sort sends the route at whatever giver happens to stand closest, which in a starting
	-- village means a level 5 quest gets picked up before the level 2 ones twenty yards further on
	-- -- and a quest done well above its level is XP thrown away. Distance is in map percent, so a
	-- level of overshoot costing a percent and a half of the map is about the right trade in a zone
	-- this size: it reorders neighbours without sending anyone across the map.
	local OVERSHOOT_COST = 1.5
	-- A quest something else pending is waiting on goes first, all else being close. Alternatives
	-- mean a chain can legally be entered part way, but a route that hands in The Lost Tools twenty
	-- steps after the quest it unlocks reads as broken even when it runs correctly. A discount
	-- rather than a rule: it reorders neighbours without dragging the route across the zone.
	local PREREQ_BONUS = 4
	local neededBy = {}
	for _, q in pairs(pending) do
		for _, p in ipairs(q.prev or {}) do neededBy[p] = (neededBy[p] or 0) + 1 end
	end
	local function score(q)
		return dist(cx, cy, q.gx, q.gy)
			+ math.max(0, (q.lvl or 1) - level) * OVERSHOOT_COST
			- (neededBy[q.id] and PREREQ_BONUS or 0)
	end
	table.sort(ready, function(a, b)
		local sa, sb = score(a), score(b)
		if math.abs(sa - sb) > 0.01 then return sa < sb end
		return (a.lvl or 99) < (b.lvl or 99)
	end)
	local pick = ready[1]
	-- Take everything this giver offers that is also ready: you are standing right there.
	local here = {}
	for _, q in ipairs(ready) do
		if q.giver and pick.giver and q.giver == pick.giver then here[#here + 1] = q end
	end
	if #here == 0 then here = { pick } end
	table.sort(here, function(a, b) return (a.lvl or 99) < (b.lvl or 99) end)
	order[#order + 1] = { kind = "hub", x = pick.gx, y = pick.gy, npc = pick.giver, quests = here }
	for _, q in ipairs(here) do
		accepted[q.id] = true
		pending[q.id] = nil
		count = count - 1
	end
	-- Do them, then hand them back, in the order they were handed over.
	--
	-- Walking the objectives nearest-first from the giver was tried and reverted: it changed one
	-- route of six and made its backtracking slightly worse (0.58 -> 0.60), because a greedy walk
	-- ends wherever it ends and the return leg pays for it. The out-and-back in these routes is not
	-- a scheduling mistake to be optimised away -- it is accept here, go out, come back, which is
	-- what questing is. A hub's quests are few enough that their order barely moves the total.
	for _, q in ipairs(here) do
		order[#order + 1] = { kind = "do", quest = q }
	end
	-- One turn-in stop PER QUEST, at that quest's own ender.
	--
	-- This used to emit a single stop for the whole hub, positioned at one representative quest's
	-- ender, and then list every quest in the hub under it. Four quests taken from one NPC do not
	-- come back to one NPC: Raene's chain in Ashenvale is handed to Raene Wolfrunner at 36.6,49.6
	-- while its neighbours end at 20.3,42.3, and the route confidently pointed the arrow eighteen
	-- map units from the person holding the quest. Stops at the same spot still merge below, so a
	-- hub whose quests really do share an ender still reads as one step.
	local backs = {}
	for _, q in ipairs(here) do backs[#backs + 1] = q end
	table.sort(backs, function(a, b)
		if (a.ex or 0) ~= (b.ex or 0) then return (a.ex or 0) < (b.ex or 0) end
		return (a.ey or 0) < (b.ey or 0)
	end)
	for _, q in ipairs(backs) do
		order[#order + 1] = { kind = "turnin", x = q.ex, y = q.ey, npc = q.ender, quests = { q } }
	end
	for _, q in ipairs(here) do done[q.id] = true turnedIn = turnedIn + 1 end
	-- A level checkpoint whenever the estimate moves on. The player reads it as "you should be
	-- about here by now"; the guide lint reads it as the level to judge the next accept against,
	-- and without it every quest above the zone's opening level looks like it was scheduled too
	-- early. One line per level, never a run of them, even if a big hub crosses two at once.
	local now = estimatedLevel(turnedIn)
	if now > announcedLevel then
		announcedLevel = now
		order[#order + 1] = { kind = "xp", level = now }
	end
	cx, cy = pick.ex, pick.ey
end

-- Emit ---------------------------------------------------------------------------------------------

local out = {}
local function w(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end

local placed, chained = 0, 0
for _, q in pairs(quests) do
	placed = placed + 1
	if q.prev then chained = chained + 1 end
end

-- The exact arguments that produced this file, so tools/refresh_harvest.sh can rebuild it after the
-- next merge without anyone remembering what they were. A guide with no such line is treated as
-- hand-authored and left alone, which is what keeps the regenerator from eating someone's work.
local function shellQuote(v)
	return '"' .. tostring(v):gsub('"', '\\"') .. '"'
end
local regen = { tostring(mapID) }
local function regenArg(flag, value)
	if value ~= nil and value ~= "" then
		regen[#regen + 1] = "--" .. flag
		regen[#regen + 1] = shellQuote(value)
	end
end
regenArg("name", NAME)
if FACTION ~= "Both" then regenArg("faction", FACTION) end
regenArg("race", RACE)
regenArg("levels", LEVELS)
regenArg("next", NEXT)
regenArg("next-horde", NEXT_HORDE)
regenArg("next-alliance", NEXT_ALLIANCE)
if ZONE ~= tostring(mapID) then regenArg("zone", ZONE) end
if MAX_LEVEL < 99 then regenArg("max-level", MAX_LEVEL) end
if MIN_LEVEL > 0 then regenArg("min-level", MIN_LEVEL) end

w("-- Lodestar Guides: %s", NAME)
w("--")
w("-- GENERATED by tools/router/generate_route.lua from the merged database (Vanilla + ATT + the")
w("-- beta harvest). Regenerate rather than hand-editing, or the next harvest will overwrite you.")
w("-- --regen-args: %s", table.concat(regen, " "))
w("--")
w("-- %d quests on uiMapID %d had a known giver position; %d carried a prerequisite chain, which is", placed, mapID, chained)
w("-- what fixes the order. Quests the data cannot place yet are not in here at all -- smart mode")
w("-- covers those, and they appear as soon as someone walks past their giver.")
w("local Guide = _G.Lodestar:GetModule(\"Guide\")")
w("")
w("Guide:RegisterGuide([[")
w("#guide %s", NAME)
w("#faction %s", FACTION)
if RACE then w("#race %s", RACE) end
if LEVELS then w("#levels %s", LEVELS) end
if NEXT then w("#next %s", NEXT) end
if NEXT_HORDE then w("#next Horde: %s", NEXT_HORDE) end
if NEXT_ALLIANCE then w("#next Alliance: %s", NEXT_ALLIANCE) end
w("#author Lodestar (generated)")
w("#note Generated from harvested and ATT data. Order follows the quest chains; positions are where players actually found things.")
w("")

local function objectiveLine(q)
	if not q.o then return nil end
	local parts = {}
	for _, o in ipairs(q.o) do
		if o.text then
			parts[#parts + 1] = (o.n and o.n > 1) and (o.text .. " x" .. o.n) or o.text
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ", ")
end

--- Flatten the plan into stops, then merge consecutive stops standing in the same place. Handing a
--- quest back and taking the next one from the same NPC is one stop for the player, and splitting it
--- across two steps makes a short route look like a long one.
---
--- With one exception: a quest must never be accepted and handed back in the same step. When the
--- giver and the ender are the same NPC and we know nothing about the objectives, the two actions
--- land on the same spot and merge, and the guide then reads "accept this, now turn it in" with no
--- hint of what happens in between. The engine holds correctly -- it will not advance past a turn-in
--- until the quest is complete -- but the player is left staring at a step that looks broken. So
--- that merge is refused, and the filler "do" step that would otherwise be dropped is kept.
local stops = {}

local function stopHas(stop, kind, questID)
	for _, a in ipairs(stop.actions) do
		if a.kind == kind and a.q and a.q.id == questID then return true end
	end
	return false
end

local function addStop(x, y, npc, action)
	local last = stops[#stops]
	local sameSpot = last and last.x and x and math.abs(last.x - x) < 0.3 and math.abs(last.y - y) < 0.3
	if sameSpot and action.kind == "turnin" and action.q and stopHas(last, "accept", action.q.id) then
		sameSpot = false
	end
	-- A class-restricted quest never shares a step. `.class` filters the whole step, so folding a
	-- mage quest in with the three ordinary ones from the same NPC would hide all four from
	-- everybody else.
	if sameSpot and ((action.q and action.q.classes) or (last.classes and last.classes ~= (action.q and action.q.classes))) then
		sameSpot = false
	end
	if sameSpot then
		last.npc = last.npc or npc
		last.actions[#last.actions + 1] = action
		return
	end
	stops[#stops + 1] = { x = x, y = y, npc = npc, classes = action.q and action.q.classes or nil, actions = { action } }
end

for _, stepRec in ipairs(order) do
	if stepRec.kind == "xp" then
		stops[#stops + 1] = { xp = stepRec.level, grind = stepRec.grind, actions = {} }
	elseif stepRec.kind == "hub" then
		for _, q in ipairs(stepRec.quests) do
			addStop(stepRec.x, stepRec.y, stepRec.npc, { kind = "accept", q = q })
		end
	elseif stepRec.kind == "do" then
		local q = stepRec.quest
		local line = objectiveLine(q)
		local sx, sy = q.ox, q.oy
		-- A "do" step with neither a position nor an objective to name says nothing the turn-in does
		-- not already say, and a route full of "Finish <quest>" reads as padding. Drop it -- unless
		-- dropping it would put the accept and the turn-in back to back at the same NPC, where the
		-- filler is the only thing telling the player that something happens in between.
		local sameNPC = q.giver and q.ender and q.giver == q.ender
		if line or sx or sameNPC then
			addStop(sx, sy, nil, { kind = "complete", q = q, text = line })
		end
	elseif stepRec.kind == "turnin" then
		for _, q in ipairs(stepRec.quests) do
			if q.enderOffMap then
				-- A quest handed in somewhere else is a breadcrumb out of the zone, and scheduling it
				-- in the middle of the route means a cross-continent detour between two Lakeshire
				-- quests. Keep it -- the XP is real and the player may well want the chain -- but as
				-- an optional step, which completionist mode shows and speed-run skips. No position
				-- either: the giver's spot is not where the ender stands.
				addStop(nil, nil, q.ender, { kind = "turnin", q = q, offMap = true })
			else
				addStop(stepRec.x, stepRec.y, stepRec.npc, { kind = "turnin", q = q })
			end
		end
	end
end

for i, stop in ipairs(stops) do
	local who = npcName(stop.npc)
	if i > 1 then w("") end
	w("step")
	if stop.xp then
		if stop.grind then
			w("  .xp %d >>You should be %d by now. If you are not, the rest of this zone will not be offered to you yet -- finish the optional quests above, or kill your way up, before carrying on.",
				stop.xp, stop.xp)
		else
			w("  .xp %d", stop.xp)
		end
	end
	-- A checkpoint stop carries no actions at all, so "every action is off-map" is vacuously true
	-- for it. Require at least one.
	local offMapOnly = #stop.actions > 0
	for _, a in ipairs(stop.actions) do
		if not a.offMap then offMapOnly = false break end
	end
	if offMapOnly then
		local target = npcName(stop.actions[1].q.ender)
		w("  .optional >>Handed in outside this zone%s", target and (", to " .. target) or "")
	end
	if stop.classes then w("  .class %s", stop.classes) end
	if stop.x then w("  .goto %s,%.1f,%.1f", ZONE, stop.x, stop.y) end
	for _, a in ipairs(stop.actions) do
		local q = a.q
		if a.kind == "accept" then
			w("  .accept %d >>Accept %s%s%s", q.id, q.t or ("quest " .. q.id),
				q.lvl and (" (lvl " .. q.lvl .. ")") or "",
				who and (" from " .. who) or "")
		elseif a.kind == "turnin" then
			local target = npcName(a.q.ender) or who
			local note = ""
			if a.offMap then
				note = " (not in this zone)"
			elseif a.q.enderUnknown then
				-- The arrow points at the giver, which is usually right and sometimes not. The
				-- engine has a better answer once the quest is in the log -- the client's own
				-- next-objective waypoint -- but the route cannot know that in advance, so it says
				-- what it is doing instead of pretending.
				note = " (turn-in spot not recorded yet)"
			end
			w("  .turnin %d >>Turn in %s%s%s", q.id, q.t or ("quest " .. q.id),
				target and (" to " .. target) or "", note)
		else
			w("  .complete %d >>%s", q.id, a.text or ("Finish " .. (q.t or ("quest " .. q.id))))
		end
	end
end

w("")
w("]], \"generated\")")
w("")

io.write(table.concat(out, "\n"))
io.stderr:write(string.format("generate_route: map %d, %d quests placed, %d chained, %d steps\n",
	mapID, placed, chained, #stops))

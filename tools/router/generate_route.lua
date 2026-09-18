-- Generate a Lodestar guide for one map from the merged database.
--
--   lua5.1 tools/router/generate_route.lua <uiMapID> [options] > Lodestar_Guides_X/Zone.lua
--
--   --name "Skyborne 1-12: Zephras Isle"   guide name (#guide)
--   --faction Both|Horde|Alliance          default Both
--   --race Skyborne                        optional #race
--   --levels 1-12                          optional #levels
--   --next "Next guide name"               optional #next
--   --zone "Zephras Isle"                  name used in .goto (default: the map id)
--   --max-level 12                         drop quests above this level
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
local ZONE = opt("zone", tostring(mapID))
local MAX_LEVEL = tonumber(opt("max-level", "99"))

-- Load the same data the addon loads ---------------------------------------------------------------

local Guide = {}
_G.Lodestar = { GetModule = function() return Guide end }
dofile("Lodestar_Guide/Data/Vanilla.lua")
dofile("Lodestar_Guide/Data/ATT.lua")
dofile("Lodestar_Guide/Data/Forever.lua")
local V, A, F = Guide.VanillaData, Guide.ATTData, Guide.ForeverData

-- Facts about a quest, from whichever source knows -------------------------------------------------

local function firstNPC(t) return t and t.npcs and t.npcs[1] or nil end

--- Position of an NPC on this map: x, y (percent) or nil.
local function npcPos(id)
	if not id then return nil end
	for _, store in ipairs({ F.npcs, A.npcs, V.npcs }) do
		local e = store and store[id]
		if e then
			if e.c then
				for _, c in ipairs(e.c) do
					if c.m == mapID then return c[2], c[3] end
				end
			end
			if e.map == mapID and e.x then return e.x, e.y end
		end
	end
	return nil
end

local function npcName(id)
	for _, store in ipairs({ F.npcs, A.npcs, V.npcs }) do
		local e = store and store[id]
		if e and e.n then return e.n end
	end
	return nil
end

local quests = {}

local ids = {}
for qid in pairs(F.quests or {}) do ids[qid] = true end
for qid in pairs(A.quests or {}) do ids[qid] = true end

for qid in pairs(ids) do
	local fq, aq, vq = (F.quests or {})[qid], (A.quests or {})[qid], (V.quests or {})[qid]
	local title = (fq and fq.t) or (vq and vq.t)
	local lvl = (fq and fq.lvl) or (aq and aq.lvl) or (vq and vq.lvl)
	local giver = firstNPC(fq and fq.start) or firstNPC(aq and aq.start) or firstNPC(vq and vq.start)
	local ender = firstNPC(fq and fq["end"]) or firstNPC(aq and aq["end"]) or firstNPC(vq and vq["end"]) or giver
	local gx, gy = npcPos(giver)
	if not gx then
		-- fall back to a recorded accept position even when the giver NPC is unknown
		local at = (fq and fq.acceptAt) or (aq and aq.acceptAt)
		if at and at.m == mapID then gx, gy = at[2], at[3] end
	end
	local ex, ey = npcPos(ender)
	if not ex then
		-- A recorded turn-in position, even when the ender NPC itself was never identified. This is
		-- what the client's own arrow for a completed quest gives, so it exists for far more quests
		-- than a first-hand sighting of the ender does.
		local at = (fq and fq.turninAt) or (aq and aq.turninAt)
		if at and at.m == mapID then ex, ey = at[2], at[3] end
	end
	local prev = (aq and aq.pre) or (vq and vq.pre) or nil
	-- objectives: text and count from the harvest, positions from either side
	local objectives = fq and fq.o or nil
	local spots = (fq and fq.spots) or (aq and aq.spots) or nil
	if gx and (not lvl or lvl <= MAX_LEVEL) then
		quests[qid] = {
			id = qid, t = title, lvl = lvl, giver = giver, ender = ender,
			gx = gx, gy = gy, ex = ex or gx, ey = ey or gy,
			prev = prev, o = objectives, spots = spots,
		}
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
local function blockers(q, pending)
	local out = {}
	for _, p in ipairs(q.prev or {}) do
		if pending[p] then out[#out + 1] = p end
	end
	return out
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
local QUESTS_PER_LEVEL = 2.5
local ACCEPT_GRACE = 3       -- a quest is offered a few levels before its own level

local function estimatedLevel(turnedIn)
	return 1 + math.floor(turnedIn / QUESTS_PER_LEVEL)
end

local turnedIn = 0

while count > 0 and guard < 500 do
	guard = guard + 1
	-- Everything whose prerequisites are already turned in.
	local ready = {}
	for qid, q in pairs(pending) do
		local blocked = false
		for _, p in ipairs(blockers(q, pending)) do
			if not done[p] then blocked = true break end
		end
		if not blocked then ready[#ready + 1] = q end
	end
	-- Of those, the ones a character this far into the zone could actually accept. If that leaves
	-- nothing, the estimate is behind the content rather than the content being wrong, so the lowest
	-- remaining level is taken anyway -- never stall the route over a guess.
	local level = estimatedLevel(turnedIn)
	local inLevel = {}
	for _, q in ipairs(ready) do
		if (q.lvl or 1) <= level + ACCEPT_GRACE then inLevel[#inLevel + 1] = q end
	end
	if #inLevel > 0 then ready = inLevel end
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
	local function score(q)
		return dist(cx, cy, q.gx, q.gy) + math.max(0, (q.lvl or 1) - level) * OVERSHOOT_COST
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
	-- Do them, then hand them back.
	for _, q in ipairs(here) do
		order[#order + 1] = { kind = "do", quest = q }
	end
	order[#order + 1] = { kind = "turnin", x = pick.ex, y = pick.ey, npc = pick.ender, quests = here }
	for _, q in ipairs(here) do done[q.id] = true turnedIn = turnedIn + 1 end
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
if ZONE ~= tostring(mapID) then regenArg("zone", ZONE) end
if MAX_LEVEL < 99 then regenArg("max-level", MAX_LEVEL) end

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
	if sameSpot then
		last.npc = last.npc or npc
		last.actions[#last.actions + 1] = action
		return
	end
	stops[#stops + 1] = { x = x, y = y, npc = npc, actions = { action } }
end

for _, stepRec in ipairs(order) do
	if stepRec.kind == "hub" then
		for _, q in ipairs(stepRec.quests) do
			addStop(stepRec.x, stepRec.y, stepRec.npc, { kind = "accept", q = q })
		end
	elseif stepRec.kind == "do" then
		local q = stepRec.quest
		local line = objectiveLine(q)
		local sx, sy
		local list = q.spots and (q.spots[1] or select(2, next(q.spots)))
		local spot = list and list[1]
		if spot and spot.m == mapID then sx, sy = spot[2], spot[3] end
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
			addStop(stepRec.x, stepRec.y, stepRec.npc, { kind = "turnin", q = q })
		end
	end
end

for i, stop in ipairs(stops) do
	local who = npcName(stop.npc)
	if i > 1 then w("") end
	w("step")
	if stop.x then w("  .goto %s,%.1f,%.1f", ZONE, stop.x, stop.y) end
	for _, a in ipairs(stop.actions) do
		local q = a.q
		if a.kind == "accept" then
			w("  .accept %d >>Accept %s%s%s", q.id, q.t or ("quest " .. q.id),
				q.lvl and (" (lvl " .. q.lvl .. ")") or "",
				who and (" from " .. who) or "")
		elseif a.kind == "turnin" then
			w("  .turnin %d >>Turn in %s%s", q.id, q.t or ("quest " .. q.id), who and (" to " .. who) or "")
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

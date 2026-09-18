-- Lodestar_Guide: read-back over the built-in Vanilla database (Data/Vanilla.lua) for smart mode.
--
-- Where Blizzard's client gives no position for a quest (Forever exposes no quest POIs for the old
-- world on this beta) and the harvest has not seen it yet, the Vanilla data answers:
--   turn-in   the quest's end NPC / object, nearest copy to the player
--   objective the mobs / objects / item drop sources of the first unfinished objective, nearest copy
--   pick-up   quests whose start NPC stands on the current map, that this character can take now:
--             race/class mask, level window, prerequisites completed, not done, not in the log
-- Zone ids in the data are 1.12 area ids; they are resolved to uiMapIDs by name through C_Map once.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local PICKUP_LEVEL_ABOVE = 2     -- offer quests up to this many levels above the player
local PICKUP_LEVEL_BELOW = 5     -- and drop quests this many levels below (gray)
local MAX_PICKUPS = 12

local zoneMap = {}                -- [pfZoneID] = uiMapID | false
local worldCache = {}             -- "zone:x:y" -> { continent, wx, wy } | false

local function data() return Guide.VanillaData end

local function zoneToMap(zone)
	local cached = zoneMap[zone]
	if cached then return cached end
	local d = data()
	local name = d and d.zones[zone]
	local mapID = name and Guide:ResolveMap(name)
	if mapID then zoneMap[zone] = mapID end -- misses are not cached: the map tree may not be ready yet
	return mapID
end

--- Distance from the player to a data coordinate, with its map (nil when unknown/other continent).
local function distanceTo(c)
	local key = c[1] .. ":" .. c[2] .. ":" .. c[3]
	local w = worldCache[key]
	if not w then
		local mapID = zoneToMap(c[1])
		if not mapID then return nil end
		local continent, wx, wy = Guide:WorldPos(mapID, c[2] / 100, c[3] / 100)
		if not continent then return nil end
		w = { continent, wx, wy, mapID }
		worldCache[key] = w
	end
	local dist = Guide:DistanceToWorld(w[1], w[2], w[3])
	return dist, w[4]
end

--- Nearest coordinate among a list of entities: mapID, x, y (0..1), name, dist.
local function nearest(store, ids)
	local best, bestDist, bestName, bestMap
	for _, id in ipairs(ids or {}) do
		local e = store[id]
		if e and e.c then
			for _, c in ipairs(e.c) do
				local dist, mapID = distanceTo(c)
				if dist and (not bestDist or dist < bestDist) then best, bestDist, bestName, bestMap = c, dist, e.n, mapID end
			end
		end
	end
	if not best then return nil end
	return bestMap, best[2] / 100, best[3] / 100, bestName, bestDist
end

local function itemSourceIDs(itemIDs)
	local d = data()
	local npcs, objs = {}, {}
	for _, itemID in ipairs(itemIDs or {}) do
		local it = d.items[itemID]
		if it then
			for _, src in ipairs(it.npcs or {}) do tinsert(npcs, src[1]) end
			for _, src in ipairs(it.objs or {}) do tinsert(objs, src[1]) end
		end
	end
	return npcs, objs
end

--- Best data position for a quest in the log: mapID, x, y, how.
function Guide:DataQuestPosition(questID, complete)
	local d = data()
	local q = d and d.quests[questID]
	if not q then return nil end
	if complete then
		local e = q["end"]
		if not e then return nil end
		local mapID, x, y, name = nearest(d.npcs, e.npcs)
		if not mapID then mapID, x, y, name = nearest(d.objs, e.objs) end
		if mapID then return mapID, x, y, name and ("Turn in to " .. name) or "Turn in" end
		return nil
	end
	local o = q.obj
	if not o then return nil end
	local mapID, x, y, name, dist = nearest(d.npcs, o.npcs)
	local mapID2, x2, y2, name2, dist2 = nearest(d.objs, o.objs)
	if mapID2 and (not mapID or dist2 < dist) then mapID, x, y, name, dist = mapID2, x2, y2, name2, dist2 end
	if not mapID then
		local npcs, objs = itemSourceIDs(o.items)
		mapID, x, y, name, dist = nearest(d.npcs, npcs)
		mapID2, x2, y2, name2, dist2 = nearest(d.objs, objs)
		if mapID2 and (not mapID or dist2 < dist) then mapID, x, y, name = mapID2, x2, y2, name2 end
	end
	if not mapID and o.areas then
		for _, areaID in ipairs(o.areas) do
			local a = d.areas[areaID]
			mapID, x, y = nearest({ [areaID] = a }, { areaID })
			if mapID then name = "Explore" break end
		end
	end
	if mapID then return mapID, x, y, name end
	return nil
end

--- Quest level and title from the data (nil when unknown).
function Guide:DataQuestInfo(questID)
	local d = data()
	local q = d and d.quests[questID]
	if not q then return nil end
	return q.t, q.lvl, q.min
end

local function playerMasks()
	local _, raceFile = UnitRace("player")
	local _, classFile = UnitClass("player")
	return RACE_BIT[raceFile] or 0, CLASS_BIT[classFile] or 0
end

local function canTake(q, level, raceBit, classBit)
	if q.race and q.race ~= 0 and bit.band(q.race, raceBit) == 0 then return false end
	if q.class and q.class ~= 0 and bit.band(q.class, classBit) == 0 then return false end
	if q.skill or q.event then return false end
	if q.min and q.min > level then return false end
	if q.lvl and (q.lvl > level + PICKUP_LEVEL_ABOVE or q.lvl < level - PICKUP_LEVEL_BELOW) then return false end
	for _, pre in ipairs(q.pre or {}) do
		if not C_QuestLog.IsQuestFlaggedCompleted(pre) then return false end
	end
	return true
end

-- Quests by start NPC/object, built once per session (lazily).
local startIndex
local function buildStartIndex()
	startIndex = { npcs = {}, objs = {} }
	local d = data()
	for qid, q in pairs(d.quests) do
		local s = q.start
		if s then
			for _, id in ipairs(s.npcs or {}) do
				startIndex.npcs[id] = startIndex.npcs[id] or {}
				tinsert(startIndex.npcs[id], qid)
			end
			for _, id in ipairs(s.objs or {}) do
				startIndex.objs[id] = startIndex.objs[id] or {}
				tinsert(startIndex.objs[id], qid)
			end
		end
	end
end

--- "Pick up" items for quest givers on the current map that this character can take now.
function Guide:DataAvailableItems(items, mapID)
	local d = data()
	if not d then return end
	if not startIndex then buildStartIndex() end
	local level = UnitLevel("player")
	local raceBit, classBit = playerMasks()
	local seen = {}
	for _, it in ipairs(items) do if it.questID then seen[it.questID] = true end end
	local found = {}
	local function scan(store, index, isObject)
		for id, qids in pairs(index) do
			local e = store[id]
			if e and e.c then
				local mapHere = false
				for _, c in ipairs(e.c) do if zoneToMap(c[1]) == mapID then mapHere = true break end end
				if mapHere then
					for _, qid in ipairs(qids) do
						local q = d.quests[qid]
						if q and not seen[qid] and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid) and canTake(q, level, raceBit, classBit) then
							seen[qid] = true
							local pmap, x, y, name, dist = nearest(store, { id })
							if pmap then
								tinsert(found, { kind = "available", questID = qid, mapID = pmap, x = x, y = y, dist = dist, source = "data",
									title = q.t or ("Quest " .. qid), level = q.lvl,
									subtitle = "Pick up from " .. (name or (isObject and "object" or "NPC")) .. (q.lvl and (" · lvl " .. q.lvl) or "") })
							end
						end
					end
				end
			end
		end
	end
	scan(d.npcs, startIndex.npcs, false)
	scan(d.objs, startIndex.objs, true)
	table.sort(found, function(a, b) return (a.dist or math.huge) < (b.dist or math.huge) end)
	for i = 1, math.min(#found, MAX_PICKUPS) do tinsert(items, found[i]) end
end

--- Chat lookup: /lode quest <id or name>
function Guide:DataLookup(arg)
	local d = data()
	if not d then Lodestar:Say("No Vanilla data loaded.") return end
	local id = tonumber(arg)
	local hits = {}
	if id and d.quests[id] then
		hits[1] = id
	else
		local needle = (arg or ""):lower()
		if needle == "" then Lodestar:Say("Usage: /lode quest <id or part of a name>") return end
		for qid, q in pairs(d.quests) do
			if q.t and q.t:lower():find(needle, 1, true) then tinsert(hits, qid) end
		end
		table.sort(hits)
	end
	if #hits == 0 then Lodestar:Say("No quest matches '%s'.", tostring(arg)) return end
	local function names(store, ids)
		local parts = {}
		for _, nid in ipairs(ids or {}) do
			local e = store[nid]
			if e then
				local c = e.c and e.c[1]
				tinsert(parts, ("%s%s"):format(e.n or ("#" .. nid), c and (" (" .. (d.zones[c[1]] or c[1]) .. " " .. c[2] .. "," .. c[3] .. ")") or ""))
			end
		end
		return #parts > 0 and table.concat(parts, ", ") or nil
	end
	for i = 1, math.min(#hits, 6) do
		local qid = hits[i]
		local q = d.quests[qid]
		local flags = C_QuestLog.IsQuestFlaggedCompleted(qid) and " |cff7fff7fdone|r" or (C_QuestLog.IsOnQuest(qid) and " |cffffd700in log|r" or "")
		Lodestar:Say("|cffffffff%d %s|r (lvl %s, min %s)%s", qid, q.t or "?", tostring(q.lvl), tostring(q.min), flags)
		local s, e = q.start, q["end"]
		if s then Lodestar:Say("   from: %s", names(d.npcs, s.npcs) or names(d.objs, s.objs) or (s.items and "item") or "?") end
		if e then Lodestar:Say("   to:   %s", names(d.npcs, e.npcs) or names(d.objs, e.objs) or "?") end
		if q.obj then
			local o = q.obj
			local txt = names(d.npcs, o.npcs) or names(d.objs, o.objs)
			if not txt and o.items then
				local npcs = itemSourceIDs(o.items)
				txt = names(d.npcs, npcs)
			end
			if txt then Lodestar:Say("   do:   %s", txt) end
		end
		if q.pre then Lodestar:Say("   needs: %s", table.concat(q.pre, ", ")) end
	end
	if #hits > 6 then Lodestar:Say("…and %d more.", #hits - 6) end
end

function Guide:EnableData()
	if not self.dataSlash then
		self.dataSlash = true
		Lodestar:RegisterSlashVerb("quest", function(rest) self:DataLookup(strtrim(rest or "")) end, "look up a quest in the built-in database: /lode quest <id|name>")
	end
end

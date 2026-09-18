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
--- Vanilla coordinates are { zoneID, x, y }; Forever overlay coordinates are { 0, x, y, m = uiMapID }.
local function distanceTo(c)
	local key = (c.m or c[1]) .. ":" .. c[2] .. ":" .. c[3]
	local w = worldCache[key]
	if not w then
		local mapID = c.m or zoneToMap(c[1])
		if not mapID then return nil end
		local continent, wx, wy = Guide:WorldPos(mapID, c[2] / 100, c[3] / 100)
		if not continent then return nil end
		w = { continent, wx, wy, mapID }
		worldCache[key] = w
	end
	local dist = Guide:DistanceToWorld(w[1], w[2], w[3])
	return dist, w[4]
end

--- Nearest coordinate among a list of entities: mapID, x, y (0..1), name, dist, id.
local function nearest(store, ids)
	local best, bestDist, bestName, bestMap, bestID
	for _, id in ipairs(ids or {}) do
		local e = store[id]
		if e and e.c then
			for _, c in ipairs(e.c) do
				local dist, mapID = distanceTo(c)
				if dist and (not bestDist or dist < bestDist) then best, bestDist, bestName, bestMap, bestID = c, dist, e.n, mapID, id end
			end
		end
	end
	if not best then return nil end
	return bestMap, best[2] / 100, best[3] / 100, bestName, bestDist, bestID
end

--- Nearest of the given NPC ids (Data/Trainers.lua lists, for one): mapID, x, y (0..1), name, dist, npcID.
function Guide:DataNearestNPC(ids)
	local d = data()
	if not d then return nil end
	return nearest(d.npcs, ids)
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
		local mapID, x, y, name
		if e then
			mapID, x, y, name = nearest(d.npcs, e.npcs)
			if not mapID then mapID, x, y, name = nearest(d.objs, e.objs) end
		end
		if not mapID and q.turninAt and q.turninAt.m then mapID, x, y = q.turninAt.m, q.turninAt[2] / 100, q.turninAt[3] / 100 end
		if mapID then return mapID, x, y, name and ("Turn in to " .. name) or "Turn in" end
		return nil
	end
	local o = q.obj
	if not o then
		-- Forever overlay: where the objective was worked on by other players (per objective index)
		if type(q.spots) == "table" then
			local objectives = C_QuestLog.GetQuestObjectives(questID)
			local idx = 1
			for i, ob in ipairs(objectives or {}) do if not ob.finished then idx = i break end end
			local list = q.spots[idx] or q.spots[1]
			local spot = list and list[1]
			if spot and spot.m then return spot.m, spot[2] / 100, spot[3] / 100, "Objective area" end
		end
		return nil
	end
	local mapID, x, y, name, dist = nearest(d.npcs, o.npcs)
	local mapID2, x2, y2, name2, dist2 = nearest(d.objs, o.objs)
	if mapID2 and (not mapID or dist2 < dist) then mapID, x, y, name = mapID2, x2, y2, name2 end
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

-- Read-only lookups for the guide window (StepFrame.lua) ------------------------------------------
-- These two add nothing to the data model: they just answer "who and where" for a single quest so the
-- window can write a plain-English headline and point the arrow at one action instead of the step.

--- Names the data knows for a quest: who gives it, who takes it back, what its first objective is
--- about, and whether that objective target is a creature. All four may be nil.
function Guide:DataQuestNames(questID)
	local d = data()
	local q = d and d.quests[questID]
	if not q then return nil end
	local function firstName(store, ids)
		for _, id in ipairs(ids or {}) do
			local e = store[id]
			if e and e.n then return e.n end
		end
		return nil
	end
	local giver = q.start and (firstName(d.npcs, q.start.npcs) or firstName(d.objs, q.start.objs)) or nil
	local ender = q["end"] and (firstName(d.npcs, q["end"].npcs) or firstName(d.objs, q["end"].objs)) or nil
	local objName, objIsCreature
	local o = q.obj
	if o then
		objName = firstName(d.npcs, o.npcs)
		objIsCreature = objName ~= nil
		if not objName then objName = firstName(d.objs, o.objs) end
		if not objName and o.items then
			local npcs = itemSourceIDs(o.items)
			objName = firstName(d.npcs, npcs)
			objIsCreature = objName ~= nil
		end
	end
	return giver, ender, objName, objIsCreature
end

--- Where a quest is picked up: mapID, x, y (0..1), name — the nearest known start NPC or object.
function Guide:DataQuestStartPosition(questID)
	local d = data()
	local q = d and d.quests[questID]
	local s = q and q.start
	if not s then return nil end
	local mapID, x, y, name = nearest(d.npcs, s.npcs)
	if not mapID then mapID, x, y, name = nearest(d.objs, s.objs) end
	if not mapID then return nil end
	return mapID, x, y, name
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

-- Quests by start NPC/object/item, built once per session (lazily).
local startIndex
local function buildStartIndex()
	startIndex = { npcs = {}, objs = {}, items = {} }
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
			for _, id in ipairs(s.items or {}) do
				startIndex.items[id] = startIndex.items[id] or {}
				tinsert(startIndex.items[id], qid)
			end
		end
	end
end

--- Quests this character can pick up right now from one quest giver (`kind` = npcs | objs | items):
--- { questID, title, level, classQuest }, lowest level first. Same filters as the pick-up list:
--- not in the log, not done, race/class masks, level window, prerequisites completed.
function Guide:DataAvailableFrom(kind, id)
	local found = {}
	local d = data()
	if not d then return found end
	if not startIndex then buildStartIndex() end
	local qids = startIndex[kind] and startIndex[kind][id]
	if not qids then return found end
	local level = UnitLevel("player")
	local raceBit, classBit = playerMasks()
	for _, qid in ipairs(qids) do
		local q = d.quests[qid]
		if q and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid) and canTake(q, level, raceBit, classBit) then
			tinsert(found, { questID = qid, title = q.t or ("Quest " .. qid), level = q.lvl, classQuest = q.class and q.class ~= 0 or false })
		end
	end
	table.sort(found, function(a, b)
		local la, lb = a.level or 0, b.level or 0
		if la ~= lb then return la < lb end
		return a.questID < b.questID
	end)
	return found
end

function Guide:DataAvailableFromNPC(npcID) return self:DataAvailableFrom("npcs", npcID) end
function Guide:DataAvailableFromObject(objID) return self:DataAvailableFrom("objs", objID) end
function Guide:DataAvailableFromItem(itemID) return self:DataAvailableFrom("items", itemID) end

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
				for _, c in ipairs(e.c) do if (c.m or zoneToMap(c[1])) == mapID then mapHere = true break end end
				if mapHere then
					for _, qid in ipairs(qids) do
						local q = d.quests[qid]
						if q and not seen[qid] and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid) and canTake(q, level, raceBit, classBit) then
							seen[qid] = true
							local pmap, x, y, name, dist = nearest(store, { id })
							if pmap then
								-- canTake already applied the class mask, so a class-flagged quest here is for this class.
								local classQuest = q.class and q.class ~= 0 or false
								tinsert(found, { kind = "available", questID = qid, mapID = pmap, x = x, y = y, dist = dist, source = "data",
									title = q.t or ("Quest " .. qid), level = q.lvl, classQuest = classQuest,
									subtitle = (classQuest and "Class quest · " or "") .. "Pick up from " .. (name or (isObject and "object" or "NPC")) .. (q.lvl and (" · lvl " .. q.lvl) or "") })
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
				-- Overlay coords carry the uiMapID in `m` and 0 in [1], so the Vanilla zone table
				-- would print a bare "0" for every Forever entry.
				local place = c and (c.m and Guide:MapName(c.m) or d.zones[c[1]] or c[1])
				tinsert(parts, ("%s%s"):format(e.n or ("#" .. nid), c and (" (" .. place .. " " .. c[2] .. "," .. c[3] .. ")") or ""))
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

--- Merge the Forever overlay (Data/Forever.lua, harvested on the beta) into the Vanilla tables once.
--- Overlay quests add/replace fields (title, level, objectives, start/end, spots, xp); overlay NPCs and
--- objects add entries or append positions; NPCs with `trains` join Data/Trainers.lua's lists.
--- Merge the All The Things overlay into the Vanilla tables. Runs BEFORE MergeForeverData, so
--- anything a player harvested first-hand overwrites ATT rather than the other way round: ATT is
--- dense on the old world and thin on Forever's new zones, and the harvest is the reverse.
function Guide:MergeATTData()
	local A, V = self.ATTData, self.VanillaData
	if not (A and V) or V.attMerged then return end
	V.attMerged = true
	for id, aq in pairs(A.quests or {}) do
		local q = V.quests[id]
		if not q then
			q = {}
			V.quests[id] = q
		end
		-- Only fill gaps: a Vanilla entry that already knows where a quest starts is not replaced.
		for k, v in pairs(aq) do
			if q[k] == nil then q[k] = v end
		end
		q.att = true
	end
	for _, storeName in ipairs({ "npcs", "objs" }) do
		for id, ae in pairs(A[storeName] or {}) do
			local e = V[storeName][id]
			if not e then
				e = {}
				V[storeName][id] = e
			end
			if ae.c then
				e.c = e.c or {}
				for _, c in ipairs(ae.c) do tinsert(e.c, c) end
			end
		end
	end
end

function Guide:MergeForeverData()
	local F, V = self.ForeverData, self.VanillaData
	if not (F and V) or V.foreverMerged then return end
	V.foreverMerged = true
	for id, fq in pairs(F.quests or {}) do
		local q = V.quests[id]
		if not q then
			q = {}
			V.quests[id] = q
		end
		for k, v in pairs(fq) do q[k] = v end
		q.forever = true
	end
	for _, storeName in ipairs({ "npcs", "objs" }) do
		for id, fe in pairs(F[storeName] or {}) do
			local e = V[storeName][id]
			if not e then
				e = {}
				V[storeName][id] = e
			end
			if fe.n and not e.n then e.n = fe.n end
			if fe.lvl and not e.lvl then e.lvl = fe.lvl end
			if fe.kind then e.kind = fe.kind end
			if fe.c then
				e.c = e.c or {}
				for _, c in ipairs(fe.c) do tinsert(e.c, c) end
			end
			if fe.trains and storeName == "npcs" and self.TrainerData then
				self.TrainerData[fe.trains] = self.TrainerData[fe.trains] or {}
				tinsert(self.TrainerData[fe.trains], id)
			end
		end
	end
end

function Guide:EnableData()
	self:MergeATTData()
	self:MergeForeverData()
	if not self.dataSlash then
		self.dataSlash = true
		Lodestar:RegisterSlashVerb("quest", function(rest) self:DataLookup(strtrim(rest or "")) end, "look up a quest in the built-in database: /lode quest <id|name>")
	end
end

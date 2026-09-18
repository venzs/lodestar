-- Lodestar_Guide: "smart mode" — a data-free guide built from the client itself.
--
-- With no authored route (or once the route is finished), the guide window lists what is worth
-- doing next, sorted by distance, and the arrow points at the top item:
--   turn-ins   quests in the log that are complete
--   objectives quests in progress
--   available  quests you can pick up nearby (Blizzard quest lines when the client has them,
--              otherwise quest givers Lodestar has seen on this character or account)
--   hubs       quest hubs Blizzard marks on the map
--   train      your class trainer, when you have new spells to learn (Engine.lua: TrainerSuggestion)
-- Completed quests are known from the client (IsQuestFlaggedCompleted), so nothing is re-suggested.
--
-- Where a quest is comes from the first source that answers:
--   1. C_QuestLog.GetNextWaypoint          Blizzard's own routing (objective, or turn-in once complete)
--   2. C_QuestLog.GetQuestsOnMap           quest POIs on the current map
--   3. Lodestar's harvest (Harvest.lua)    NPCs this account has talked to, objective spots recorded
--   4. nothing                             the quest is still listed (objective text, no arrow), ranked
--                                          by C_QuestLog.GetDistanceSqToQuest when the client knows it
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local WEIGHT = { turnin = 0.6, train = 0.8, objective = 1.0, available = 1.3, hub = 1.6 }
local questLineRequests = {} -- [mapID] = GetTime() of last request
local pinned                 -- item the player clicked in the list; arrow follows it until done
local cache, cacheAt = nil, 0
local lastSources = {}       -- [questID] = "waypoint" | "poi" | "harvest" | "none"  (for /lode guide diag)

local function firstUnfinishedObjective(questID)
	local objectives = C_QuestLog.GetQuestObjectives(questID)
	if type(objectives) ~= "table" then return nil end
	for _, o in ipairs(objectives) do
		if not o.finished and o.text and o.text ~= "" then return o.text end
	end
	local o = objectives[1]
	return o and o.text or nil
end

--- Quest POIs on a map, indexed by questID ({ x, y }). Cached per collect.
local function poisOnMap(mapID)
	if not (mapID and C_QuestLog.GetQuestsOnMap) then return {} end
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	local byQuest = {}
	if ok and type(list) == "table" then
		for _, poi in ipairs(list) do
			if poi.questID and poi.x and poi.y and not byQuest[poi.questID] then
				byQuest[poi.questID] = { x = poi.x, y = poi.y }
			end
		end
	end
	return byQuest
end

--- Position for a quest in the log: mapID, x, y, source.
local function questPosition(questID, complete, mapID, pois)
	local ok, wmap, wx, wy = pcall(C_QuestLog.GetNextWaypoint, questID)
	if ok and wmap and wx and wy then return wmap, wx, wy, "waypoint" end
	local poi = pois[questID]
	if poi then return mapID, poi.x, poi.y, "poi" end
	if Guide.HarvestQuestPosition then
		local hmap, hx, hy, how = Guide:HarvestQuestPosition(questID, complete)
		if hmap then return hmap, hx, hy, "harvest:" .. (how or "") end
	end
	if Guide.DataQuestPosition then
		local dmap, dx, dy, how = Guide:DataQuestPosition(questID, complete)
		if dmap then return dmap, dx, dy, "data", how end
	end
	return nil
end

local function questLogItems(items, mapID)
	local pois = poisOnMap(mapID)
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID then
			local qid = info.questID
			local complete = C_QuestLog.IsComplete(qid) and true or false
			local pmap, px, py, source, where = questPosition(qid, complete, mapID, pois)
			lastSources[qid] = source or "none"
			local okText, wpText = pcall(C_QuestLog.GetNextWaypointText, qid)
			local subtitle
			if complete then
				subtitle = (okText and wpText and wpText ~= "" and wpText) or where or "Turn in"
			else
				local objective = firstUnfinishedObjective(qid)
				subtitle = objective or (okText and wpText and wpText ~= "" and wpText) or "Objective"
				if where and objective and not objective:lower():find(where:lower(), 1, true) then subtitle = subtitle .. " · " .. where end
			end
			local item = {
				kind = complete and "turnin" or "objective", questID = qid, mapID = pmap, x = px, y = py,
				title = info.title or ("Quest " .. qid), subtitle = subtitle, source = source,
				level = info.level, isTask = info.isTask,
			}
			if not pmap then
				-- No position, but the client may still know how far away it is.
				if C_QuestLog.GetDistanceSqToQuest then
					local okD, distSq, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, qid)
					if okD and type(distSq) == "number" and distSq >= 0 and onContinent ~= false then item.dist = math.sqrt(distSq) end
				end
				item.noPosition = true
			end
			tinsert(items, item)
		end
	end
end

local function availableItems(items, mapID)
	if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return end
	local now = GetTime()
	if C_QuestLine.RequestQuestLinesForMap and (not questLineRequests[mapID] or now - questLineRequests[mapID] > 60) then
		questLineRequests[mapID] = now
		pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
	end
	local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
	if not ok or type(lines) ~= "table" then return end
	for _, ql in ipairs(lines) do
		if ql.questID and not ql.isHidden and not C_QuestLog.IsOnQuest(ql.questID) and not C_QuestLog.IsQuestFlaggedCompleted(ql.questID) and ql.x and ql.y then
			tinsert(items, { kind = "available", questID = ql.questID, mapID = mapID, x = ql.x, y = ql.y, source = "questline",
				title = ql.questName or ql.questLineName or ("Quest " .. ql.questID), subtitle = "Pick up" .. (ql.questLineName and (" · " .. ql.questLineName) or "") })
		end
	end
end

local function hubItems(items, mapID)
	if not (C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap) then return end
	local ok, hubs = pcall(C_AreaPoiInfo.GetQuestHubsForMap, mapID)
	if not ok or type(hubs) ~= "table" then return end
	for _, poi in ipairs(hubs) do
		local pos = poi.position
		if pos then
			local x, y = pos:GetXY()
			tinsert(items, { kind = "hub", mapID = mapID, x = x, y = y, title = poi.name or "Quest hub", subtitle = "Quest hub" .. (poi.description and poi.description ~= "" and (" · " .. poi.description) or ""), poiID = poi.areaPoiID, source = "hub" })
		end
	end
end

--- Everything worth doing, scored by weighted distance. Cached for 1 s.
function Guide:CollectSmartItems(force)
	local now = GetTime()
	if cache and not force and now - cacheAt < 1 then return cache end
	local items = {}
	local mapID = C_Map.GetBestMapForUnit("player")
	questLogItems(items, mapID)
	if mapID then
		availableItems(items, mapID)
		hubItems(items, mapID)
		if self.HarvestAvailableItems then self:HarvestAvailableItems(items, mapID) end
		if self.DataAvailableItems then self:DataAvailableItems(items, mapID) end
		if self.TrainItems then self:TrainItems(items, mapID) end
	end
	for _, it in ipairs(items) do
		if it.mapID and it.x and it.y then
			local dist = self:VectorTo(it.mapID, it.x, it.y)
			it.dist = dist
		end
		local d = it.dist
		-- Things without a known position sort after everything that has one, but stay in the list.
		it.score = d and (d * (WEIGHT[it.kind] or 1) + (it.noPosition and 1e5 or 0)) or (1e6 + (WEIGHT[it.kind] or 1))
	end
	table.sort(items, function(a, b)
		if a.score ~= b.score then return a.score < b.score end
		return (a.title or "") < (b.title or "")
	end)
	cache, cacheAt = items, now
	return items
end

local function sameItem(a, b)
	return a and b and a.kind == b.kind and a.questID == b.questID and a.mapID == b.mapID and a.x == b.x and a.y == b.y
end

--- The item the arrow should follow in smart mode: the pinned one while it still exists, else the
--- best item that has a position.
function Guide:SmartTarget(force)
	local items = self:CollectSmartItems(force)
	if pinned then
		for _, it in ipairs(items) do
			if sameItem(it, pinned) then return it end
		end
		pinned = nil
	end
	for _, it in ipairs(items) do
		if it.mapID and it.x and it.y then return it end
	end
	return nil
end

function Guide:PinSmartItem(item)
	pinned = item
	self:RetargetArrow()
	self:RefreshStepFrame()
end

function Guide:GetPinnedSmartItem() return pinned end

--- True when the window/arrow should run in smart mode.
function Guide:InSmartMode()
	return self.current == nil
end

function Guide:SmartSources() return lastSources end

function Guide:PrintNextUp()
	local items = self:CollectSmartItems(true)
	if #items == 0 then Lodestar:Say("Nothing in the quest log and no quest givers known on this map.") return end
	Lodestar:Say("Next up (%d):", #items)
	for i = 1, math.min(#items, 8) do
		local it = items[i]
		Lodestar:Say("  %d. |cffffffff%s|r — %s%s%s", i, it.title, it.subtitle or it.kind,
			it.dist and (" · " .. math.floor(it.dist) .. " yd") or "",
			it.noPosition and " · |cff888888location unknown|r" or "")
	end
end

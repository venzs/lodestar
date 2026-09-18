-- Lodestar_Guide: "smart mode" — a data-free guide built from the client itself.
--
-- With no authored route (or once the route is finished), the guide window lists what is worth
-- doing next, sorted by distance, and the arrow points at the top item:
--   turn-ins   quests in the log that are complete            (C_QuestLog.GetNextWaypoint → the NPC)
--   objectives quests in progress                              (GetNextWaypoint → nearest objective)
--   available  storyline quests you can pick up on this map    (C_QuestLine.GetAvailableQuestLines)
--   hubs       quest hubs Blizzard marks on the map            (C_AreaPoiInfo.GetQuestHubsForMap)
-- Completed quests are known from the client (IsQuestFlaggedCompleted), so nothing is re-suggested.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local WEIGHT = { turnin = 0.6, objective = 1.0, available = 1.3, hub = 1.6 }
local questLineRequests = {} -- [mapID] = GetTime() of last request
local pinned                 -- item the player clicked in the list; arrow follows it until done
local cache, cacheAt = nil, 0

local function questLogItems(items)
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID then
			local qid = info.questID
			local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, qid)
			if ok and mapID and x and y then
				local complete = C_QuestLog.IsComplete(qid)
				local okText, wpText = pcall(C_QuestLog.GetNextWaypointText, qid)
				tinsert(items, {
					kind = complete and "turnin" or "objective", questID = qid, mapID = mapID, x = x, y = y,
					title = info.title or ("Quest " .. qid),
					subtitle = (okText and wpText and wpText ~= "" and wpText) or (complete and "Turn in" or "Objective"),
				})
			end
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
			tinsert(items, { kind = "available", questID = ql.questID, mapID = mapID, x = ql.x, y = ql.y,
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
			tinsert(items, { kind = "hub", mapID = mapID, x = x, y = y, title = poi.name or "Quest hub", subtitle = "Quest hub" .. (poi.description and poi.description ~= "" and (" · " .. poi.description) or ""), poiID = poi.areaPoiID })
		end
	end
end

--- Everything worth doing, scored by weighted distance. Cached for 1 s.
function Guide:CollectSmartItems(force)
	local now = GetTime()
	if cache and not force and now - cacheAt < 1 then return cache end
	local items = {}
	questLogItems(items)
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID then
		availableItems(items, mapID)
		hubItems(items, mapID)
	end
	for _, it in ipairs(items) do
		local dist = self:VectorTo(it.mapID, it.x, it.y)
		it.dist = dist
		it.score = dist and dist * (WEIGHT[it.kind] or 1) or math.huge
	end
	table.sort(items, function(a, b) return a.score < b.score end)
	cache, cacheAt = items, now
	return items
end

local function sameItem(a, b)
	return a and b and a.kind == b.kind and a.questID == b.questID and a.mapID == b.mapID and a.x == b.x and a.y == b.y
end

--- The item the arrow should follow in smart mode: the pinned one while it still exists, else the best.
function Guide:SmartTarget(force)
	local items = self:CollectSmartItems(force)
	if pinned then
		for _, it in ipairs(items) do
			if sameItem(it, pinned) then return it end
		end
		pinned = nil
	end
	return items[1]
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

function Guide:PrintNextUp()
	local items = self:CollectSmartItems(true)
	if #items == 0 then Lodestar:Say("Nothing in the quest log and no quest givers known on this map.") return end
	Lodestar:Say("Next up (%d):", #items)
	for i = 1, math.min(#items, 8) do
		local it = items[i]
		Lodestar:Say("  %d. |cffffffff%s|r — %s%s", i, it.title, it.subtitle or it.kind, it.dist and (" · " .. math.floor(it.dist) .. " yd") or "")
	end
end

-- Lodestar_Guide: the harvest — everything the client tells us about the world, kept account-wide.
--
-- Runs all the time (not only while recording). It is the raw material for routes on a game whose
-- quest data no addon has yet:
--   npcs     every creature you talk to, target or mouse over: id, name, level range, what it is
--            (quest giver / vendor / repair / trainer / flight master / innkeeper), where it stands and
--            which quests it offers or accepts
--   quests   every quest you see: title, level, objectives, giver, ender, XP at your level, and where
--            each objective was worked on and finished
--   taxi     flight nodes seen on the flight map, with positions and whether you had them
--   levels   XP needed per level (UnitXPMax), in case Forever's curve differs from Classic
--   scan     `/lode scan quests [from] [to]` walks quest IDs through RequestLoadQuestByID and keeps the
--            title/objectives of every ID that exists — the census of the game's quests
--
-- Smart mode reads it back (Guide:HarvestQuestPosition / Guide:HarvestAvailableItems) so the arrow
-- and the "Pick up" rows work even where Blizzard's routing does not.
--
-- Positions are the player's own position at the moment of the event, so an NPC you talked to is
-- placed within interaction range (~5 yd) and a mob you targeted is placed within sight of you.
-- Stored as map id + percent coordinates (61.2, 52.3), like the guide format.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local MAX_SAMPLES = 6          -- approximate positions kept per creature
local SAMPLE_MIN_APART = 3     -- percent-of-map units; closer samples are merged
local SCAN_BATCH, SCAN_TICK = 8, 0.25   -- 32 quest ids per second

local db                        -- LodestarScanDB
local objectiveState = {}       -- [questID] = { [i] = { finished, num } }
local diffQueued = false
local lastInteraction           -- { id, kind = "npc"|"object", name, t }
local scanTicker
local scanPending = {}          -- [questID] = true while a load is in flight

local function plain(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function playerXY()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return nil end
	return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

--- Map id and percent coordinates of the player, or nil.
function Guide:PlayerMapXY() return playerXY() end

local function ensureDB()
	if type(_G.LodestarScanDB) ~= "table" then _G.LodestarScanDB = {} end
	db = _G.LodestarScanDB
	db.v = 1
	db.build = select(2, GetBuildInfo())
	db.npcs = db.npcs or {}
	db.objects = db.objects or {}
	db.quests = db.quests or {}
	db.taxi = db.taxi or {}
	db.levels = db.levels or {}
	db.scan = db.scan or {}
	return db
end

function Guide:HarvestDB() return db or ensureDB() end

-- Creatures -----------------------------------------------------------------------------------------------

local function guidInfo(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	id = tonumber(id)
	if not id then return nil end
	if kind == "Creature" or kind == "Vehicle" then return "npc", id end
	if kind == "GameObject" then return "object", id end
	return nil
end

local function entryFor(kind, id, name)
	local store = kind == "object" and db.objects or db.npcs
	local e = store[id]
	if not e then
		e = { name = name, seen = 0 }
		store[id] = e
	end
	if name and (not e.name or e.name == "") then e.name = name end
	e.seen = (e.seen or 0) + 1
	return e
end

local function farEnough(e, mapID, x, y)
	for _, s in ipairs(e.samples or {}) do
		if s[1] == mapID and math.abs(s[2] - x) < SAMPLE_MIN_APART and math.abs(s[3] - y) < SAMPLE_MIN_APART then return false end
	end
	return true
end

--- Record a creature seen through a unit token. `exact` = we are interacting with it (within ~5 yd).
local function noteUnit(unit, exact)
	if not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
	local guid = plain(UnitGUID(unit))
	local kind, id = guidInfo(guid)
	if not kind then return nil end
	local name = plain(UnitName(unit))
	if type(name) ~= "string" then name = nil end
	local e = entryFor(kind, id, name)
	local mapID, x, y = playerXY()
	if kind == "npc" then
		local level = tonumber(plain(UnitLevel(unit)))
		if level and level > 0 then
			e.minL = e.minL and math.min(e.minL, level) or level
			e.maxL = e.maxL and math.max(e.maxL, level) or level
		end
		local cls = plain(UnitClassification(unit))
		if type(cls) == "string" and cls ~= "normal" then e.cls = cls end
		local react = tonumber(plain(UnitReaction("player", unit)))
		if react then e.react = react end
		local ctype = plain(UnitCreatureType(unit))
		if type(ctype) == "string" then e.ctype = ctype end
	end
	if mapID then
		if exact then
			e.map, e.x, e.y, e.exact = mapID, x, y, true
		elseif not e.exact then
			e.samples = e.samples or {}
			if #e.samples < MAX_SAMPLES and farEnough(e, mapID, x, y) then tinsert(e.samples, { mapID, x, y }) end
			if not e.map then e.map, e.x, e.y = mapID, x, y end
		end
	end
	return e, kind, id
end

--- The NPC/object we are interacting with (gossip, quest, merchant, trainer, taxi frames).
local function noteInteraction(event)
	local unit = (event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "QUEST_GREETING") and "questnpc" or "npc"
	local e, kind, id = noteUnit(unit, true)
	if not e then e, kind, id = noteUnit(unit == "npc" and "questnpc" or "npc", true) end
	if not e then return nil end
	lastInteraction = { id = id, kind = kind, name = e.name, t = GetTime() }
	return e, kind, id
end

local function interactionRef()
	if lastInteraction and GetTime() - lastInteraction.t < 30 then
		return lastInteraction.kind == "object" and ("o" .. lastInteraction.id) or lastInteraction.id
	end
end

-- Quests --------------------------------------------------------------------------------------------------

local function questEntry(questID, title)
	local q = db.quests[questID]
	if not q then
		q = {}
		db.quests[questID] = q
	end
	if title and title ~= "" and not q.t then q.t = title end
	return q
end

local function objectivesOf(questID)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(objectives) ~= "table" then return nil end
	local list = {}
	for i, o in ipairs(objectives) do
		local text = o.text and o.text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "") or nil
		list[i] = { text = text, type = o.type, n = o.numRequired }
	end
	return #list > 0 and list or nil
end

local function snapshotObjectives(questID)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(objectives) ~= "table" then return end
	local state = {}
	for i, o in ipairs(objectives) do
		local n = tonumber(o.numFulfilled) or tonumber(o.text and o.text:match("(%d+)%s*/%s*%d+")) or 0
		state[i] = { finished = o.finished and true or false, num = n }
	end
	objectiveState[questID] = state
end

local function noteQuestFromLog(questID)
	local q = questEntry(questID, C_QuestLog.GetTitleForQuestID(questID))
	local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	local info = idx and C_QuestLog.GetInfo(idx)
	if info then
		if info.level and info.level > 0 then q.lvl = info.level end
		if info.suggestedGroup and info.suggestedGroup > 0 then q.group = info.suggestedGroup end
	end
	if not q.lvl and C_QuestLog.GetQuestDifficultyLevel then
		local lvl = C_QuestLog.GetQuestDifficultyLevel(questID)
		if lvl and lvl > 0 then q.lvl = lvl end
	end
	q.o = objectivesOf(questID) or q.o
	if C_QuestLog.GetQuestTagInfo then
		local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
		if ok and type(tag) == "table" and tag.tagName then q.tag = tag.tagName end
	end
	return q
end

local function recordSpot(q, key, index, single)
	local mapID, x, y = playerXY()
	if not mapID then return end
	q[key] = q[key] or {}
	if single then
		q[key][index] = { mapID, x, y }
	else
		local list = q[key][index] or {}
		q[key][index] = list
		if #list < 4 then tinsert(list, { mapID, x, y }) end
	end
end

local function diffObjectives()
	diffQueued = false
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local qid = info.questID
			local prev = objectiveState[qid]
			local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, qid)
			if prev and ok and type(objectives) == "table" then
				local q
				for idx, o in ipairs(objectives) do
					local before = prev[idx]
					local num = tonumber(o.numFulfilled) or tonumber(o.text and o.text:match("(%d+)%s*/%s*%d+")) or 0
					if before and num > (before.num or 0) then
						q = q or questEntry(qid, info.title)
						recordSpot(q, "prog", idx, false)
					end
					if o.finished and before and not before.finished then
						q = q or questEntry(qid, info.title)
						recordSpot(q, "done", idx, true)
					end
				end
			end
			snapshotObjectives(qid)
		end
	end
end

local function queueDiff()
	if diffQueued then return end
	diffQueued = true
	Guide:ScheduleTimer(diffObjectives, 0.3)
end

local function noteOffered(e, list, ends)
	if type(list) ~= "table" then return end
	for _, info in ipairs(list) do
		local qid = info.questID
		if qid then
			local q = questEntry(qid, info.title)
			if info.questLevel and info.questLevel > 0 then q.lvl = info.questLevel end
			if info.frequency and info.frequency ~= 0 then q.freq = info.frequency end
			if info.repeatable then q.rep = true end
			if ends then
				e.ends = e.ends or {}
				e.ends[qid] = true
			else
				e.gives = e.gives or {}
				e.gives[qid] = true
			end
		end
	end
end

local function noteGreeting(e)
	if GetNumAvailableQuests then
		for i = 1, GetNumAvailableQuests() do
			local _, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(i)
			if questID then
				local q = questEntry(questID, GetAvailableTitle and GetAvailableTitle(i))
				if frequency and frequency ~= 0 then q.freq = frequency end
				if isRepeatable then q.rep = true end
				e.gives = e.gives or {}
				e.gives[questID] = true
			end
		end
	end
	if GetNumActiveQuests and GetActiveQuestID then
		for i = 1, GetNumActiveQuests() do
			local questID = GetActiveQuestID(i)
			if questID then
				questEntry(questID, GetActiveTitle and GetActiveTitle(i))
				e.ends = e.ends or {}
				e.ends[questID] = true
			end
		end
	end
end

local function noteRewardXP(q)
	if not GetRewardXP then return end
	local xp = tonumber(plain(GetRewardXP()))
	local level = UnitLevel("player")
	if xp and xp > 0 and (not q.xp or level <= q.xp[1]) then q.xp = { level, xp } end
	if GetRewardMoney then
		local money = tonumber(plain(GetRewardMoney()))
		if money and money > 0 then q.money = money end
	end
end

-- Taxi --------------------------------------------------------------------------------------------------------

local function noteTaxi(e)
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
	local mapID = (_G.GetTaxiMapID and _G.GetTaxiMapID()) or C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not ok or type(nodes) ~= "table" then return end
	for _, node in ipairs(nodes) do
		if node.nodeID then
			local t = db.taxi[node.nodeID] or {}
			db.taxi[node.nodeID] = t
			t.name = node.name or t.name
			if node.position then
				local x, y = node.position:GetXY()
				t.map, t.x, t.y = mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
			end
			if node.state == Enum.FlightPathState.Current then
				t.state = "current"
				if e then e.taxiNode = node.nodeID end
				t.npc = e and lastInteraction and lastInteraction.id or t.npc
			elseif node.state == Enum.FlightPathState.Reachable then
				t.state = "reachable"
			elseif not t.state then
				t.state = "unreachable"
			end
			-- Reachable from the current node: the graph edges the router needs.
			if e and e.taxiNode and node.state == Enum.FlightPathState.Reachable then
				local cur = db.taxi[e.taxiNode]
				cur.links = cur.links or {}
				cur.links[node.nodeID] = true
			end
		end
	end
end

-- Levels -----------------------------------------------------------------------------------------------------

local function noteLevel()
	local level, max = UnitLevel("player"), UnitXPMax("player")
	if level and max and max > 0 then db.levels[level] = max end
end

-- Events -----------------------------------------------------------------------------------------------------

function Guide:HarvestOnEvent(event, ...)
	if not db then ensureDB() end
	if event == "GOSSIP_SHOW" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			local avail = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()
			local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
			if (avail and #avail > 0) or (active and #active > 0) then e.kind.quest = true end
			noteOffered(e, avail, false)
			noteOffered(e, active, true)
			for _, opt in ipairs((C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()) or {}) do
				local name = opt.name and opt.name:lower() or ""
				if name:find("inn your home", 1, true) or name:find("make this inn", 1, true) then e.kind.inn = true end
				if name:find("vendor", 1, true) or name:find("browse your goods", 1, true) then e.kind.vendor = true end
				if name:find("train", 1, true) then e.kind.trainer = true end
				if name:find("flight", 1, true) or name:find("fly", 1, true) then e.kind.taxi = true end
			end
		end
	elseif event == "QUEST_GREETING" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			e.kind.quest = true
			noteGreeting(e)
		end
	elseif event == "QUEST_DETAIL" then
		local questID = GetQuestID and GetQuestID()
		if questID and questID > 0 then
			local e = noteInteraction(event)
			local q = questEntry(questID, GetTitleText and GetTitleText())
			if e then
				e.kind = e.kind or {}
				e.kind.quest = true
				e.gives = e.gives or {}
				e.gives[questID] = true
				q.giver = interactionRef()
			elseif QuestGetAutoAccept and QuestGetAutoAccept() then
				q.auto = true
			end
			noteRewardXP(q)
		end
	elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
		local questID = GetQuestID and GetQuestID()
		if questID and questID > 0 then
			local e = noteInteraction(event)
			local q = questEntry(questID, GetTitleText and GetTitleText())
			if e then
				e.kind = e.kind or {}
				e.kind.quest = true
				e.ends = e.ends or {}
				e.ends[questID] = true
				q.ender = interactionRef()
			end
			if event == "QUEST_COMPLETE" then noteRewardXP(q) end
		end
	elseif event == "QUEST_ACCEPTED" then
		local questID = ...
		if type(questID) == "number" then
			local q = noteQuestFromLog(questID)
			q.giver = q.giver or interactionRef()
			local mapID, x, y = playerXY()
			if mapID then q.acceptAt = { mapID, x, y } end
			snapshotObjectives(questID)
		end
	elseif event == "QUEST_TURNED_IN" then
		local questID, xp, money = ...
		if type(questID) == "number" then
			local q = questEntry(questID, C_QuestLog.GetTitleForQuestID(questID))
			q.ender = q.ender or interactionRef()
			local level = UnitLevel("player")
			if type(xp) == "number" and xp > 0 and (not q.xp or level <= q.xp[1]) then q.xp = { level, xp } end
			if type(money) == "number" and money > 0 then q.money = money end
			local mapID, x, y = playerXY()
			if mapID then q.turninAt = { mapID, x, y } end
			q.done = true
			objectiveState[questID] = nil
		end
	elseif event == "QUEST_REMOVED" then
		local questID = ...
		if type(questID) == "number" then objectiveState[questID] = nil end
	elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
		queueDiff()
	elseif event == "PLAYER_TARGET_CHANGED" then
		noteUnit("target", false)
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		noteUnit("mouseover", false)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		if type(unit) == "string" then noteUnit(unit, false) end
	elseif event == "MERCHANT_SHOW" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			e.kind.vendor = true
			if CanMerchantRepair and CanMerchantRepair() then e.kind.repair = true end
		end
	elseif event == "TRAINER_SHOW" then
		local e = noteInteraction(event)
		if e then e.kind = e.kind or {} e.kind.trainer = true end
	elseif event == "TAXIMAP_OPENED" then
		local e = noteInteraction(event)
		if e then e.kind = e.kind or {} e.kind.taxi = true end
		noteTaxi(e)
	elseif event == "HEARTHSTONE_BOUND" then
		local e = noteInteraction("GOSSIP_SHOW")
		if e then e.kind = e.kind or {} e.kind.inn = true end
	elseif event == "PLAYER_LEVEL_UP" then
		self:ScheduleTimer(noteLevel, 1)
	elseif event == "PLAYER_ENTERING_WORLD" then
		noteLevel()
		wipe(objectiveState)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				snapshotObjectives(info.questID)
				noteQuestFromLog(info.questID)
			end
		end
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		self:ScanOnLoadResult(...)
	end
end

-- Read-back for smart mode --------------------------------------------------------------------------------------

local function refPosition(ref)
	if not ref then return nil end
	local e
	if type(ref) == "string" then e = db.objects[tonumber(ref:sub(2))] else e = db.npcs[ref] end
	if e and e.map and e.x and e.y then return e.map, e.x, e.y, e.name end
	return nil
end

--- Best known position for a quest in the log: mapID, x, y (0..1), how.
function Guide:HarvestQuestPosition(questID, complete)
	if not db then ensureDB() end
	local q = db.quests[questID]
	if not q then return nil end
	local mapID, x, y, how
	if complete then
		mapID, x, y = refPosition(q.ender)
		how = "ender"
		if not mapID and q.turninAt then mapID, x, y, how = q.turninAt[1], q.turninAt[2], q.turninAt[3], "turnin" end
		if not mapID then
			-- Most Classic quests end where they began; say so in the subtitle via `how`.
			mapID, x, y = refPosition(q.giver)
			how = "giver"
			if not mapID and q.acceptAt then mapID, x, y, how = q.acceptAt[1], q.acceptAt[2], q.acceptAt[3], "accept" end
		end
	else
		local objectives = C_QuestLog.GetQuestObjectives(questID)
		local idx
		for i, o in ipairs(objectives or {}) do if not o.finished then idx = i break end end
		idx = idx or 1
		local spot = q.done and q.done[idx]
		if spot then mapID, x, y, how = spot[1], spot[2], spot[3], "done" end
		if not mapID and q.prog and q.prog[idx] and q.prog[idx][1] then
			local s = q.prog[idx][1]
			mapID, x, y, how = s[1], s[2], s[3], "progress"
		end
	end
	if not mapID then return nil end
	return mapID, x / 100, y / 100, how
end

--- Quests harvested quest givers on this map offer that the player can still pick up.
function Guide:HarvestAvailableItems(items, mapID)
	if not db then ensureDB() end
	local level = UnitLevel("player")
	local seen = {}
	for _, it in ipairs(items) do if it.questID then seen[it.questID] = true end end
	local function fromStore(store, isObject)
		for id, e in pairs(store) do
			if e.map == mapID and e.gives and e.x and e.y then
				for qid in pairs(e.gives) do
					if not seen[qid] and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid) then
						local q = db.quests[qid]
						local lvl = q and q.lvl
						local trivial = lvl and (level - lvl) >= 6
						if not trivial and not (q and q.done) then
							seen[qid] = true
							tinsert(items, { kind = "available", questID = qid, mapID = mapID, x = e.x / 100, y = e.y / 100, source = "harvest",
								title = (q and q.t) or C_QuestLog.GetTitleForQuestID(qid) or ("Quest " .. qid),
								subtitle = "Pick up from " .. (e.name or (isObject and "object" or ("NPC " .. id))) .. (lvl and (" · lvl " .. lvl) or ""),
								level = lvl })
						end
					end
				end
			end
		end
	end
	fromStore(db.npcs, false)
	fromStore(db.objects, true)
end

-- Quest census: /lode scan quests ------------------------------------------------------------------------------

local function scanRecord(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if not title or title == "" then return false end
	local q = questEntry(questID, title)
	q.t = q.t or title
	q.o = objectivesOf(questID) or q.o
	if C_QuestLog.GetQuestDifficultyLevel and not q.lvl then
		local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
		if ok and lvl and lvl > 0 then q.lvl = lvl end
	end
	if C_QuestLog.GetQuestTagInfo and not q.tag then
		local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
		if ok and type(tag) == "table" and tag.tagName then q.tag = tag.tagName end
	end
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
		local ok, cls = pcall(C_QuestInfoSystem.GetQuestClassification, questID)
		if ok and type(cls) == "number" then q.cls = cls end
	end
	if C_QuestLog.IsQuestFlaggedCompleted(questID) then q.done = true end
	q.scanned = true
	return true
end

function Guide:ScanOnLoadResult(questID, success)
	if not scanPending[questID] then return end
	scanPending[questID] = nil
	local s = db.scan
	if success and scanRecord(questID) then s.found = (s.found or 0) + 1 end
end

local function scanTick()
	local s = db.scan
	if not s.next or s.next > s.to then
		Guide:StopScan(true)
		return
	end
	local n = 0
	while n < (s.batch or SCAN_BATCH) and s.next <= s.to do
		local id = s.next
		s.next = s.next + 1
		s.checked = (s.checked or 0) + 1
		if scanRecord(id) then
			s.found = (s.found or 0) + 1        -- already cached; no request needed
		else
			scanPending[id] = true
			pcall(C_QuestLog.RequestLoadQuestByID, id)
		end
		n = n + 1
	end
	if s.checked % 500 == 0 then
		Lodestar:Msg("Quest scan: %d/%d checked, %d quests found.", s.next - s.from, s.to - s.from + 1, s.found or 0)
	end
end

function Guide:StartScan(from, to)
	if not db then ensureDB() end
	local s = db.scan
	if scanTicker then Lodestar:Say("A scan is already running (%d/%d). /lode scan stop", s.next - s.from, s.to - s.from + 1) return end
	if from then
		s.from, s.to, s.next, s.checked, s.found = from, to, from, 0, 0
	elseif not s.next or not s.to or s.next > s.to then
		Lodestar:Say("Usage: /lode scan quests <from> <to>   e.g. /lode scan quests 1 10000")
		return
	end
	s.startedAt = time()
	scanTicker = self:ScheduleRepeatingTimer(scanTick, SCAN_TICK)
	Lodestar:Say("Scanning quest ids %d-%d (%d per second). Keep playing; /lode scan status for progress, /lode scan stop to pause.",
		s.next, s.to, math.floor((s.batch or SCAN_BATCH) / SCAN_TICK))
end

function Guide:StopScan(finished)
	if scanTicker then self:CancelTimer(scanTicker) scanTicker = nil end
	local s = db and db.scan
	if not s then return end
	if finished then
		Lodestar:Say("Quest scan finished: %d ids checked, %d quests found. They are saved account-wide; /reload or log out to write them to disk.", s.checked or 0, s.found or 0)
		s.finishedAt = time()
	else
		Lodestar:Say("Quest scan paused at %d (%d found). /lode scan resume to continue.", s.next or 0, s.found or 0)
	end
end

local function scanStatus()
	local s = db.scan
	local nQ, nN, nO, nT = 0, 0, 0, 0
	for _ in pairs(db.quests) do nQ = nQ + 1 end
	for _ in pairs(db.npcs) do nN = nN + 1 end
	for _ in pairs(db.objects) do nO = nO + 1 end
	for _ in pairs(db.taxi) do nT = nT + 1 end
	Lodestar:Say("Harvest: %d quests, %d NPCs, %d objects, %d flight nodes.", nQ, nN, nO, nT)
	if s.to then
		Lodestar:Say("Quest scan %s: ids %d-%d, at %d, %d checked, %d found.", scanTicker and "running" or "stopped",
			s.from or 0, s.to, s.next or 0, s.checked or 0, s.found or 0)
	end
end

local function handleScan(rest)
	if not db then ensureDB() end
	local verb, a, b = strsplit(" ", strtrim(rest or ""), 3)
	verb = (verb or ""):lower()
	if verb == "quests" or verb == "quest" then
		local from, to = tonumber(a), tonumber(b)
		if from and not to then to = from + 9999 end
		if from and to and to >= from then Guide:StartScan(math.max(1, from), to) else Guide:StartScan() end
	elseif verb == "resume" then
		Guide:StartScan()
	elseif verb == "stop" or verb == "pause" then
		if scanTicker then Guide:StopScan(false) else Lodestar:Say("No scan running.") end
	elseif verb == "status" or verb == "" then
		scanStatus()
	elseif verb == "rate" then
		local n = tonumber(a)
		if n and n >= 1 and n <= 200 then
			db.scan.batch = math.max(1, math.floor(n * SCAN_TICK + 0.5))
			Lodestar:Say("Scan rate: about %d ids per second.", math.floor(db.scan.batch / SCAN_TICK))
		else
			Lodestar:Say("Usage: /lode scan rate <ids per second, 1-200>")
		end
	elseif verb == "npc" then
		local e, kind, id = noteUnit("target", false)
		if not e then Lodestar:Say("Target a creature first.") return end
		Lodestar:Say("%s #%d (%s): level %s-%s, at %s %.1f,%.1f%s", e.name or "?", id, kind, tostring(e.minL), tostring(e.maxL),
			tostring(e.map), e.x or 0, e.y or 0, e.exact and " (exact)" or " (approx)")
	elseif verb == "wipe" then
		if a == "confirm" then
			wipe(db.npcs) wipe(db.objects) wipe(db.quests) wipe(db.taxi) wipe(db.scan)
			Lodestar:Say("Harvest wiped.")
		else
			Lodestar:Say("This deletes everything harvested on this account. Type /lode scan wipe confirm to do it.")
		end
	else
		Lodestar:Say("Usage: /lode scan [status | quests <from> <to> | resume | stop | rate <n> | npc | wipe]")
	end
end

-- Diagnostics ------------------------------------------------------------------------------------------------------

--- `/lode guide diag`: what the guide sees for every quest in the log, printed and saved to LodestarProbeDB.
function Guide:Diagnose()
	if not db then ensureDB() end
	local out = { when = date("%Y-%m-%d %H:%M:%S"), quests = {}, arrow = {}, smart = {} }
	local mapID = C_Map.GetBestMapForUnit("player")
	out.mapID = mapID
	local info = mapID and C_Map.GetMapInfo(mapID)
	out.mapName = info and info.name
	out.playerPos = { playerXY() }
	local pois = {}
	if mapID and C_QuestLog.GetQuestsOnMap then
		local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
		out.questsOnMapOK = ok
		out.questsOnMapErr = (not ok) and tostring(list) or nil
		if ok and type(list) == "table" then
			out.questsOnMap = #list
			for _, p in ipairs(list) do pois[p.questID or 0] = { p.x, p.y, p.type } end
		end
	end
	local sources = self:SmartSources()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local qi = C_QuestLog.GetInfo(i)
		if qi and not qi.isHeader and qi.questID then
			local qid = qi.questID
			local d = { title = qi.title, level = qi.level, complete = C_QuestLog.IsComplete(qid) and true or false, isOnMap = qi.isOnMap, hasLocalPOI = qi.hasLocalPOI, isHidden = qi.isHidden, isTask = qi.isTask }
			local ok, wmap, wx, wy = pcall(C_QuestLog.GetNextWaypoint, qid)
			d.nextWaypoint = ok and wmap and { wmap, wx, wy } or (ok and "nil" or ("error: " .. tostring(wmap)))
			if C_QuestLog.GetNextWaypointForMap and mapID then
				local ok2, fx, fy = pcall(C_QuestLog.GetNextWaypointForMap, qid, mapID)
				d.nextWaypointForMap = ok2 and fx and { fx, fy } or (ok2 and "nil" or ("error: " .. tostring(fx)))
			end
			local ok3, distSq, onCont = pcall(C_QuestLog.GetDistanceSqToQuest, qid)
			d.distSq = ok3 and distSq or ("error: " .. tostring(distSq))
			d.onContinent = ok3 and onCont or nil
			d.poi = pois[qid]
			d.source = sources[qid]
			local hmap, hx, hy, how = self:HarvestQuestPosition(qid, d.complete)
			d.harvest = hmap and { hmap, hx, hy, how } or nil
			out.quests[qid] = d
		end
	end
	local t = self:GetArrowTarget()
	local cfg = self.db.profile.arrow
	out.arrow = { mode = cfg.mode, show = cfg.show, frameShown = _G.LodestarArrow and _G.LodestarArrow:IsShown() or false,
		target = t and { kind = t.kind, title = t.title, mapID = t.mapID, x = t.x, y = t.y, continent = t.continent } or "none",
		facing = GetPlayerFacing and GetPlayerFacing() or nil, pos = cfg.pos }
	local items = self:CollectSmartItems(true)
	for i, it in ipairs(items) do
		if i > 12 then break end
		out.smart[i] = { kind = it.kind, title = it.title, dist = it.dist, source = it.source, noPosition = it.noPosition or nil }
	end
	out.guide = self.current and { name = self.current.name, step = self.stepIndex } or "smart mode"
	out.harvest = {}
	for k, v in pairs({ npcs = db.npcs, objects = db.objects, quests = db.quests, taxi = db.taxi }) do
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		out.harvest[k] = n
	end
	if type(_G.LodestarProbeDB) ~= "table" then _G.LodestarProbeDB = {} end
	_G.LodestarProbeDB.guideDiag = out

	Lodestar:Say("Guide diag — map %s (%s), %s, arrow target: %s", tostring(mapID), tostring(out.mapName), type(out.guide) == "table" and out.guide.name or out.guide, t and t.title or "none")
	local n = 0
	for qid, d in pairs(out.quests) do
		n = n + 1
		Lodestar:Say("  %d %s%s — waypoint: %s, poi: %s, harvest: %s, dist: %s", qid, d.title or "?", d.complete and " |cff7fff7f(complete)|r" or "",
			type(d.nextWaypoint) == "table" and "yes" or tostring(d.nextWaypoint), d.poi and "yes" or "no", d.harvest and d.harvest[4] or "no",
			type(d.distSq) == "number" and tostring(math.floor(math.sqrt(math.max(d.distSq, 0)))) or tostring(d.distSq))
	end
	Lodestar:Say("%d quests. Saved to LodestarProbeDB.guideDiag (written on /reload or logout).", n)
end

-- Lifecycle -------------------------------------------------------------------------------------------------------

function Guide:EnableHarvest()
	ensureDB()
	if not self.scanSlash then
		self.scanSlash = true
		Lodestar:RegisterSlashVerb("scan", handleScan, "harvest status, quest census: /lode scan quests <from> <to>")
	end
	-- Resume an interrupted census automatically.
	local s = db.scan
	if s.next and s.to and s.next <= s.to and not s.finishedAt then
		self:ScheduleTimer(function() if not scanTicker then self:StartScan() end end, 10)
	end
end

function Guide:DisableHarvest()
	if scanTicker then self:CancelTimer(scanTicker) scanTicker = nil end
end

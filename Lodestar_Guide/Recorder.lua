-- Lodestar_Guide: route recorder — logs what you do while leveling and exports it as a guide.
--
--   /lode record start [name]   begin (or resume) a recording; survives /reload
--   /lode record stop           stop recording
--   /lode record export         build the guide text, register it, and open it in a copy box
--   /lode record status         what has been captured so far
--   /lode record discard        throw the current recording away
--
-- Captured per entry: position (map, x, y), your level, and for quests the quest's level, the NPC
-- you talked to and the levels of mobs killed while working on objectives — the raw material a
-- route optimizer needs to judge pickups, mob difficulty and run-backs.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local HUB_YARDS = 20      -- accepts/turn-ins within this distance and time become one step
local HUB_SECONDS = 180

local objectiveState = {} -- [questID] = { [index] = finished }
local recentTargets = {}  -- [guid] = { name, level, t }
local mobsSinceLastStep = {}
local lastNpc              -- { name, guid, t }
local flightStart

local function rec() return Guide.db.char.recording end

local function here()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return nil end
	return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function npcName()
	if lastNpc and GetTime() - lastNpc.t < 30 then return lastNpc.name, lastNpc.id end
	return nil
end

local function mobSummary()
	local parts = {}
	for name, m in pairs(mobsSinceLastStep) do
		tinsert(parts, ("%s x%d (lvl %s)"):format(name, m.count, m.min == m.max and tostring(m.min) or (m.min .. "-" .. m.max)))
	end
	table.sort(parts)
	wipe(mobsSinceLastStep)
	return #parts > 0 and table.concat(parts, ", ") or nil
end

local function add(entry)
	local r = rec()
	if not r then return end
	local mapID, x, y = here()
	entry.map, entry.x, entry.y = mapID, x, y
	entry.t = time()
	entry.level = UnitLevel("player")
	tinsert(r.entries, entry)
	Lodestar:Debug("record: %s", entry.type)
end

-- Event capture --------------------------------------------------------------------------------------

local function snapshotObjectives(questID)
	local objectives = C_QuestLog.GetQuestObjectives(questID)
	local state = {}
	for i, o in ipairs(objectives or {}) do state[i] = o.finished and true or false end
	objectiveState[questID] = state
end

local function diffObjectives()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local qid = info.questID
			local prev = objectiveState[qid]
			local objectives = C_QuestLog.GetQuestObjectives(qid)
			if prev and objectives then
				for idx, o in ipairs(objectives) do
					if o.finished and prev[idx] == false then
						local text = o.text and o.text:gsub(":%s*%d+%s*/%s*%d+%s*$", "") or nil
						add({ type = "complete", questID = qid, objective = idx, text = text, title = info.title, mobs = mobSummary() })
					end
				end
			end
			snapshotObjectives(qid)
		end
	end
end

function Guide:RecorderOnEvent(event, ...)
	-- Track the NPC we are talking to even when not recording (cheap) so accepts have a name.
	if event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" or event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then
		local unit = (event == "QUEST_DETAIL" or event == "QUEST_COMPLETE") and "questnpc" or "npc"
		local name = UnitName(unit) or UnitName("npc") or UnitName("questnpc")
		if name then lastNpc = { name = name, id = Lodestar.NpcIDFromGUID(UnitGUID(unit) or UnitGUID("npc")), t = GetTime() } end
	end
	if not rec() then return end

	if event == "QUEST_ACCEPTED" then
		local questID = ...
		if type(questID) ~= "number" then return end
		local name, id = npcName()
		local title = C_QuestLog.GetTitleForQuestID(questID)
		local qlevel = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)
		add({ type = "accept", questID = questID, title = title, npc = name, npcID = id, questLevel = qlevel })
		snapshotObjectives(questID)
	elseif event == "QUEST_TURNED_IN" then
		local questID, xp = ...
		local name, id = npcName()
		add({ type = "turnin", questID = questID, title = C_QuestLog.GetTitleForQuestID(questID), npc = name, npcID = id, xp = xp, mobs = mobSummary() })
		objectiveState[questID] = nil
	elseif event == "QUEST_REMOVED" then
		local questID = ...
		objectiveState[questID] = nil
	elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
		diffObjectives()
	elseif event == "PLAYER_LEVEL_UP" then
		add({ type = "level", level = ... })
	elseif event == "HEARTHSTONE_BOUND" then
		add({ type = "hs", name = GetBindLocation and GetBindLocation() or GetSubZoneText() })
	elseif event == "TRAINER_SHOW" then
		add({ type = "train", npc = UnitName("npc") })
	elseif event == "TAXIMAP_OPENED" then
		flightStart = GetTime()
	elseif event == "PLAYER_CONTROL_LOST" then
		if flightStart and GetTime() - flightStart < 60 then
			add({ type = "flyStart" })
		end
	elseif event == "PLAYER_CONTROL_GAINED" then
		local r = rec()
		local last = r.entries[#r.entries]
		if last and last.type == "flyStart" then
			add({ type = "fly", name = GetSubZoneText() ~= "" and GetSubZoneText() or GetRealZoneText() })
		end
		flightStart = nil
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		add({ type = "zone", name = GetRealZoneText() })
	elseif event == "MERCHANT_SHOW" then
		add({ type = "vendor", npc = UnitName("npc") })
	elseif event == "PLAYER_TARGET_CHANGED" then
		local guid = UnitGUID("target")
		if guid and UnitCanAttack and UnitCanAttack("player", "target") and not UnitIsPlayer("target") then
			recentTargets[guid] = { name = UnitName("target"), level = UnitLevel("target"), t = GetTime() }
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		-- Undocumented in the generated API docs but present (the deprecated global aliases it).
		local ns = _G.C_CombatLog
		local getInfo = (ns and ns.GetCurrentEventInfo) or _G.CombatLogGetCurrentEventInfo
		if not getInfo then return end
		local ok, _, subevent, _, _, _, _, _, destGUID = pcall(getInfo)
		if ok and subevent == "UNIT_DIED" and destGUID then
			local mob = recentTargets[destGUID]
			if mob and mob.name then
				local lvl = tonumber(mob.level) or 0
				local m = mobsSinceLastStep[mob.name]
				if not m then
					mobsSinceLastStep[mob.name] = { count = 1, min = lvl, max = lvl }
				else
					m.count = m.count + 1
					if lvl < m.min then m.min = lvl end
					if lvl > m.max then m.max = lvl end
				end
				recentTargets[destGUID] = nil
			end
		end
	end
end

-- Export -----------------------------------------------------------------------------------------------

local function distanceBetween(a, b)
	if not (a.map and b.map and a.x and b.x) then return math.huge end
	local ca, ax, ay = Guide:WorldPos(a.map, a.x / 100, a.y / 100)
	local cb, bx, by = Guide:WorldPos(b.map, b.x / 100, b.y / 100)
	if not ca or not cb or ca ~= cb then return math.huge end
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function gotoLine(e)
	if not e.map then return nil end
	return ("  .goto %d,%.1f,%.1f"):format(e.map, e.x, e.y)
end

local function questLine(directive, e)
	local text = e.title and (" >>" .. ({ accept = "Accept ", turnin = "Turn in " })[directive] .. e.title) or ""
	local comment = {}
	if e.npc then tinsert(comment, e.npc) end
	if e.questLevel then tinsert(comment, "quest lvl " .. e.questLevel) end
	if e.xp then tinsert(comment, e.xp .. " xp") end
	return ("  .%s %d%s%s"):format(directive, e.questID, text, #comment > 0 and ("   -- " .. table.concat(comment, ", ")) or "")
end

--- Build guide text from the recording.
function Guide:BuildRecordingText(r)
	local pf = self:PlayerFilters()
	local raceName = UnitRace("player")
	local className = UnitClass("player")
	local minLevel, maxLevel = math.huge, 0
	for _, e in ipairs(r.entries) do
		if e.level then minLevel, maxLevel = math.min(minLevel, e.level), math.max(maxLevel, e.level) end
	end
	if minLevel == math.huge then minLevel, maxLevel = pf.level, pf.level end
	local out = {
		"#guide " .. (r.name or "Recorded route"),
		"#faction " .. (pf.faction or "Both"),
		"#race " .. (raceName or ""),
		"#class " .. (className or ""),
		("#levels %d-%d"):format(minLevel, maxLevel),
		"#author " .. Lodestar.player.name,
		("#note Recorded with Lodestar %s on %s. Draft: verify positions and order."):format(Lodestar.version, date("%Y-%m-%d", r.startedAt or time())),
		"",
	}
	local i = 1
	local entries = r.entries
	local lastLevel
	while i <= #entries do
		local e = entries[i]
		if e.type == "accept" or e.type == "turnin" then
			-- Hub: gather consecutive accept/turnin entries close in space and time.
			local group = { e }
			local j = i + 1
			while j <= #entries do
				local n = entries[j]
				if (n.type == "accept" or n.type == "turnin") and (n.t - e.t) <= HUB_SECONDS and distanceBetween(e, n) <= HUB_YARDS then
					tinsert(group, n)
					j = j + 1
				else
					break
				end
			end
			tinsert(out, "step")
			local g = gotoLine(e)
			if g then tinsert(out, g) end
			-- turn-ins first, then accepts, matching how you'd play a hub
			for _, ge in ipairs(group) do if ge.type == "turnin" then tinsert(out, questLine("turnin", ge)) end end
			for _, ge in ipairs(group) do if ge.type == "accept" then tinsert(out, questLine("accept", ge)) end end
			if e.level ~= lastLevel then tinsert(out, "  -- level " .. tostring(e.level)) lastLevel = e.level end
			tinsert(out, "")
			i = j
		elseif e.type == "complete" then
			tinsert(out, "step")
			local g = gotoLine(e)
			if g then tinsert(out, g) end
			tinsert(out, ("  .complete %d,%d%s"):format(e.questID, e.objective or 1, e.text and (" >>" .. e.text) or ""))
			if e.mobs then tinsert(out, "  -- mobs: " .. e.mobs) end
			if e.level ~= lastLevel then tinsert(out, "  -- level " .. tostring(e.level)) lastLevel = e.level end
			tinsert(out, "")
			i = i + 1
		elseif e.type == "hs" then
			tinsert(out, "step")
			local g = gotoLine(e) if g then tinsert(out, g) end
			tinsert(out, "  .hs " .. (e.name or ""))
			tinsert(out, "")
			i = i + 1
		elseif e.type == "train" then
			tinsert(out, "step")
			local g = gotoLine(e) if g then tinsert(out, g) end
			tinsert(out, "  .train" .. (e.npc and (" >>Train at " .. e.npc) or ""))
			tinsert(out, "")
			i = i + 1
		elseif e.type == "fly" then
			tinsert(out, "step")
			tinsert(out, "  .fly " .. (e.name or ""))
			tinsert(out, "")
			i = i + 1
		elseif e.type == "level" then
			tinsert(out, ("-- reached level %d at %s"):format(e.level or 0, e.map and ("%d,%.1f,%.1f"):format(e.map, e.x, e.y) or "?"))
			i = i + 1
		elseif e.type == "zone" then
			tinsert(out, "-- entered " .. (e.name or "?"))
			i = i + 1
		elseif e.type == "vendor" then
			tinsert(out, "-- vendor: " .. (e.npc or "?") .. (e.map and (" at %d,%.1f,%.1f"):format(e.map, e.x, e.y) or ""))
			i = i + 1
		else
			i = i + 1
		end
	end
	return table.concat(out, "\n")
end

-- Commands --------------------------------------------------------------------------------------------------

local function status()
	local r = rec()
	if not r then Lodestar:Say("Not recording. /lode record start [name]") return end
	local counts = {}
	for _, e in ipairs(r.entries) do counts[e.type] = (counts[e.type] or 0) + 1 end
	Lodestar:Say("Recording '%s' since %s: %d accepts, %d objectives, %d turn-ins, %d level-ups, %d entries total.",
		r.name, date("%H:%M", r.startedAt or time()), counts.accept or 0, counts.complete or 0, counts.turnin or 0, counts.level or 0, #r.entries)
end

local function handleRecord(rest)
	local verb, arg = strsplit(" ", strtrim(rest or ""), 2)
	verb = (verb or ""):lower()
	local char = Guide.db.char
	if verb == "start" then
		if char.recording then
			Lodestar:Say("Already recording '%s' — continuing. /lode record status", char.recording.name)
			return
		end
		local name = arg and arg ~= "" and arg or ("%s/%s %d %s"):format(Lodestar.player.faction or "?", UnitRace("player") or "?", UnitLevel("player"), GetRealZoneText() or "")
		char.recording = { name = name, startedAt = time(), entries = {} }
		wipe(objectiveState)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then snapshotObjectives(info.questID) end
		end
		Lodestar:Say("Recording '%s'. Play normally; /lode record export when you're done.", name)
	elseif verb == "stop" then
		if not char.recording then Lodestar:Say("Not recording.") return end
		Lodestar:Say("Stopped recording '%s' (%d entries kept). /lode record export to build the guide.", char.recording.name, #char.recording.entries)
		char.recordingPaused = char.recording
		char.recording = nil
	elseif verb == "resume" then
		if char.recording then Lodestar:Say("Already recording.") return end
		if not char.recordingPaused then Lodestar:Say("Nothing to resume.") return end
		char.recording = char.recordingPaused
		char.recordingPaused = nil
		Lodestar:Say("Resumed recording '%s'.", char.recording.name)
	elseif verb == "status" then
		status()
	elseif verb == "export" then
		local r = char.recording or char.recordingPaused
		if not r then Lodestar:Say("Nothing recorded yet.") return end
		if #r.entries == 0 then Lodestar:Say("The recording is empty so far.") return end
		local text = Guide:BuildRecordingText(r)
		char.recordings[r.name] = text
		Guide:RegisterGuide(text, "recording")
		Lodestar:ShowCopyBox(text, "Recorded guide — paste into a guide pack file")
		Lodestar:Say("Exported '%s' (%d entries). It is also loaded as a guide: /lode guide load %s", r.name, #r.entries, r.name)
	elseif verb == "discard" then
		char.recording = nil
		char.recordingPaused = nil
		Lodestar:Say("Recording discarded.")
	elseif verb == "list" then
		local n = 0
		for name in pairs(char.recordings) do n = n + 1 Lodestar:Say("  %s", name) end
		if n == 0 then Lodestar:Say("No exported recordings on this character.") end
	elseif verb == "show" then
		local text = arg and char.recordings[arg]
		if text then Lodestar:ShowCopyBox(text, arg) else Lodestar:Say("Usage: /lode record show <name> (see /lode record list)") end
	else
		Lodestar:Say("Usage: /lode record start [name] | stop | resume | status | export | discard | list | show <name>")
	end
end

function Guide:EnableRecorder()
	if not self.recordSlash then
		self.recordSlash = true
		Lodestar:RegisterSlashVerb("record", handleRecord, "record your route as a guide: /lode record start|stop|export")
	end
	-- Combat events are registered here (not in the shared list) so they cost nothing unless recording.
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnGameEvent")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnGameEvent")
	-- Previously exported recordings are available as guides.
	for _, text in pairs(self.db.char.recordings) do self:RegisterGuide(text, "recording") end
	if self.db.char.recording then
		Lodestar:Msg("Route recording '%s' is active (%d entries).", self.db.char.recording.name, #self.db.char.recording.entries)
	end
end

function Guide:DisableRecorder()
	self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

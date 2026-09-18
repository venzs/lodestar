-- Lodestar_Guide: guide registry, current step, completion detection and auto-advance.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")
local Parser = Guide.Parser

Guide.guides = {}         -- parsed guides in registration order
Guide.guideByName = {}
Guide.current = nil       -- parsed guide table
Guide.stepIndex = nil
Guide.stepFlags = {}      -- [stepIndex] = { hs = true, train = true, fly = true, manual = true }

local evalQueued = false
local arrivalTicker
local recentTurnIn, recentAccept = {}, {}   -- questID -> GetTime(); the server flag lags the event by a few seconds
local TURNIN_GRACE, ACCEPT_GRACE = 6, 3
local TRAINER_RANGE = 300                   -- yards; farther trainers are not suggested
local TRAINER_RECHECK = 5                   -- seconds between trainer suggestion recomputes
local trainerSuggestion, trainerSuggestedAt

-- Registry ---------------------------------------------------------------------------------------

--- Register guide text (from a guide pack or a recording). Returns the guide or nil, error.
function Guide:RegisterGuide(text, source)
	local guide, err = Parser.Parse(text)
	if not guide then
		Lodestar:Say("Guide failed to load%s: %s", source and (" (" .. source .. ")") or "", tostring(err))
		return nil, err
	end
	guide.pack = source
	if self.guideByName[guide.name] then
		-- replace in place (a newer pack version, or a re-registered recording)
		for i, g in ipairs(self.guides) do
			if g.name == guide.name then self.guides[i] = guide end
		end
	else
		tinsert(self.guides, guide)
	end
	self.guideByName[guide.name] = guide
	if self.current and self.current.name == guide.name then
		self.current = guide
		self:RefreshStepFrame()
	end
	return guide
end

--- Player descriptors used for guide/step filters (all lower-case).
function Guide:PlayerFilters()
	local raceName, raceFile = UnitRace("player")
	return {
		faction = Lodestar.player.faction,
		class = (Lodestar.player.class or ""):lower(),
		className = (UnitClass("player") or ""):lower(),
		race = (raceName or ""):lower(),
		raceFile = (raceFile or ""):lower(),
		level = UnitLevel("player"),
	}
end

local function hasItem(itemID)
	if not (C_Item and C_Item.GetItemCount) then return true end -- cannot tell: never skip
	return (C_Item.GetItemCount(itemID) or 0) > 0 -- bags only: .item means carried, not banked
end

local function stepApplies(step, pf)
	if step.classes and not (step.classes[pf.class] or step.classes[pf.className]) then return false end
	if step.races and not (step.races[pf.race] or step.races[pf.raceFile]) then return false end
	if step.optional and not Guide.db.profile.steps.completionist then return false end
	if step.requireItems then
		for _, id in ipairs(step.requireItems) do
			if not hasItem(id) then return false end
		end
	end
	return true
end

--- Does a step of the current guide apply to this character right now (class, race, optional, items)?
function Guide:StepApplies(step, pf)
	return stepApplies(step, pf or self:PlayerFilters())
end

local function guideApplies(guide, pf, ignoreLevel)
	if guide.faction ~= "Both" and pf.faction and guide.faction ~= pf.faction then return false end
	if guide.classes and not (guide.classes[pf.class] or guide.classes[pf.className]) then return false end
	if guide.races and not (guide.races[pf.race] or guide.races[pf.raceFile]) then return false end
	if not ignoreLevel and guide.minLevel and guide.maxLevel and (pf.level < guide.minLevel or pf.level > guide.maxLevel) then return false end
	return true
end

--- Guides that apply to this character.
function Guide:ApplicableGuides(ignoreLevel)
	local pf = self:PlayerFilters()
	local list = {}
	for _, g in ipairs(self.guides) do
		if guideApplies(g, pf, ignoreLevel) then tinsert(list, g) end
	end
	return list
end

--- Choose the best guide for the character: most specific match covering the current level,
--- else the applicable guide with the lowest level range above the player, else anything applicable.
function Guide:PickGuide()
	local pf = self:PlayerFilters()
	local best, bestScore
	for _, g in ipairs(self.guides) do
		local outleveled = g.maxLevel and pf.level > g.maxLevel
		if guideApplies(g, pf, true) and not outleveled then
			local covers = g.minLevel and g.maxLevel and pf.level >= g.minLevel and pf.level <= g.maxLevel
			local specificity = (g.races and 2 or 0) + (g.classes and 2 or 0) + (g.faction ~= "Both" and 1 or 0)
			local score
			if covers then
				score = 1000 + specificity
			elseif g.minLevel and g.minLevel > pf.level then
				score = 500 - (g.minLevel - pf.level) + specificity * 0.1
			else
				score = specificity
			end
			if not bestScore or score > bestScore then best, bestScore = g, score end
		end
	end
	return best
end

-- Loading ------------------------------------------------------------------------------------------

function Guide:LoadGuide(name, stepIndex)
	local guide = name and self.guideByName[name]
	if not guide then
		if name then Lodestar:Say("No guide called %s.", tostring(name)) end
		return false
	end
	self.current = guide
	self.stepFlags = {}
	self.finished = nil
	self.db.char.currentGuide = guide.name
	local saved = self.db.char.progress[guide.name]
	local synced
	if not stepIndex then
		-- Sync to the character, not to the saved position: a character that is mid-way (or has played
		-- without the guide) lands on the step after the last one its completed quests account for.
		local start, _, open = self:SuggestStartIndex(guide)
		if not saved then
			stepIndex, synced = start, { open = open }
		elseif start > saved then
			-- Never step over work the character still has open: that is the player's real position.
			-- The window's Sync button (and /lode guide sync) still jump on demand.
			local openBetween = 0
			for _, idx in ipairs(self:OpenStepsBefore(guide, start)) do
				if idx >= saved then openBetween = openBetween + 1 end
			end
			if openBetween == 0 then stepIndex, synced = start, { from = saved, open = open } end
		end
	end
	self.stepIndex = stepIndex or saved or 1
	if self.stepIndex < 1 then self.stepIndex = 1 end
	if self.stepIndex > #guide.steps then self.stepIndex = #guide.steps end
	self.db.char.progress[guide.name] = self.stepIndex
	if synced and self.stepIndex > 1 then
		Lodestar:Msg("Synced to step %d of %d from your quest log%s%s.", self.stepIndex, #guide.steps,
			synced.from and (" (was at " .. synced.from .. ")") or "",
			synced.open > 0 and (" — " .. synced.open .. " earlier step" .. (synced.open == 1 and "" or "s") .. " still open, press < to see them") or "")
	elseif self.db.profile.steps.announce then
		Lodestar:Msg("Guide: %s (step %d of %d)", guide.name, self.stepIndex, #guide.steps)
	end
	self:EvaluateStep(true)
	self:RefreshStepFrame()
	self:ArrowOnEvent("LODESTAR_STEP_CHANGED")
	return true
end

--- Leave guided mode; the window and arrow fall back to smart mode.
function Guide:UnloadGuide()
	self.current = nil
	self.stepIndex = nil
	self.stepFlags = {}
	self.finished = nil
	self.db.char.currentGuide = nil
	self:RefreshStepFrame()
	self:ArrowOnEvent("LODESTAR_STEP_CHANGED")
end

function Guide:CurrentStep()
	if not self.current or not self.stepIndex then return nil end
	return self.current.steps[self.stepIndex]
end

function Guide:SetStep(index, silent)
	if not self.current then return end
	index = math.max(1, math.min(#self.current.steps, index))
	if index == self.stepIndex then return end
	self.stepIndex = index
	self.finished = nil
	self.db.char.progress[self.current.name] = index
	if not silent and self.db.profile.steps.announce then
		Lodestar:Msg("Step %d: %s", index, self:StepText(self.current.steps[index]))
	end
	self:RefreshStepFrame()
	self:ArrowOnEvent("LODESTAR_STEP_CHANGED")
end

--- In smart mode, next/prev move the arrow through the list instead of through steps.
local function cycleSmart(delta)
	local items = Guide:CollectSmartItems(true)
	if #items == 0 then return end
	local pinnedItem = Guide:GetPinnedSmartItem() or Guide:SmartTarget()
	local at = 1
	for i, it in ipairs(items) do
		if pinnedItem and it.kind == pinnedItem.kind and it.questID == pinnedItem.questID and it.x == pinnedItem.x then at = i break end
	end
	local n = #items
	for _ = 1, n do
		at = ((at - 1 + delta) % n) + 1
		if items[at].mapID then break end
	end
	Guide:PinSmartItem(items[at])
end

function Guide:NextStep()
	if not self.current then cycleSmart(1) return end
	if self.stepIndex >= #self.current.steps then
		self:FinishGuide(true)
	else
		self.stepFlags[self.stepIndex] = { manual = true }
		self:SetStep(self.stepIndex + 1)
		self:EvaluateStep()
	end
end

function Guide:PrevStep()
	if not self.current then cycleSmart(-1) return end
	self.stepFlags[self.stepIndex - 1] = nil
	self:SetStep(self.stepIndex - 1)
end

--- The last step is done. Chain to the next guide when installed; otherwise stay on the last step
--- (marked finished) unless the player asked to move on, so choosing an old guide from the menu
--- doesn't silently bounce back to smart mode.
function Guide:FinishGuide(manual)
	local guide = self.current
	if not guide then return end
	self.db.char.progress[guide.name] = #guide.steps
	if guide.next and self.guideByName[guide.next] then
		Lodestar:Msg("Finished %s — loading %s.", guide.name, guide.next)
		self:LoadGuide(guide.next, 1)
	elseif manual then
		Lodestar:Msg("Finished %s. %s Switching to smart mode: the window now lists your nearest turn-ins, objectives and quest givers.",
			guide.name, guide.next and ("Next guide '" .. guide.next .. "' is not installed.") or "")
		self:UnloadGuide()
	else
		if not self.finished then
			Lodestar:Msg("%s is finished for this character.%s Click > for smart mode, or pick another guide from the right-click menu.",
				guide.name, guide.next and (" The next guide, '" .. guide.next .. "', is not installed.") or "")
		end
		self.finished = true
		self:RefreshStepFrame()
	end
end

-- Text -----------------------------------------------------------------------------------------------

local pendingQuestLoads = {}

local function questName(questID)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if title and title ~= "" then return title end
	if C_QuestLog.RequestLoadQuestByID and not pendingQuestLoads[questID] then
		pendingQuestLoads[questID] = true
		pcall(C_QuestLog.RequestLoadQuestByID, questID)
	end
	return "quest #" .. questID
end

local function objectiveText(questID, index)
	if not C_QuestLog.IsOnQuest(questID) then return nil end
	local objectives = C_QuestLog.GetQuestObjectives(questID)
	if not objectives then return nil end
	if index then
		local o = objectives[index]
		return o and o.text
	end
	local parts = {}
	for _, o in ipairs(objectives) do if o.text then tinsert(parts, o.text) end end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

local pendingItemLoads = {}

--- Item name, or nil until the client has the item data (a load is requested; ITEM_DATA_LOAD_RESULT refreshes).
local function itemName(itemID)
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if name and name ~= "" then return name end
	if C_Item.RequestLoadItemDataByID and not pendingItemLoads[itemID] then
		pendingItemLoads[itemID] = true
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return nil
end

function Guide:StepText(step)
	return Parser.StepText(step, questName, objectiveText, function(map) return self:MapName(map) end, itemName)
end

function Guide:ActionText(action)
	return Parser.ActionText(action, questName, objectiveText, itemName)
end

--- Lower-case names of the professions the character knows, or nil when the client cannot say.
local function knownProfessions()
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local known = {}
	local slots = { GetProfessions() }   -- prof1, prof2, archaeology, fishing, cooking, firstAid (nil = empty slot)
	for i = 1, 6 do
		local idx = slots[i]
		if idx then
			local name = GetProfessionInfo(idx)
			if type(name) == "string" then known[name:lower()] = true end
		end
	end
	return known
end

-- Completion -------------------------------------------------------------------------------------------

local function turnedIn(questID)
	if C_QuestLog.IsQuestFlaggedCompleted(questID) then return true end
	local t = recentTurnIn[questID]
	return t ~= nil and (GetTime() - t) < TURNIN_GRACE
end

local function accepted(questID)
	if C_QuestLog.IsOnQuest(questID) or turnedIn(questID) then return true end
	local t = recentAccept[questID]
	return t ~= nil and (GetTime() - t) < ACCEPT_GRACE
end

function Guide:IsActionComplete(action, flags)
	local t = action.type
	if t == "accept" then
		return accepted(action.questID)
	elseif t == "turnin" then
		return turnedIn(action.questID)
	elseif t == "complete" then
		if turnedIn(action.questID) then return true end
		if not C_QuestLog.IsOnQuest(action.questID) then return false end
		if action.objective then
			local objectives = C_QuestLog.GetQuestObjectives(action.questID)
			local o = objectives and objectives[action.objective]
			return o and o.finished or false
		end
		return C_QuestLog.IsComplete(action.questID) and true or false
	elseif t == "level" then
		return UnitLevel("player") >= action.level
	elseif t == "zone" then
		local z = action.zone:lower()
		return (GetRealZoneText() or ""):lower() == z or (GetSubZoneText() or ""):lower() == z
	elseif t == "hs" then
		if flags and flags.hs then return true end
		if action.name and GetBindLocation then
			local bind = GetBindLocation()
			return bind and bind:lower() == action.name:lower() or false
		end
		return false
	elseif t == "train" then
		return flags and flags.train or false
	elseif t == "fly" then
		return flags and flags.fly or false
	elseif t == "vendor" then
		return flags and flags.vendor or false
	elseif t == "repair" then
		return flags and (flags.repair or flags.vendor) or false
	elseif t == "buy" then
		if flags and flags.manual then return true end
		if not (C_Item and C_Item.GetItemCount) then return false end
		-- bags only (includeBank defaults false): .buy completes when you CARRY that many
		return (C_Item.GetItemCount(action.itemID) or 0) >= (action.count or 1)
	elseif t == "profession" then
		if flags and flags.manual then return true end
		local known = knownProfessions()
		if not known then return false end -- no profession API: click Next
		for _, name in ipairs(action.names or {}) do
			if not known[name:lower()] then return false end
		end
		return true
	else -- text, camp, cook
		return flags and flags.manual or false
	end
end

function Guide:IsStepComplete(step)
	local flags = self.stepFlags[step.index]
	if flags and flags.manual then return true end
	if step.arrival then
		-- Measured directly (not via the arrow, which may be pointing elsewhere), with hysteresis so a
		-- step doesn't flap at the edge of the radius, and never while on a flight path.
		if UnitOnTaxi and UnitOnTaxi("player") then return false end
		local mapID = self:ResolveMap(step.go.map)
		local dist = mapID and self:VectorTo(mapID, step.go.x / 100, step.go.y / 100)
		if not dist then return false end
		local radius = step.go.radius or self.db.profile.arrow.arrivalYards or 10
		flags = flags or {}
		self.stepFlags[step.index] = flags
		if flags.arrived then
			if dist > radius * 1.5 then flags.arrived = nil end
		elseif dist <= radius then
			flags.arrived = true
		end
		return flags.arrived == true
	end
	if #step.actions == 0 then return false end
	for _, action in ipairs(step.actions) do
		if not self:IsActionComplete(action, flags) then return false end
	end
	return true
end

--- A quest was abandoned: go back to the step that accepts it, if we are past it.
function Guide:OnQuestAbandoned(questID)
	if not self.current then return end
	for idx = self.stepIndex, 1, -1 do
		local step = self.current.steps[idx]
		for _, a in ipairs(step.actions) do
			if a.type == "accept" and a.questID == questID then
				if idx < self.stepIndex then
					for j = idx, self.stepIndex do self.stepFlags[j] = nil end
					Lodestar:Msg("Quest abandoned — back to step %d.", idx)
					self:SetStep(idx, true)
				end
				return
			end
		end
	end
end

--- Zygor-style "suggested starting point": the step after the last one whose quest actions are all
--- complete according to the client's completion flags. Returns startIndex, skipped.
function Guide:SuggestStartIndex(guide)
	local pf = self:PlayerFilters()
	local last = 0
	local openBefore = {}   -- [idx] = true for applicable quest steps that are not complete
	for idx, step in ipairs(guide.steps) do
		if self:StepApplies(step, pf) then
			local questActions, done, proof = 0, 0, false
			for _, a in ipairs(step.actions) do
				if a.questID then
					questActions = questActions + 1
					if self:IsActionComplete(a, nil) then
						done = done + 1
						-- A quest merely sitting in the log proves nothing about where the character is:
						-- players grab every quest at a hub, often long before the guide's step for it.
						-- Only a turn-in or a finished objective may move the suggested start forward.
						if a.type ~= "accept" or turnedIn(a.questID) then proof = true end
					end
				end
			end
			if questActions > 0 then
				if done < questActions then openBefore[idx] = true
				elseif proof then last = idx end
			end
		end
	end
	local start = math.min(last + 1, #guide.steps)
	local open = 0
	for idx in pairs(openBefore) do if idx < start then open = open + 1 end end
	return start, math.max(0, start - 1), open
end

--- Steps before `upto` whose quests are still open (for the window's "earlier steps" hint).
function Guide:OpenStepsBefore(guide, upto)
	local pf = self:PlayerFilters()
	local list = {}
	for idx = 1, math.min(upto - 1, #guide.steps) do
		local step = guide.steps[idx]
		if self:StepApplies(step, pf) then
			for _, a in ipairs(step.actions) do
				if a.questID and not self:IsActionComplete(a, nil) then tinsert(list, idx) break end
			end
		end
	end
	return list
end

--- Re-sync the current guide to the character's quest log. Returns the new step index.
function Guide:SyncToQuestLog(silent)
	if not self.current then return nil end
	local start, _, open = self:SuggestStartIndex(self.current)
	if not silent then
		if start == self.stepIndex then
			Lodestar:Say("Already in sync: step %d of %d.%s", start, #self.current.steps, open > 0 and (" " .. open .. " earlier step(s) still open.") or "")
		else
			Lodestar:Say("Synced: step %d → %d of %d.%s", self.stepIndex or 0, start, #self.current.steps, open > 0 and (" " .. open .. " earlier step(s) still open — press < to see them.") or "")
		end
	end
	self.stepFlags = {}
	self:SetStep(start, true)
	self:EvaluateStep()
	return start
end

--- Skip steps that don't apply or are already done, announcing only the step we land on.
--- `initial` (guide load) suppresses that announcement.
function Guide:EvaluateStep(initial)
	if not self.current or not self.stepIndex then return end
	-- Steps that do not apply to this character are skipped whatever `autoAdvance` says: the window
	-- already hides them. `autoAdvance` only governs completion-driven advancing.
	local advance = initial or self.db.profile.steps.autoAdvance
	local pf = self:PlayerFilters()
	local from = self.stepIndex
	local guard = 0
	while guard < 500 do
		guard = guard + 1
		local step = self.current.steps[self.stepIndex]
		if not step then return end
		if not stepApplies(step, pf) or (advance and self:IsStepComplete(step)) then
			if self.stepIndex >= #self.current.steps then
				self:FinishGuide()
				return
			end
			-- Walk silently: the steps in between are done or belong to another class or race, and
			-- announcing each one reads as instructions the player is meant to follow.
			self:SetStep(self.stepIndex + 1, true)
		else
			break
		end
	end
	if not initial and self.stepIndex ~= from and self.db.profile.steps.announce then
		Lodestar:Msg("Step %d: %s", self.stepIndex, self:StepText(self.current.steps[self.stepIndex]))
	end
	self:RefreshStepFrame()
end

function Guide:QueueEvaluate()
	if evalQueued then return end
	evalQueued = true
	self:ScheduleTimer(function() evalQueued = false self:EvaluateStep() end, 0.3)
end

local ENGINE_EVENTS = {
	QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true, QUEST_LOG_UPDATE = true, UNIT_QUEST_LOG_CHANGED = true,
	PLAYER_LEVEL_UP = true, ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true, PLAYER_ENTERING_WORLD = true, QUEST_DATA_LOAD_RESULT = true,
	BAG_UPDATE_DELAYED = true, SKILL_LINES_CHANGED = true,
}

--- A trainer window opened. Class trainers (anything that is not a tradeskill trainer — the client
--- only opens a class trainer for its own class) mark the character as trained at this level and
--- tag the harvested NPC with the class it teaches, so the suggestion can use it later.
function Guide:NoteTrainerVisit()
	if IsTradeskillTrainer and IsTradeskillTrainer() then
		self.classTrainerOpen = nil
		return
	end
	self.classTrainerOpen = true
	self.db.char.lastTrainedLevel = math.max(self.db.char.lastTrainedLevel or 0, UnitLevel("player") or 0)
	local npcID = Lodestar.NpcIDFromGUID(UnitGUID("npc"))
	local db = self.HarvestDB and self:HarvestDB()
	local e = npcID and db and db.npcs[npcID]
	if e then e.trains = Lodestar.player.class or select(2, UnitClass("player")) end
	trainerSuggestedAt = nil
end

function Guide:EngineOnEvent(event, ...)
	if event == "TRAINER_SHOW" then
		self:NoteTrainerVisit()
	elseif event == "TRAINER_CLOSED" then
		if self.classTrainerOpen then
			self.classTrainerOpen = nil
			self.db.char.lastTrainedLevel = math.max(self.db.char.lastTrainedLevel or 0, UnitLevel("player") or 0)
		end
		trainerSuggestedAt = nil
	elseif event == "PLAYER_LEVEL_UP" or event == "ZONE_CHANGED_NEW_AREA" then
		trainerSuggestedAt = nil
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		self:RefreshStepFrame()
	end
	if not self.current then return end
	local flags = self.stepFlags
	local i = self.stepIndex
	local function flag(key)
		flags[i] = flags[i] or {}
		flags[i][key] = true
	end
	if event == "QUEST_TURNED_IN" then
		local questID = ...
		if type(questID) == "number" then recentTurnIn[questID] = GetTime() end
	elseif event == "QUEST_ACCEPTED" then
		-- payload is (questID) on this client; be tolerant of an older (index, questID) shape
		local a, b = ...
		local questID = (type(b) == "number" and b > 0) and b or a
		if type(questID) == "number" then recentAccept[questID] = GetTime() end
	elseif event == "QUEST_REMOVED" then
		-- Also fires for turn-ins, and is not guaranteed to arrive after QUEST_TURNED_IN; decide a
		-- second later, once the turn-in event (or the lagging completed flag) has had a chance to land.
		local questID = ...
		if type(questID) == "number" then
			self:ScheduleTimer(function()
				if self.current and not turnedIn(questID) and not C_QuestLog.IsOnQuest(questID) then
					self:OnQuestAbandoned(questID)
				end
			end, 1)
		end
	elseif event == "HEARTHSTONE_BOUND" then
		flag("hs")
	elseif event == "TRAINER_CLOSED" then
		flag("train")
	elseif event == "TAXIMAP_OPENED" then
		self.taxiOpened = GetTime()
	elseif event == "PLAYER_CONTROL_LOST" then
		-- UnitOnTaxi can still be false at the instant of the event; check a moment later.
		local opened = self.taxiOpened
		self:ScheduleTimer(function()
			if (UnitOnTaxi and UnitOnTaxi("player")) or (opened and GetTime() - opened < 2) then
				flag("fly")
				self:QueueEvaluate()
			end
		end, 0.3)
	elseif event == "MERCHANT_SHOW" then
		flag("visitedVendor")
		if CanMerchantRepair and CanMerchantRepair() then flag("canRepair") end
	elseif event == "MERCHANT_CLOSED" then
		if flags[i] and flags[i].visitedVendor then
			flag("vendor")
			if flags[i].canRepair then flag("repair") end
		end
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		self:RefreshStepFrame()
	end
	if ENGINE_EVENTS[event] or event == "HEARTHSTONE_BOUND" or event == "TRAINER_CLOSED" or event == "MERCHANT_CLOSED" then
		self:QueueEvaluate()
	end
end

-- Class trainers ----------------------------------------------------------------------------------

local function playerClass()
	return Lodestar.player.class or select(2, UnitClass("player"))
end

--- The highest level at or below `level` at which the class gets new spells (nil when none yet).
local function spellLevelReached(classFile, level)
	local levels = Guide.SpellLevels and Guide.SpellLevels[classFile]
	if not levels then return nil end
	local best
	for l in pairs(levels) do
		if l <= level and (not best or l > best) then best = l end
	end
	return best
end

--- Nearest known trainer for the player's class within `range` yards: { npcID, name, mapID, x, y, dist }
--- or nil. Sources: NPCs this account has seen open a class trainer window (harvest, exact position)
--- and the built-in trainer list resolved through the Vanilla database.
function Guide:NearestClassTrainer(range)
	local classFile = playerClass()
	local ids = self.TrainerData and self.TrainerData[classFile]
	local idSet = {}
	for _, id in ipairs(ids or {}) do idSet[id] = true end
	local best
	local function consider(npcID, name, mapID, x, y, dist)
		if dist and (not range or dist <= range) and (not best or dist < best.dist) then
			best = { npcID = npcID, name = name, mapID = mapID, x = x, y = y, dist = dist }
		end
	end
	local db = self.HarvestDB and self:HarvestDB()
	for id, e in pairs(db and db.npcs or {}) do
		if e.kind and e.kind.trainer and e.map and e.x and e.y and (idSet[id] or e.trains == classFile) then
			consider(id, e.name, e.map, e.x / 100, e.y / 100, (self:VectorTo(e.map, e.x / 100, e.y / 100)))
		end
	end
	if ids and self.DataNearestNPC then
		local mapID, x, y, name, dist, npcID = self:DataNearestNPC(ids)
		if mapID then consider(npcID, name, mapID, x, y, dist) end
	end
	return best
end

--- "New spells available": the character has reached a level with new spells for the class, has
--- not visited a class trainer since, and a trainer is close. Recomputed at most every 5 s.
--- Returns { npcID, name, mapID, x, y, dist, level, title } or nil.
function Guide:TrainerSuggestion(force)
	local now = GetTime()
	if not force and trainerSuggestedAt and now - trainerSuggestedAt < TRAINER_RECHECK then return trainerSuggestion end
	trainerSuggestedAt = now
	trainerSuggestion = nil
	local due = spellLevelReached(playerClass(), UnitLevel("player") or 1)
	if not due or (self.db.char.lastTrainedLevel or 0) >= due then return nil end
	local t = self:NearestClassTrainer(TRAINER_RANGE)
	if not t then return nil end
	t.level = due
	t.title = "Train new spells at " .. (t.name or "your class trainer")
	trainerSuggestion = t
	return t
end

--- Smart-mode hook (called from CollectSmartItems): the trainer suggestion as a list item.
function Guide:TrainItems(items, mapID)
	local t = self:TrainerSuggestion()
	if not (t and t.mapID) then return end
	tinsert(items, { kind = "train", mapID = t.mapID, x = t.x, y = t.y, npcID = t.npcID, source = "trainer",
		title = t.title, subtitle = ("Level %d spells · class trainer"):format(t.level) })
end

-- Slash ----------------------------------------------------------------------------------------------

local function handleGuideSlash(rest)
	local verb, arg = strsplit(" ", strtrim(rest or ""), 2)
	verb = (verb or ""):lower()
	if verb == "" or verb == "toggle" then
		Guide.db.profile.steps.show = not Guide.db.profile.steps.show
		Guide:UpdateStepFrame()
	elseif verb == "list" then
		if #Guide.guides == 0 then Lodestar:Say("No guides installed.") return end
		local pf = Guide:PlayerFilters()
		for _, g in ipairs(Guide.guides) do
			local ok = guideApplies(g, pf, true)
			local progress = Guide.db.char.progress[g.name]
			Lodestar:Say("  %s%s|r — %d steps%s%s%s", ok and "|cffffffff" or "|cff888888", g.name, #g.steps,
				g.minLevel and (" · levels " .. g.minLevel .. "-" .. g.maxLevel) or "",
				progress and (" · at step " .. progress) or "",
				g.pack and (" · " .. g.pack) or "")
		end
	elseif verb == "load" then
		if not arg or arg == "" then Lodestar:Say("Usage: /lode guide load <guide name>") return end
		-- allow a case-insensitive prefix match
		local match
		for _, g in ipairs(Guide.guides) do
			if g.name:lower() == arg:lower() then match = g break end
			if not match and g.name:lower():find(arg:lower(), 1, true) then match = g end
		end
		if match then Guide:LoadGuide(match.name) else Lodestar:Say("No guide matches '%s'.", arg) end
	elseif verb == "next" then
		Guide:NextStep()
	elseif verb == "prev" or verb == "back" then
		Guide:PrevStep()
	elseif verb == "step" then
		local n = tonumber(arg)
		if n then Guide:SetStep(n) Guide:EvaluateStep() else Lodestar:Say("Usage: /lode guide step <number>") end
	elseif verb == "reset" then
		if Guide.current then Guide.db.char.progress[Guide.current.name] = 1 Guide:LoadGuide(Guide.current.name, 1) end
	elseif verb == "auto" then
		local g = Guide:PickGuide()
		if g then Guide:LoadGuide(g.name) else Lodestar:Say("No installed guide fits this character; using smart mode.") Guide:UnloadGuide() end
	elseif verb == "sync" then
		if Guide.current then Guide:SyncToQuestLog() else Lodestar:Say("No guide loaded — smart mode is already built from your quest log.") end
	elseif verb == "smart" or verb == "unload" then
		Guide:UnloadGuide()
		Lodestar:Say("Smart mode: nearest turn-ins, objectives and quest givers.")
	elseif verb == "nextup" or verb == "up" then
		Guide:PrintNextUp()
	elseif verb == "completionist" or verb == "optional" then
		local on
		if arg == "on" then on = true elseif arg == "off" then on = false else on = not Guide.db.profile.steps.completionist end
		Guide:SetCompletionist(on)
	elseif verb == "train" then
		local t = Guide:TrainerSuggestion(true)
		if t then
			Lodestar:Say("New level %d spells: %s is %d yd away.", t.level, t.name or ("NPC " .. tostring(t.npcID)), math.floor(t.dist))
		else
			Lodestar:Say("No class trainer suggestion right now (last trained at level %s).", tostring(Guide.db.char.lastTrainedLevel or "never"))
		end
	elseif verb == "diag" then
		Guide:Diagnose()
	else
		Lodestar:Say("Usage: /lode guide [list | load <name> | next | prev | step <n> | reset | sync | auto | smart | nextup | completionist | train | diag]")
	end
end

--- Completionist mode shows `.optional` steps (extra quests, professions, camp); speed-run mode skips them.
function Guide:SetCompletionist(on)
	self.db.profile.steps.completionist = on and true or false
	Lodestar:Msg("Guide: %s.", on and "completionist — optional quests and steps are shown" or "speed run — optional steps are skipped")
	self:EvaluateStep()
	self:RefreshStepFrame()
end

function Guide:EnableEngine()
	if not self.engineSlash then
		self.engineSlash = true
		Lodestar:RegisterSlashVerb("guide", handleGuideSlash, "guide window and guide commands: /lode guide list|load|next|prev|reset")
	end
	-- Restore or pick a guide once the world is ready.
	self:ScheduleTimer(function()
		if self.current then return end
		local saved = self.db.char.currentGuide
		local savedGuide = saved and self.guideByName[saved]
		-- Keep the character on its guide whatever its level: #levels is deliberately narrower than the
		-- route (the packs say so) and only steers PickGuide. Only a finished guide with no installed
		-- #next hands the character back to the auto-pick.
		local progress = savedGuide and self.db.char.progress[saved]
		local finished = savedGuide and progress and progress >= #savedGuide.steps
			and not (savedGuide.next and self.guideByName[savedGuide.next])
		if savedGuide and not finished then
			self:LoadGuide(saved)
		elseif self.db.profile.steps.autoPickGuide then
			local g = self:PickGuide()
			if g then self:LoadGuide(g.name) else self:RefreshStepFrame() end
		else
			self:RefreshStepFrame()
		end
	end, 3)
	arrivalTicker = self:ScheduleRepeatingTimer(function()
		local step = self:CurrentStep()
		if step and step.arrival then self:EvaluateStep() end
	end, 2)
end

function Guide:DisableEngine()
	if arrivalTicker then self:CancelTimer(arrivalTicker) arrivalTicker = nil end
	self.current = nil
	self.stepIndex = nil
end

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

-- Why the guide is where it is ------------------------------------------------------------------
--
-- Four rounds of this were debugged from saved files written BEFORE the fix being tested had loaded,
-- and from reading the code. That is how you get four fixes that each reproduce a real bug offline
-- and none of which is the one the player is hitting.
--
-- So the engine now writes down what it decided and what it decided it from, at the moment it
-- decides: which guides were considered and why each was rejected, what the character looked like to
-- the filters, what the saved progress said, what the quest log suggested, and which of those won.
-- `/lode guide why` prints the last one; it is mirrored into LodestarProbes.guideDecisions so it
-- also survives to disk on the next /reload and can be read without the player transcribing chat.
local MAX_DECISIONS = 8

function Guide:RecordDecision(kind, data)
	data.kind = kind
	data.at = date and date("%Y-%m-%d %H:%M:%S") or nil
	data.version = Lodestar.version
	self.decisions = self.decisions or {}
	tinsert(self.decisions, data)
	while #self.decisions > MAX_DECISIONS do tremove(self.decisions, 1) end
	if type(_G.LodestarProbes) ~= "table" then _G.LodestarProbes = {} end
	_G.LodestarProbes.guideDecisions = self.decisions
	return data
end

--- Player descriptors used for guide/step filters (all lower-case).
function Guide:PlayerFilters()
	local raceName, raceFile = UnitRace("player")
	return {
		-- Lodestar.player.faction is cached at login, which is right -- faction cannot change during
		-- a session -- but UnitFactionGroup can answer nil that early, and a nil here used to switch
		-- the faction filter off entirely rather than narrowing it. Ask the client again before
		-- giving up on knowing.
		faction = Lodestar.player.faction or (UnitFactionGroup and UnitFactionGroup("player")) or nil,
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

local PICK_LEVEL_GRACE = 2   -- levels: auto-pick will load a route starting this soon, no further

--- Choose the best guide for the character: most specific match covering the current level,
--- else the applicable guide with the lowest level range above the player, else anything applicable.
function Guide:PickGuide()
	local pf = self:PlayerFilters()
	local best, bestScore
	local considered = {}
	for _, g in ipairs(self.guides) do
		local outleveled = g.maxLevel and pf.level > g.maxLevel
		-- Fail closed on an unknown faction. Listing every guide when we cannot tell is friendly
		-- (ApplicableGuides still does), but LOADING one is not: the cost of guessing wrong is a
		-- character following a route on the other continent, which is worse than no route at all.
		local unknownFaction = not pf.faction and g.faction ~= "Both"
		if guideApplies(g, pf, true) and not outleveled and not unknownFaction then
			local covers = g.minLevel and g.maxLevel and pf.level >= g.minLevel and pf.level <= g.maxLevel
			local ahead = g.minLevel and g.minLevel > pf.level and (g.minLevel - pf.level) or 0
			local specificity = (g.races and 2 or 0) + (g.classes and 2 or 0) + (g.faction ~= "Both" and 1 or 0)
			local score
			if covers then
				score = 1000 + specificity
			elseif ahead > 0 then
				-- A route that starts a level or two ahead is worth loading; one that starts ten levels
				-- ahead is not. Forever's new races have no 1-12 route at all, so the only guides passing
				-- their race filter are the faction-wide 12-20 ones, and pointing a level 2 druid at a
				-- level 12 zone is worse than saying nothing. nil here means smart mode.
				score = ahead <= PICK_LEVEL_GRACE and (500 - ahead + specificity * 0.1) or nil
			else
				score = specificity
			end
			if score and (not bestScore or score > bestScore) then best, bestScore = g, score end
			considered[#considered + 1] = { name = g.name, score = score,
				why = score and "considered" or ("starts " .. ahead .. " levels ahead, past the " .. PICK_LEVEL_GRACE .. "-level grace") }
		else
			-- Name the filter that rejected it. "No route for your character" is not a diagnosis, and
			-- a race or faction string the guide spells differently from the client is invisible
			-- without this -- which is exactly the failure that leaves a levelling character in smart
			-- mode wondering why the route it can see in /lode guide list never loads.
			local why
			if g.faction ~= "Both" and pf.faction and g.faction ~= pf.faction then
				why = ("faction: guide is %s, character is %s"):format(tostring(g.faction), tostring(pf.faction))
			elseif g.classes and not (g.classes[pf.class] or g.classes[pf.className]) then
				why = ("class: character is %s/%s"):format(tostring(pf.class), tostring(pf.className))
			elseif g.races and not (g.races[pf.race] or g.races[pf.raceFile]) then
				why = ("race: character is %s/%s"):format(tostring(pf.race), tostring(pf.raceFile))
			elseif outleveled then
				why = ("outlevelled: guide tops out at %d, character is %d"):format(g.maxLevel or -1, pf.level or -1)
			elseif unknownFaction then
				why = "the client has not said which faction this character is yet"
			else
				why = "did not apply"
			end
			considered[#considered + 1] = { name = g.name, why = why }
		end
	end
	self:RecordDecision("pick", { player = pf, guides = considered, chose = best and best.name or nil, guideCount = #self.guides })
	return best
end

-- Loading ------------------------------------------------------------------------------------------

--- Run `fn` once the client can answer "has this quest been finished?" honestly.
---
--- For the first seconds after entering the world, C_QuestLog.IsQuestFlaggedCompleted answers FALSE
--- for every quest rather than "not yet known" -- the server's completed list has not landed. Any
--- code that reconciles against the quest log in that window concludes the character has done
--- nothing. Smart.lua's CompletedQuestsReady carries its own grace timer, so this always fires
--- eventually, including for a genuinely new character who really has finished nothing.
function Guide:WhenCompletedReady(fn)
	if not self.CompletedQuestsReady or self:CompletedQuestsReady() then return fn() end
	self:ScheduleTimer(function() self:WhenCompletedReady(fn) end, 1)
end

local function completedKnown(self)
	return not self.CompletedQuestsReady or self:CompletedQuestsReady()
end

function Guide:LoadGuide(name, stepIndex)
	local guide = name and self.guideByName[name]
	if not guide then
		if name then Lodestar:Say("No guide called %s.", tostring(name)) end
		return false
	end
	-- Whether the CALLER pinned a step. `stepIndex` is reassigned by the reconcile below, so asking
	-- "was one given?" afterwards always answers yes and any guard built on it never fires.
	local pinned = stepIndex ~= nil
	self.current = guide
	self.stepFlags = {}
	self.finished = nil
	self.db.char.currentGuide = guide.name
	local saved = self.db.char.progress[guide.name]
	local why = { guide = guide.name, steps = #guide.steps, saved = saved, pinned = pinned,
		player = self:PlayerFilters(), completedKnown = completedKnown(self) }
	-- Saved progress parked on the LAST step of a route this character never actually finished is
	-- the clamp at the bottom of this function, not a position. A start suggestion of 40 in a
	-- 36-step route gets clamped to 36 and written back as progress, and from then on the character
	-- is pinned to the end of the zone: the window shows the last turn-in forever, and the next
	-- login reads it as a finished guide and falls through to smart mode. Reconcile instead.
	if saved and saved >= #guide.steps and not (self.db.char.finished or {})[guide.name] then
		why.droppedSaved = "saved progress was the last step of a route this character never finished"
		saved = nil
	end
	local synced
	if not stepIndex then
		-- Distrust is reconsidered on every load, not latched for the session: a character that has
		-- since levelled past the contradiction gets its completed flags believed again. Otherwise a
		-- decision taken at level 6 would still be overriding the client at level 12.
		if not self:ImpossibleStart(guide, #guide.steps) then
			for _, s in ipairs(guide.steps) do
				for _, a in ipairs(s.actions) do
					if a.questID then self.distrusted[a.questID] = nil end
				end
			end
		end
		-- Sync to the character, not to the saved position: a character that is mid-way (or has played
		-- without the guide) lands on the step after the last one its completed quests account for.
		local start, _, open = self:SuggestStartIndex(guide)
		-- Saved progress is normally the player's real position and is never stepped backwards over.
		-- But a saved step that CANNOT be acted on is not a position, it is a dead end: it parks the
		-- window on "turn in X" for a quest with three of eight kills done and nothing will ever
		-- advance it, because the thing it waits for cannot happen from there. Reconcile instead.
		if saved and self:StepBlocked(guide.steps[saved]) then
			why.droppedSaved = "saved step cannot be acted on from where it stands"
			saved = nil
		end
		why.suggested, why.openBefore = start, open

		-- A suggestion the route's own level range says cannot be true. This is the overshoot that
		-- put a level 6 character on step 36 of 36: believed once, it is written back as progress and
		-- the character is pinned to the end of the zone from then on. Fall back to reconciling
		-- against the quest log, which reads what the character is actually carrying, and say so --
		-- an addon quietly disagreeing with the client about what you have done should not be silent.
		local impossible = self:ImpossibleStart(guide, start)
		if impossible then
			local proof = self.lastSuggestProof or {}
			why.impossibleStart = impossible
			why.proof = proof
			why.disagreement = self:CompletedDisagreement(proof)
			-- Stop believing the flag for these specific quests, then ask again from scratch. Without
			-- the second pass the suggestion here is still the poisoned one.
			for _, id in ipairs(proof) do self.distrusted[id] = true end
			start, _, open = self:SuggestStartIndex(guide)
			why.suggested = start
			Lodestar:Msg("|cffff9933The client says this character has already finished every quest in %s|r — %s. Ignoring that and working from your quest log; |cffffff7f/lode guide why|r has the detail.", guide.name, impossible)
		end
		local distrust = impossible ~= nil
		if not saved then
			-- No saved progress: this character has never run this guide, so it may be half way
			-- through the zone already. Resume from what it actually holds rather than from step 1.
			local resumed, actionable = self:ReconcileToLog(guide)
			-- Reconciliation reads the quest LOG, which is a separate source from the completed
			-- flags, so it is worth doing even when the flags are not to be trusted -- a character
			-- part way through the zone is still holding real quests and lands on the right step.
			-- But when it finds nothing actionable it falls back to "one past the last thing that
			-- looks finished", and that is the poisoned number again. Start at the beginning rather
			-- than at the end of a route this character demonstrably has not run.
			if distrust and not (actionable and #actionable > 0) then
				why.distrustFallback = "nothing in the quest log to reconcile against either"
				resumed = 1
			end
			stepIndex, synced = resumed or start or 1, { open = open, reconciled = actionable and #actionable or nil }
		elseif start and start > saved then
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
	why.wanted = self.stepIndex
	if self.stepIndex < 1 then self.stepIndex = 1 end
	if self.stepIndex > #guide.steps then
		-- Worth writing down rather than quietly correcting: the only way to land here is a start
		-- suggestion that ran off the end of the route, and that is a bug in the suggestion.
		why.clamped = true
		self.stepIndex = #guide.steps
	end
	why.chose = self.stepIndex
	why.vault = self.vaultSeed
	self:RecordDecision("load", why)
	self:SaveProgress(guide.name, self.stepIndex)
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

	-- On this client saved progress never comes back, so every login reconciles from scratch -- and
	-- the login is exactly when the completed list is missing. A reconcile done in that window puts
	-- the character back near the start of the zone and sends them at quests they finished hours
	-- ago. Redo it once the client can answer; the second pass announces where it landed, so the
	-- correction is visible rather than a window that silently changes under you.
	if not pinned and not completedKnown(self) then
		local token = (self.reconcileToken or 0) + 1
		self.reconcileToken = token
		self:WhenCompletedReady(function()
			if self.reconcileToken ~= token or self.current ~= guide then return end
			self.db.char.progress[guide.name] = nil
			self:LoadGuide(guide.name)
		end)
	end
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

--- Record how far through a route this character is, in both places.
---
--- The saved variable is the real home and will work again the day the client hands them back. The
--- vault is what actually survives today, and it holds one route and one number -- the guide you
--- are on and the step you are at -- because that is the pair whose loss is noticeable on every
--- single login.
function Guide:SaveProgress(name, index)
	self.db.char.progress[name] = index
	self.db.char.currentGuide = name
	if Lodestar.VaultSet then
		Lodestar:VaultSet("g", name)
		Lodestar:VaultSet("gs", tostring(index))
	end
end

function Guide:SetStep(index, silent)
	if not self.current then return end
	index = math.max(1, math.min(#self.current.steps, index))
	if index == self.stepIndex then return end
	self.stepIndex = index
	self.finished = nil
	self:SaveProgress(self.current.name, index)
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
	-- The record of "this character finished this route". Reaching the last step is not enough on
	-- its own: LoadGuide clamps an over-eager start suggestion to the last step too, and that used
	-- to be indistinguishable from this.
	self.db.char.finished = self.db.char.finished or {}
	self.db.char.finished[guide.name] = true
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

--- Quests whose "already completed" flag this session has positive evidence against.
---
--- Populated only by ImpossibleStart below, and only for the quests of a route the character
--- demonstrably has not run. It is not a hunch about the client: it is the route's own level range
--- contradicting the flag, for a specific list of quest IDs.
---
--- It has to live here, at the source, rather than as a guard on the start index. Starting at step 1
--- is not enough on its own -- EvaluateStep then walks straight back to the end, because every step
--- it looks at still reads as complete. One switch, applied where the question is asked, keeps the
--- start index, the reconcile, the step evaluator, the window and smart mode all saying the same
--- thing. Turn-ins recorded this session still count: those were watched happening.
Guide.distrusted = {}

local function turnedIn(questID)
	if C_QuestLog.IsQuestFlaggedCompleted(questID) and not Guide.distrusted[questID] then return true end
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
--- A suggested start the route's own metadata says is impossible, or nil when it is credible.
---
--- A route declares the levels it covers. "#levels 1-12" is a claim that a character who works
--- through it comes out the other end at 12 -- that is what the route is FOR. So a character who is
--- level 6 cannot have finished it, whatever the client says about which quests are flagged
--- complete, and a suggestion that lands them on the last step is not a reading of their progress,
--- it is bad data.
---
--- This matters because the failure is silent and self-reinforcing: the suggestion is written back
--- as progress, the window parks on the final turn-in, and nothing about it looks like an error.
--- Two levels of slack, because a player who kills nothing and only quests can finish a zone a
--- little under its nominal level, and because being wrong in this direction costs a real resume.
local LEVEL_SLACK = 2

function Guide:ImpossibleStart(guide, start)
	if not (guide.maxLevel and start and start >= #guide.steps) then return nil end
	local level = UnitLevel("player")
	if type(level) ~= "number" or level >= guide.maxLevel - LEVEL_SLACK then return nil end
	return ("the quest data says this character finished every quest in a %d-%d route, but it is level %d")
		:format(guide.minLevel or 1, guide.maxLevel, level)
end

--- What the client's two answers to "has this been finished?" say, when they disagree.
---
--- IsQuestFlaggedCompleted is what every completion check in the suite is built on.
--- GetAllCompletedQuestIDs is the same information as a list. They should never differ; if they do
--- on this build, that is worth knowing precisely rather than inferring from behaviour, so the
--- disagreement is recorded rather than silently resolved -- picking a winner before knowing which
--- one is right is how the last four rounds of this went.
function Guide:CompletedDisagreement(questIDs)
	if not C_QuestLog.GetAllCompletedQuestIDs then return nil end
	local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
	if not (ok and type(list) == "table") then return nil end
	local inList = {}
	for _, id in ipairs(list) do inList[id] = true end
	local only = {}
	for _, id in ipairs(questIDs) do
		if not inList[id] then only[#only + 1] = id end
	end
	if #only == 0 then return nil end
	return { flaggedButNotListed = only, listSize = #list }
end

function Guide:SuggestStartIndex(guide)
	local pf = self:PlayerFilters()
	local last = 0
	local openBefore = {}   -- [idx] = true for applicable quest steps that are not complete
	local proofIDs = {}     -- the quests whose completion moved the suggestion forward
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
						if a.type ~= "accept" or turnedIn(a.questID) then
							proof = true
							proofIDs[#proofIDs + 1] = a.questID
						end
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
	self.lastSuggestProof = proofIDs
	return start, math.max(0, start - 1), open
end

--- Reconcile a route against what this character actually holds, for someone who installs the addon
--- half way through a character rather than at level 1. Walking in from step 1 is wrong (they have
--- done most of it) and so is jumping past the last thing they finished (the route's order is not
--- the order they played it, and quests they are still carrying would be stranded behind them).
---
--- Returns startIndex, actionable ({ idx, held }), done (set), lastProof.
--- True when a step is a dead end: it wants a quest handed in that the character is CARRYING and
--- has not finished. Nothing that happens while standing there can advance it, and the step that
--- would finish the quest is somewhere else entirely.
---
--- Deliberately narrow. A turn-in already handed in is fine -- the step is still live because of
--- something else on it, usually the next quest the same NPC gives out. A quest sitting complete in
--- the log is fine, that is exactly what the step is for. And a quest that is not in the log at all
--- is NOT a dead end: the player skipped it on purpose, and dragging them back to a quest they
--- chose not to take is its own bug. Only "carrying it, not finished" is a wall.
function Guide:StepBlocked(step)
	if not (step and step.actions) then return false end
	for _, a in ipairs(step.actions) do
		if a.type == "turnin" and a.questID
			and C_QuestLog.IsOnQuest(a.questID)
			and not C_QuestLog.IsComplete(a.questID)
			and not self:IsActionComplete(a, nil) then
			return true
		end
	end
	return false
end

function Guide:ReconcileToLog(guide)
	local pf = self:PlayerFilters()
	local actionable, done = {}, {}
	local lastProof = 0
	for idx, step in ipairs(guide.steps) do
		if self:StepApplies(step, pf) then
			local quests, complete, held, proof = 0, 0, false, false
			for _, a in ipairs(step.actions) do
				if a.questID then
					quests = quests + 1
					if C_QuestLog.IsOnQuest(a.questID) then held = true end
					if self:IsActionComplete(a, nil) then
						complete = complete + 1
						if a.type ~= "accept" or turnedIn(a.questID) then proof = true end
					end
				end
			end
			if quests > 0 then
				if complete >= quests then
					done[idx] = true
					if proof then lastProof = idx end
				else
					actionable[#actionable + 1] = { idx = idx, held = held }
				end
			end
		end
	end
	-- Resume where the character can actually pick the thread up: a step they can act on beats one
	-- they cannot, a quest already in the log beats one they have not started, then whichever is
	-- physically closest, then route order.
	--
	-- "Can act on" is what the distance sort gets wrong on its own. The step that kills the mobs and
	-- the step that hands the quest back name the same quest, so both look held -- and the turn-in
	-- is usually the nearer of the two, because the giver stands in the village and the objective is
	-- out in the field. Ranking on distance alone therefore resumes onto "turn in The Mindless Ones"
	-- with three of eight zombies dead. A turn-in for a quest that is not finished is not a place
	-- you can pick anything up: standing on it does nothing at all.
	local best, bestRank
	for _, c in ipairs(actionable) do
		local step = guide.steps[c.idx]
		local dist
		if step.go then
			local map = self:ResolveMap(step.go.map)
			if map and self.VectorTo then dist = self:VectorTo(map, step.go.x / 100, step.go.y / 100) end
		end
		local rank = (self:StepBlocked(step) and 1e8 or 0) + (c.held and 0 or 1e7) + (dist or 5e6) + c.idx * 0.001
		if not bestRank or rank < bestRank then best, bestRank = c.idx, rank end
	end
	return best or math.min(lastProof + 1, #guide.steps), actionable, done, lastProof
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
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- The completed-quest list has not arrived yet; until it does, "you can pick this up" is not
		-- a question the client can answer honestly (Smart.lua: CompletedQuestsReady).
		if self.ResetCompletedReady then self:ResetCompletedReady() end
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

--- Nearest harvested tradeskill trainer within `range` yards: { npcID, name, mapID, x, y, dist } or
--- nil. Unlike class trainers there is no built-in list to fall back on -- Data/Trainers.lua covers
--- classes only -- so this is whatever this account has actually walked past and opened.
function Guide:NearestTradeskillTrainer(range)
	local best
	local db = self.HarvestDB and self:HarvestDB()
	for id, e in pairs(db and db.npcs or {}) do
		if e.kind and e.kind.tradeskill and e.map and e.x and e.y then
			local dist = self:VectorTo(e.map, e.x / 100, e.y / 100)
			if dist and (not range or dist <= range) and (not best or dist < best.dist) then
				best = { npcID = id, name = e.name, mapID = e.map, x = e.x / 100, y = e.y / 100, dist = dist }
			end
		end
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
		if Guide.current then
			local name = Guide.current.name
			Guide.db.char.progress[name] = 1
			if Guide.db.char.finished then Guide.db.char.finished[name] = nil end
			Guide:LoadGuide(name, 1)
		end
	elseif verb == "auto" then
		local g = Guide:PickGuide()
		if g then Guide:LoadGuide(g.name) else Lodestar:Say("No installed guide fits this character; using smart mode.") Guide:UnloadGuide() end
	elseif verb == "why" then
		Guide:PrintWhy()
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

--- `/lode guide why`: the last routing decisions, in the order they were made.
---
--- This is the answer to "it's on the wrong quest" that does not require guessing. It says which
--- guide was chosen and which were rejected and by which filter, what the saved progress was and
--- whether it was believed, what the quest log suggested, and whether the completed-quest list had
--- arrived when any of that was decided -- which is the single most common reason for a wrong answer
--- at login, because for the first seconds the client says "not completed" about everything.
function Guide:PrintWhy()
	local list = self.decisions
	if not (list and #list > 0) then
		Lodestar:Say("No routing decisions recorded yet. They are written when a guide is picked or loaded.")
		return
	end
	for _, d in ipairs(list) do
		if d.kind == "pick" then
			local p = d.player or {}
			Lodestar:Say("|cffffff7fpick|r %s — level %s %s (%s), %s; %d guide%s installed",
				d.at or "?", tostring(p.level), tostring(p.race ~= "" and p.race or p.raceFile),
				tostring(p.class), tostring(p.faction or "faction unknown"), d.guideCount or 0, (d.guideCount == 1) and "" or "s")
			for _, g in ipairs(d.guides or {}) do
				Lodestar:Say("    %s%s|r — %s", g.score and "|cff7fff7f" or "|cff999999", g.name, g.why or "?")
			end
			Lodestar:Say("    chose: %s", d.chose or "|cffff9933nothing — smart mode|r")
		elseif d.kind == "load" then
			Lodestar:Say("|cffffff7fload|r %s — %s (%d steps)", d.at or "?", d.guide or "?", d.steps or 0)
			Lodestar:Say("    saved progress: %s%s", d.saved and tostring(d.saved) or "none",
				d.droppedSaved and (" |cffff9933(ignored: " .. d.droppedSaved .. ")|r") or "")
			Lodestar:Say("    quest log suggested: %s%s", d.suggested and tostring(d.suggested) or "n/a",
				d.openBefore and d.openBefore > 0 and (", " .. d.openBefore .. " earlier step(s) still open") or "")
			Lodestar:Say("    started at %s%s%s", tostring(d.chose),
				d.clamped and (" |cffff5555(clamped from " .. tostring(d.wanted) .. " — the suggestion ran off the end)|r") or "",
				d.pinned and " (pinned by the caller)" or "")
			if d.impossibleStart then
				Lodestar:Say("    |cffff5555ignored the quest data's suggestion|r: %s", d.impossibleStart)
				if d.proof and #d.proof > 0 then
					local ids = {}
					for i, id in ipairs(d.proof) do if i > 12 then break end ids[i] = tostring(id) end
					Lodestar:Say("      reported as turned in: %s%s", table.concat(ids, ", "), #d.proof > 12 and (" and " .. (#d.proof - 12) .. " more") or "")
				end
				if d.disagreement then
					Lodestar:Say("      |cffff5555and the client contradicts itself|r: %d of those are flagged complete but missing from GetAllCompletedQuestIDs (%d entries)",
						#d.disagreement.flaggedButNotListed, d.disagreement.listSize)
				end
			end
			if not d.completedKnown then
				Lodestar:Say("    |cffff9933the completed-quest list had not arrived yet — this was re-done once it did|r")
			end
		end
	end
	Lodestar:Say("Also saved to LodestarProbes.guideDecisions (written to disk on /reload or logout).")
end

function Guide:EnableEngine()
	if not self.engineSlash then
		self.engineSlash = true
		Lodestar:RegisterSlashVerb("guide", handleGuideSlash, "guide window and guide commands: /lode guide list|load|next|prev|reset|why")
	end
	-- Restore or pick a guide once the world is ready.
	self:ScheduleTimer(function()
		if self.current then return end
		-- On this client the saved variables come back empty every login, so without this the
		-- character is re-derived from scratch each time and any correction the player made by hand
		-- is lost with it. The vault goes through the client's own config, which does survive.
		if not self.db.char.currentGuide and Lodestar.VaultGet then
			local name = Lodestar:VaultGet("g")
			local step = tonumber(Lodestar:VaultGet("gs") or "")
			if name and self.guideByName[name] then
				self.db.char.currentGuide = name
				if step then self.db.char.progress[name] = step end
				self.vaultSeed = ("restored %s at step %s from the client config"):format(name, tostring(step))
			end
		end
		local saved = self.db.char.currentGuide
		local savedGuide = saved and self.guideByName[saved]
		-- Keep the character on its guide whatever its level: #levels is deliberately narrower than the
		-- route (the packs say so) and only steers PickGuide. Only a finished guide with no installed
		-- #next hands the character back to the auto-pick.
		local finished = savedGuide and (self.db.char.finished or {})[saved]
			and not (savedGuide.next and self.guideByName[savedGuide.next])
		if savedGuide and not finished then
			self:LoadGuide(saved)
		elseif self.db.profile.steps.autoPickGuide then
			local g = self:PickGuide()
			if g then
				self:LoadGuide(g.name)
			else
				-- Say so rather than showing an empty window: on Forever this is the normal state for a
				-- new race in its starting zone, and it is not a fault the player should have to guess at.
				local raceName = UnitRace("player")
				Lodestar:Msg("No route for a level %d %s yet — using smart mode, which builds the list from your quest log and the map. Everything you do here is recorded, and that is what the route gets built from.",
					UnitLevel("player") or 0, tostring(raceName or "character"))
				self:RefreshStepFrame()
			end
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

-- Lodestar_Leveling: XP/hour, time-to-level, session stats, and the XP waiting in completed quests
-- ("turn-ins to ding"). The status strip (StatusStrip.lua) renders as the frame's second line.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local FormatNumberShort, FormatDuration = Lodestar.FormatNumberShort, Lodestar.FormatDuration

local LINE_HEIGHT = 22          -- one-line frame height
local STRIP_HEIGHT = 14         -- extra height for the strip line (same small font as the XP line)
local TURNIN_DELAY = 1          -- QUEST_LOG_UPDATE bursts collapse into one scan per second
local SEP = "  |cff666666·|r  "

local session -- see ResetXPSession
local samples = {} -- { t = GetTime(), xp = gained } for the rolling window
local frame
local turnIns = { xp = 0, count = 0, sig = nil } -- reward XP of quests ready to turn in, refreshed on QUEST_LOG_UPDATE
local turnInTimer

--- Mirrors GameRulesUtil.GetEffectiveMaxLevelForPlayer: the expansion cap clamped by the realm/phase cap
--- (GetMaxPlayerLevel), which is how a capped beta or a Classic-style pre-patch reports its max level.
local function maxLevel()
	if GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer then
		local ok, v = pcall(GameRulesUtil.GetEffectiveMaxLevelForPlayer)
		if ok and type(v) == "number" then return v end
	end
	local expansionMax = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	local realmMax = GetMaxPlayerLevel and GetMaxPlayerLevel() or expansionMax
	return math.min(expansionMax, realmMax)
end

--- True when the client would not show an XP bar at all (XP turned off, or the game mode disables it).
local function xpDisabled()
	if IsXPUserDisabled and IsXPUserDisabled() then return true end
	local rules = Enum and Enum.GameRule
	local rule = rules and rules.ExperienceBarDisabled
	if rule and C_GameRules and C_GameRules.IsGameRuleActive and C_GameRules.IsGameRuleActive(rule) then return true end
	return false
end

--- `level` is the PLAYER_LEVEL_UP payload: the unit fields may not be updated yet when that event fires.
local function atMaxLevel(level)
	if xpDisabled() then return true end
	if type(level) ~= "number" then level = UnitLevel("player") end
	return level >= maxLevel()
end

function Leveling:ResetXPSession()
	session = {
		start = GetTime(),
		xp = 0,
		quests = 0,
		questXP = 0,
		kills = 0,
		killXP = 0,
		levels = 0,
		lastXP = UnitXP("player"),
		lastMax = UnitXPMax("player"),
		level = UnitLevel("player"),
	}
	wipe(samples)
	self:RefreshXPText()
end

-- Rates ---------------------------------------------------------------------------

local function pruneSamples(windowSeconds)
	local cutoff = GetTime() - windowSeconds
	while samples[1] and samples[1].t < cutoff do
		tremove(samples, 1)
	end
end

--- Returns xpPerHour (rolling), xpPerHour (session), secondsToLevel or nil.
function Leveling:GetXPRates()
	if not session then return 0, 0, nil end
	local now = GetTime()
	local elapsed = math.max(1, now - session.start)
	local windowSeconds = (self.db.profile.xp.windowMinutes or 30) * 60
	pruneSamples(windowSeconds)
	local windowXP = 0
	for _, s in ipairs(samples) do windowXP = windowXP + s.xp end
	local windowSpan = math.min(elapsed, windowSeconds)
	local rolling = windowXP / windowSpan * 3600
	local average = session.xp / elapsed * 3600
	local rate = rolling > 0 and rolling or average
	local remaining = UnitXPMax("player") - UnitXP("player")
	local ttl = rate > 0 and (remaining / rate * 3600) or nil
	return rolling, average, ttl
end

-- Turn-ins to ding -------------------------------------------------------------------

--- Sum the reward XP of every quest in the log that is ready to turn in. GetQuestLogRewardXP is an
--- undocumented global on this client that reads the selected quest (Blizzard's QuestInfo pattern),
--- so each quest is selected in turn and the previous selection put back afterwards; the questID is
--- also passed for clients whose version takes it directly.
---
--- The reward XP is only re-read when the set of ready quests (or the player's level, which scales
--- quest XP in Classic rules) changes: selecting quests is not free, and if SetSelectedQuest itself
--- raised QUEST_LOG_UPDATE an unconditional rescan would feed back into itself every second.
--- Returns total, count, signature.
local function scanTurnIns(force)
	local ql = C_QuestLog
	if not (ql and ql.GetNumQuestLogEntries and ql.GetInfo) then return 0, 0, nil end
	local ready = ql.ReadyForTurnIn or ql.IsComplete
	local rewardXP = _G.GetQuestLogRewardXP
	if not ready or type(rewardXP) ~= "function" then return 0, 0, nil end
	local ids = {}
	for i = 1, ql.GetNumQuestLogEntries() or 0 do
		local info = ql.GetInfo(i)
		local questID = info and not info.isHeader and info.questID
		if questID and ready(questID) then tinsert(ids, questID) end
	end
	table.sort(ids)
	local sig = tostring(UnitLevel("player")) .. ":" .. table.concat(ids, ",")
	if not force and sig == turnIns.sig then return turnIns.xp, turnIns.count, sig end
	local total = 0
	local previous = ql.GetSelectedQuest and ql.GetSelectedQuest()
	for _, questID in ipairs(ids) do
		if ql.SetSelectedQuest then ql.SetSelectedQuest(questID) end
		local xp = rewardXP(questID)
		if type(xp) == "number" and xp > 0 then total = total + xp end
	end
	if #ids > 0 and ql.SetSelectedQuest and type(previous) == "number" then pcall(ql.SetSelectedQuest, previous) end
	return total, #ids, sig
end

--- Cached result of the last scan: total reward XP, number of quests ready to turn in.
function Leveling:GetTurnInXP()
	return turnIns.xp, turnIns.count
end

function Leveling:RefreshTurnIns(force)
	local ok, xp, count, sig = pcall(scanTurnIns, force)
	if ok then
		turnIns.xp, turnIns.count, turnIns.sig = xp, count, sig
	else
		Lodestar:Debug("turn-in scan: %s", tostring(xp))
	end
	self:RefreshXPText()
end

function Leveling:QUEST_LOG_UPDATE()
	if turnInTimer then return end
	turnInTimer = self:ScheduleTimer(function()
		turnInTimer = nil
		self:RefreshTurnIns()
	end, TURNIN_DELAY)
end

--- "1,240 xp (ding!)" when the ready quests cover the rest of the level, else "1,240 xp (31% of level)".
--- nil when nothing is ready.
function Leveling:TurnInText()
	local xp, count = turnIns.xp, turnIns.count
	if count == 0 then return nil end
	local cur, xpMax = UnitXP("player"), UnitXPMax("player")
	if xpMax > 0 and xp >= xpMax - cur then
		return ("|cffffffff%s|r xp |cffffff00(ding!)|r"):format(BreakUpLargeNumbers(xp))
	end
	return ("|cffffffff%s|r xp (%.0f%% of level)"):format(BreakUpLargeNumbers(xp), xpMax > 0 and xp / xpMax * 100 or 0)
end

-- Events --------------------------------------------------------------------------

function Leveling:PLAYER_XP_UPDATE(_, unit)
	if unit ~= "player" or not session then return end
	local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	local gained, leveled
	if level > session.level then
		gained = (session.lastMax - session.lastXP) + xp -- lastMax is still the previous level's max here
		session.levels = session.levels + (level - session.level)
		session.level = level
		leveled = true
	else
		gained = xp - session.lastXP
	end
	session.lastXP, session.lastMax = xp, xpMax
	if gained > 0 then
		session.xp = session.xp + gained
		tinsert(samples, { t = GetTime(), xp = gained })
		if self.pendingQuestXP and self.pendingQuestXP > 0 then
			session.questXP = session.questXP + math.min(gained, self.pendingQuestXP)
			self.pendingQuestXP = nil
		else
			session.kills = session.kills + 1
			session.killXP = session.killXP + gained
		end
	end
	if leveled then
		self:UpdateXPFrame() -- the unit fields are fresh now: re-check the level cap
	else
		self:RefreshXPText()
	end
end

function Leveling:QUEST_TURNED_IN(_, _, xpReward)
	if not session then return end
	session.quests = session.quests + 1
	if type(xpReward) == "number" and xpReward > 0 then
		self.pendingQuestXP = xpReward
	end
end

--- PLAYER_LEVEL_UP: only the payload level is trustworthy here. session.lastMax is deliberately left
--- alone so the following PLAYER_XP_UPDATE can compute the carry-over from the previous level's max.
function Leveling:OnLevelUpXP(level)
	self:UpdateXPFrame(level)
	self:QUEST_LOG_UPDATE() -- quest XP scales with level under Classic rules: re-read it
end

-- Frame ---------------------------------------------------------------------------

local function savePosition()
	local db = Leveling.db.profile.xp
	local point, _, _, x, y = frame:GetPoint(1)
	db.pos = { point = point or "TOP", x = x or 0, y = y or 0 }
end

local function fillTooltip(tooltip)
	local rolling, average, ttl = Leveling:GetXPRates()
	local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	local elapsed = session and (GetTime() - session.start) or 0
	tooltip:AddLine(Lodestar.COLOR .. "Lodestar|r XP tracker")
	tooltip:AddDoubleLine("Level " .. level, ("%s / %s (%.1f%%)"):format(BreakUpLargeNumbers(xp), BreakUpLargeNumbers(xpMax), xpMax > 0 and xp / xpMax * 100 or 0), 1, 1, 1, 1, 1, 1)
	local rested = GetXPExhaustion()
	if rested and rested > 0 then
		tooltip:AddDoubleLine("Rested", ("%s (%.0f%%)"):format(BreakUpLargeNumbers(rested), xpMax > 0 and rested / xpMax * 100 or 0), 1, 1, 1, 0.4, 0.6, 1)
	end
	local turnInText = Leveling:TurnInText()
	local _, turnInCount = Leveling:GetTurnInXP()
	tooltip:AddDoubleLine(("Ready to turn in (%d)"):format(turnInCount), turnInText or "—", 1, 1, 1, 1, 1, 1)
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("XP/hour (last " .. (Leveling.db.profile.xp.windowMinutes) .. "m)", FormatNumberShort(rolling), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("XP/hour (session)", FormatNumberShort(average), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Time to level", ttl and FormatDuration(ttl) or "—", 1, 1, 1, 1, 1, 1)
	tooltip:AddLine(" ")
	Leveling:AddStripTooltipLines(tooltip)
	if session then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine("Session", FormatDuration(elapsed), 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine("XP gained", BreakUpLargeNumbers(session.xp), 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine("From quests", ("%s (%d)"):format(BreakUpLargeNumbers(session.questXP), session.quests), 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine("From kills", ("%s (%d)"):format(BreakUpLargeNumbers(session.killXP), session.kills), 1, 1, 1, 1, 1, 1)
		if session.levels > 0 then
			tooltip:AddDoubleLine("Levels gained", session.levels, 1, 1, 1, 1, 1, 1)
		end
	end
	tooltip:AddLine(" ")
	tooltip:AddLine("|cffaaaaaaDrag to move when unlocked · Right-click: settings · /lode xp reset|r")
end

local function createFrame()
	frame = CreateFrame("Frame", "LodestarXPFrame", UIParent, "BackdropTemplate")
	frame:SetSize(230, 22)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.text:SetPoint("CENTER")
	frame.text:SetJustifyH("CENTER")

	-- Second line: the status strip, same font, hidden unless the option is on.
	frame.strip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.strip:SetPoint("TOP", frame.text, "BOTTOM", 0, -2)
	frame.strip:SetJustifyH("CENTER")
	frame.strip:Hide()

	frame:SetScript("OnDragStart", function(self)
		if not Leveling.db.profile.xp.locked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Lodestar:OpenConfig("Leveling") end
	end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		fillTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Lay the XP line out for one or two lines: centred alone, or pushed to the top with the strip below.
local function layoutFrame(showStrip)
	frame.text:ClearAllPoints()
	if showStrip then
		frame.text:SetPoint("TOP", frame, "TOP", 0, -5)
		frame.strip:Show()
		frame:SetHeight(LINE_HEIGHT + STRIP_HEIGHT)
	else
		frame.text:SetPoint("CENTER")
		frame.strip:Hide()
		frame:SetHeight(LINE_HEIGHT)
	end
end

function Leveling:RefreshXPText()
	if not frame or not frame:IsShown() then return end
	local rolling, average, ttl = self:GetXPRates()
	local rate = rolling > 0 and rolling or average
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	local pct = xpMax > 0 and xp / xpMax * 100 or 0
	local parts = {
		("|cffffffff%s|r xp/h"):format(FormatNumberShort(rate)),
		ttl and ("|cffffffff%s|r to %d"):format(FormatDuration(ttl), UnitLevel("player") + 1) or ("%.0f%%"):format(pct),
	}
	if self.db.profile.xp.showRested then
		local rested = GetXPExhaustion()
		if rested and rested > 0 then
			tinsert(parts, ("|cff6b9eff%s|r rested"):format(FormatNumberShort(rested)))
		end
	end
	if self.db.profile.xp.showTurnIns then
		local turnIn = self:TurnInText()
		if turnIn then tinsert(parts, "turn-ins: " .. turnIn) end
	end
	frame.text:SetText(table.concat(parts, SEP))
	local width = frame.text:GetStringWidth()
	if frame.strip:IsShown() then
		frame.strip:SetText(self:BuildStripText())
		width = math.max(width, frame.strip:GetStringWidth())
	end
	frame:SetWidth(math.max(120, width + 24))
end

--- `level` is optional (PLAYER_LEVEL_UP payload); otherwise the unit's current level is used.
function Leveling:UpdateXPFrame(level)
	if not frame then return end
	local db = self.db.profile.xp
	if not self:IsEnabled() or not db.show or atMaxLevel(level) then
		frame:Hide()
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(db.pos.point or "TOP", UIParent, db.pos.point or "TOP", db.pos.x or 0, db.pos.y or -120)
	frame:SetScale(db.scale or 1)
	frame:EnableMouse(true)
	frame:SetBackdropBorderColor(db.locked and 0.4 or 0.3, db.locked and 0.4 or 0.75, db.locked and 0.4 or 1, 0.8)
	layoutFrame(db.strip and db.strip.show)
	frame:Show()
	self:RefreshXPText()
end

--- UPDATE_EXHAUSTION: the XP line shows rested XP directly; the strip shows it as a share of the level.
function Leveling:OnExhaustionUpdate()
	self:RefreshXPText()
	self:QueueStripRefresh()
end

-- Lifecycle ------------------------------------------------------------------------

function Leveling:EnableXPTracker()
	if not frame then createFrame() end
	self:ResetXPSession()
	self:RegisterEvent("PLAYER_XP_UPDATE")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("UPDATE_EXHAUSTION", "OnExhaustionUpdate")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self.xpTicker = self:ScheduleRepeatingTimer("RefreshXPText", 5)
	self:RefreshTurnIns()
	self:UpdateXPFrame()

	-- Module toggles are live, so OnEnable can run more than once per session: register once.
	if self.xpTooltipRegistered then return end
	self.xpTooltipRegistered = true

	Lodestar:RegisterTooltipProvider(function(tooltip)
		if not self:IsEnabled() or atMaxLevel() then return end
		local rolling, average, ttl = self:GetXPRates()
		local rate = rolling > 0 and rolling or average
		tooltip:AddDoubleLine("XP/hour", FormatNumberShort(rate), 1, 0.82, 0, 1, 1, 1)
		tooltip:AddDoubleLine("Time to level", ttl and FormatDuration(ttl) or "—", 1, 0.82, 0, 1, 1, 1)
		tooltip:AddDoubleLine("Turn-ins ready", self:TurnInText() or "none", 1, 0.82, 0, 1, 1, 1)
	end)

	Lodestar:RegisterSlashVerb("xp", function(rest)
		if rest == "reset" then
			self:ResetXPSession()
			Lodestar:Say("XP session reset.")
			return
		end
		local rolling, average, ttl = self:GetXPRates()
		Lodestar:Say("XP/hour %s (session avg %s) · time to level %s · %s xp this session in %s",
			FormatNumberShort(rolling), FormatNumberShort(average), ttl and FormatDuration(ttl) or "—",
			BreakUpLargeNumbers(session and session.xp or 0), FormatDuration(session and (GetTime() - session.start) or 0))
		local turnIn = self:TurnInText()
		if turnIn then
			local _, count = self:GetTurnInXP()
			Lodestar:Say("%d quest%s ready to turn in: %s", count, count == 1 and "" or "s", turnIn)
		end
	end, "XP session summary, or /lode xp reset")
end

function Leveling:DisableXPTracker()
	self:UnregisterEvent("PLAYER_XP_UPDATE")
	self:UnregisterEvent("QUEST_TURNED_IN")
	self:UnregisterEvent("UPDATE_EXHAUSTION")
	self:UnregisterEvent("QUEST_LOG_UPDATE")
	if self.xpTicker then self:CancelTimer(self.xpTicker) self.xpTicker = nil end
	if turnInTimer then self:CancelTimer(turnInTimer) turnInTimer = nil end
	if frame then frame:Hide() end
end

-- Lodestar_Leveling: XP/hour, time-to-level and session stats.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local FormatNumberShort, FormatDuration = Lodestar.FormatNumberShort, Lodestar.FormatDuration

local session -- see ResetXPSession
local samples = {} -- { t = GetTime(), xp = gained } for the rolling window
local frame

local function maxLevel()
	if GetMaxLevelForPlayerExpansion then
		local ok, v = pcall(GetMaxLevelForPlayerExpansion)
		if ok and type(v) == "number" then return v end
	end
	return _G.MAX_PLAYER_LEVEL or 60
end

local function atMaxLevel()
	if IsXPUserDisabled and IsXPUserDisabled() then return true end
	return UnitLevel("player") >= maxLevel()
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

-- Events --------------------------------------------------------------------------

function Leveling:PLAYER_XP_UPDATE(_, unit)
	if unit ~= "player" or not session then return end
	local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	local gained
	if level > session.level then
		gained = (session.lastMax - session.lastXP) + xp
		session.levels = session.levels + (level - session.level)
		session.level = level
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
	self:RefreshXPText()
end

function Leveling:QUEST_TURNED_IN(_, _, xpReward)
	if not session then return end
	session.quests = session.quests + 1
	if type(xpReward) == "number" and xpReward > 0 then
		self.pendingQuestXP = xpReward
	end
end

function Leveling:OnLevelUpXP()
	if session then
		session.lastMax = UnitXPMax("player")
	end
	self:UpdateXPFrame()
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
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("XP/hour (last " .. (Leveling.db.profile.xp.windowMinutes) .. "m)", FormatNumberShort(rolling), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("XP/hour (session)", FormatNumberShort(average), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Time to level", ttl and FormatDuration(ttl) or "—", 1, 1, 1, 1, 1, 1)
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
	frame.text:SetText(table.concat(parts, "  |cff666666·|r  "))
	frame:SetWidth(math.max(120, frame.text:GetStringWidth() + 24))
end

function Leveling:UpdateXPFrame()
	if not frame then return end
	local db = self.db.profile.xp
	if not self:IsEnabled() or not db.show or atMaxLevel() then
		frame:Hide()
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(db.pos.point or "TOP", UIParent, db.pos.point or "TOP", db.pos.x or 0, db.pos.y or -120)
	frame:SetScale(db.scale or 1)
	frame:EnableMouse(true)
	frame:SetBackdropBorderColor(db.locked and 0.4 or 0.3, db.locked and 0.4 or 0.75, db.locked and 0.4 or 1, 0.8)
	frame:Show()
	self:RefreshXPText()
end

-- Lifecycle ------------------------------------------------------------------------

function Leveling:EnableXPTracker()
	if not frame then createFrame() end
	self:ResetXPSession()
	self:RegisterEvent("PLAYER_XP_UPDATE")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("UPDATE_EXHAUSTION", "RefreshXPText")
	self.xpTicker = self:ScheduleRepeatingTimer("RefreshXPText", 5)
	self:UpdateXPFrame()

	Lodestar:RegisterTooltipProvider(function(tooltip)
		if not self:IsEnabled() or atMaxLevel() then return end
		local rolling, average, ttl = self:GetXPRates()
		local rate = rolling > 0 and rolling or average
		tooltip:AddDoubleLine("XP/hour", FormatNumberShort(rate), 1, 0.82, 0, 1, 1, 1)
		tooltip:AddDoubleLine("Time to level", ttl and FormatDuration(ttl) or "—", 1, 0.82, 0, 1, 1, 1)
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
	end, "XP session summary, or /lode xp reset")
end

function Leveling:DisableXPTracker()
	self:UnregisterEvent("PLAYER_XP_UPDATE")
	self:UnregisterEvent("QUEST_TURNED_IN")
	self:UnregisterEvent("UPDATE_EXHAUSTION")
	if self.xpTicker then self:CancelTimer(self.xpTicker) self.xpTicker = nil end
	if frame then frame:Hide() end
end

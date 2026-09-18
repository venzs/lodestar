-- Lodestar_Leveling: time-per-level bookkeeping and the level-up announcement.
--
-- Played time is kept accurate by asking the server (RequestTimePlayed) once at login while
-- muting ChatFrameUtil.DisplayTimePlayed for a moment, then advanced locally every 30 seconds.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local FormatDuration = Lodestar.FormatDuration

local lastTick = GetTime()

--- Ask the server for /played without the two chat lines it normally prints.
local function requestPlayedSilently()
	local util = _G.ChatFrameUtil
	local original = util and util.DisplayTimePlayed
	if original then
		util.DisplayTimePlayed = function() end
		C_Timer.After(3, function() util.DisplayTimePlayed = original end)
	end
	RequestTimePlayed()
end

function Leveling:TIME_PLAYED_MSG(_, totalTime)
	if type(totalTime) == "number" then
		self.db.char.played = totalTime
		self.db.char.playedAt = time()
		lastTick = GetTime()
	end
end

--- Best-effort total played seconds.
function Leveling:GetPlayed()
	local char = self.db.char
	return (char.played or 0) + math.max(0, GetTime() - lastTick)
end

local function tickPlayed()
	local char = Leveling.db.char
	local now = GetTime()
	char.played = (char.played or 0) + (now - lastTick)
	lastTick = now
end

function Leveling:OnLevelUpStats(level)
	local char = self.db.char
	tickPlayed()
	local played = char.played or 0
	local prev = char.levels[tostring(level - 1)]
	char.levels[tostring(level)] = { at = time(), played = played }
	if not self.db.profile.stats.announce then return end
	local sinceLast = prev and prev.played and (played - prev.played) or nil
	if sinceLast and sinceLast > 0 then
		Lodestar:Msg("|cffffff00Level %d!|r %s since level %d · %s played total.", level, FormatDuration(sinceLast), level - 1, FormatDuration(played))
	else
		Lodestar:Msg("|cffffff00Level %d!|r %s played total.", level, FormatDuration(played))
	end
end

function Leveling:PrintLevelStats()
	local char = self.db.char
	local levels = {}
	for lvl in pairs(char.levels) do tinsert(levels, tonumber(lvl)) end
	table.sort(levels)
	Lodestar:Say("Level %d · %s played total.", UnitLevel("player"), FormatDuration(self:GetPlayed()))
	local prevPlayed
	for _, lvl in ipairs(levels) do
		local entry = char.levels[tostring(lvl)]
		local delta = prevPlayed and (entry.played - prevPlayed) or nil
		Lodestar:Say("  %d — %s%s", lvl, date("%Y-%m-%d %H:%M", entry.at), delta and (" (" .. FormatDuration(delta) .. " for the level)") or "")
		prevPlayed = entry.played
	end
end

function Leveling:EnableLevelStats()
	self:RegisterEvent("TIME_PLAYED_MSG")
	lastTick = GetTime()
	self.playedTicker = self:ScheduleRepeatingTimer(tickPlayed, 30)
	if not self.levelStatsSlash then
		self.levelStatsSlash = true
		Lodestar:RegisterSlashVerb("levels", function() self:PrintLevelStats() end, "time spent per level")
	end
	if self.db.profile.stats.syncPlayed and not self.playedSynced then
		self.playedSynced = true
		self:ScheduleTimer(requestPlayedSilently, 6)
	end
end

function Leveling:DisableLevelStats()
	self:UnregisterEvent("TIME_PLAYED_MSG")
	if self.playedTicker then self:CancelTimer(self.playedTicker) self.playedTicker = nil end
	tickPlayed()
end

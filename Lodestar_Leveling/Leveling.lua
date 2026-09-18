-- Lodestar_Leveling: module definition, defaults and settings page.
local Lodestar = _G.Lodestar
local L = Lodestar.L

local Leveling = Lodestar:NewModule("Leveling", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
Leveling.displayName = "Leveling"
Leveling.description = "XP/hour and time-to-level, quest auto-accept and turn-in, /way waypoints, level-up stats."
Leveling.order = 10

Leveling.defaults = {
	profile = {
		xp = {
			show = true,
			locked = false,
			windowMinutes = 30,
			scale = 1,
			showRested = true,
			showTurnIns = true,
			pos = { point = "TOP", x = 0, y = -120 },
			strip = {
				show = true,
				buffs = "Well Fed",   -- comma-separated aura names to show while active
				nagBags = true,
				nagDurability = true,
			},
		},
		quest = {
			autoAccept = true,
			autoTurnIn = true,
			autoGossip = true,
			skipTrivial = true,
			acceptShared = true,
			acceptEscort = true,
			pickSingleReward = true,
			pauseModifier = "SHIFT", -- SHIFT | CTRL | ALT | NONE
		},
		waypoints = {
			enabled = true,
			announce = true,
		},
		stats = {
			announce = true,
			syncPlayed = true,
		},
		camp = {
			enabled = true,
			warnExpiring = true,
			warnMinutes = 5,     -- warn when a watched buff has this long left
			warnFood = true,
			foodLow = 5,         -- warn at this many food/drink items or fewer
			showStock = true,    -- food count on the status strip
		},
		questLog = {
			nagFull = true,      -- say so when the log is nearly full, and name what has gone grey
		},
		professions = {
			enabled = true,
			nagCap = true,       -- say so when a profession hits its tier cap
			showOnStrip = true,  -- show professions at or near their cap on the strip
		},
	},
	char = {
		levels = {},     -- [level] = { at = epoch, played = seconds }
		played = 0,      -- total /played seconds (synced when possible)
		playedAt = 0,    -- epoch when 'played' was last accurate
		professions = {},-- [name] = { rank, maxRank, first, gained, at }
	},
}

local MODIFIERS = { SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt", NONE = L["Disabled"] }

Leveling.options = {
	xpHeader = { type = "header", order = 10, name = "XP tracker" },
	xpShow = {
		type = "toggle", order = 11, name = "Show XP tracker",
		desc = "A small movable readout with XP/hour, time to level and rested XP. Hidden at max level.",
		get = function() return Leveling.db.profile.xp.show end,
		set = function(_, v) Leveling.db.profile.xp.show = v; Leveling:UpdateXPFrame() end,
	},
	xpLocked = {
		type = "toggle", order = 12, name = "Lock position",
		desc = "When unlocked, drag the readout to move it.",
		get = function() return Leveling.db.profile.xp.locked end,
		set = function(_, v) Leveling.db.profile.xp.locked = v; Leveling:UpdateXPFrame() end,
	},
	xpRested = {
		type = "toggle", order = 13, name = "Show rested XP",
		get = function() return Leveling.db.profile.xp.showRested end,
		set = function(_, v) Leveling.db.profile.xp.showRested = v; Leveling:RefreshXPText() end,
	},
	xpTurnIns = {
		type = "toggle", order = 13.5, name = "Show XP waiting in completed quests",
		desc = "Adds the XP from quests ready to turn in — and whether that is enough to ding — to the readout. Always shown in the minimap tooltip.",
		get = function() return Leveling.db.profile.xp.showTurnIns end,
		set = function(_, v) Leveling.db.profile.xp.showTurnIns = v; Leveling:RefreshXPText() end,
	},
	xpWindow = {
		type = "range", order = 14, name = "Rate window (minutes)",
		desc = "XP/hour is computed over the last N minutes so it reacts to how you are playing right now. The tooltip also shows the whole-session average.",
		min = 5, max = 120, step = 5,
		get = function() return Leveling.db.profile.xp.windowMinutes end,
		set = function(_, v) Leveling.db.profile.xp.windowMinutes = v end,
	},
	xpScale = {
		type = "range", order = 15, name = "Scale", min = 0.6, max = 2, step = 0.1,
		get = function() return Leveling.db.profile.xp.scale end,
		set = function(_, v) Leveling.db.profile.xp.scale = v; Leveling:UpdateXPFrame() end,
	},
	xpReset = {
		type = "execute", order = 16, name = "Reset session",
		func = function() Leveling:ResetXPSession() end,
	},

	stripHeader = { type = "header", order = 17, name = "Status strip" },
	stripDesc = {
		type = "description", order = 17.1, fontSize = "medium",
		name = "A second line under the XP readout: free bag slots, lowest durability, rested XP as a share of the level, and the buffs you want to keep up.\n",
	},
	stripShow = {
		type = "toggle", order = 17.2, name = "Show the status strip",
		get = function() return Leveling.db.profile.xp.strip.show end,
		set = function(_, v) Leveling.db.profile.xp.strip.show = v; Leveling:UpdateXPFrame() end,
	},
	stripBuffs = {
		type = "input", order = 17.3, name = "Buffs to watch", width = "double",
		desc = "Comma-separated buff names, shown on the strip while active (e.g. Well Fed, Sharpened Blade).",
		get = function() return Leveling.db.profile.xp.strip.buffs or "" end,
		set = function(_, v) Leveling.db.profile.xp.strip.buffs = strtrim(v or ""); Leveling:RefreshStrip() end,
	},
	stripNagBags = {
		type = "toggle", order = 17.4, name = "Warn when 2 or fewer bag slots are free",
		desc = "A chat line at most once every five minutes; the strip turns orange (red when the bags are full).",
		get = function() return Leveling.db.profile.xp.strip.nagBags end,
		set = function(_, v) Leveling.db.profile.xp.strip.nagBags = v end,
	},
	stripNagDurability = {
		type = "toggle", order = 17.5, name = "Warn when durability drops to 20%",
		desc = "A chat line at most once every five minutes; the strip turns orange (red at 10%).",
		get = function() return Leveling.db.profile.xp.strip.nagDurability end,
		set = function(_, v) Leveling.db.profile.xp.strip.nagDurability = v end,
	},

	logNagFull = {
		type = "toggle", order = 17.8, name = "Warn when the quest log is nearly full",
		desc = "Names the quests that have gone grey, so you know what is safe to drop. |cffffff7f/lode log|r lists them any time; nothing is ever abandoned without asking.",
		get = function() return Leveling.db.profile.questLog.nagFull end,
		set = function(_, v) Leveling.db.profile.questLog.nagFull = v end,
	},

	campHeader = { type = "header", order = 18, name = "Camp" },
	campDesc = {
		type = "description", order = 18.1, fontSize = "medium",
		name = "How long your buffs have left and how much food and drink is in the bags -- the two things that decide whether you can stay out. |cffffff7f/lode camp|r prints the lot.\n",
	},
	campEnabled = {
		type = "toggle", order = 18.2, name = "Track camp state",
		get = function() return Leveling.db.profile.camp.enabled end,
		set = function(_, v) Leveling.db.profile.camp.enabled = v; Leveling:RefreshStrip() end,
	},
	campWarnExpiring = {
		type = "toggle", order = 18.3, name = "Warn before a watched buff drops",
		desc = "Uses the same buff list as the status strip. One line when it gets close, one more in the last minute.",
		get = function() return Leveling.db.profile.camp.warnExpiring end,
		set = function(_, v) Leveling.db.profile.camp.warnExpiring = v end,
	},
	campWarnMinutes = {
		type = "range", order = 18.4, name = "Warn this many minutes ahead",
		min = 1, max = 30, step = 1,
		get = function() return Leveling.db.profile.camp.warnMinutes end,
		set = function(_, v) Leveling.db.profile.camp.warnMinutes = v end,
	},
	campWarnFood = {
		type = "toggle", order = 18.5, name = "Warn when food and drink run low",
		get = function() return Leveling.db.profile.camp.warnFood end,
		set = function(_, v) Leveling.db.profile.camp.warnFood = v end,
	},
	campFoodLow = {
		type = "range", order = 18.6, name = "Low at this many items",
		min = 1, max = 40, step = 1,
		get = function() return Leveling.db.profile.camp.foodLow end,
		set = function(_, v) Leveling.db.profile.camp.foodLow = v; Leveling:RefreshStrip() end,
	},
	campShowStock = {
		type = "toggle", order = 18.7, name = "Show the food count on the strip",
		get = function() return Leveling.db.profile.camp.showStock end,
		set = function(_, v) Leveling.db.profile.camp.showStock = v; Leveling:RefreshStrip() end,
	},

	profHeader = { type = "header", order = 19, name = "Professions" },
	profDesc = {
		type = "description", order = 19.1, fontSize = "medium",
		name = "Classic tradeskills stop dead at 75, 150, 225 and 300 until a trainer raises the cap, and nothing in the default UI says when you get there. |cffffff7f/lode prof|r lists every profession and what it has gained.\n",
	},
	profEnabled = {
		type = "toggle", order = 19.2, name = "Track professions",
		get = function() return Leveling.db.profile.professions.enabled end,
		set = function(_, v) Leveling.db.profile.professions.enabled = v; Leveling:RefreshStrip() end,
	},
	profNagCap = {
		type = "toggle", order = 19.3, name = "Say so when a profession hits its cap",
		desc = "At most once every ten minutes per profession, with the next tier and the level it needs.",
		get = function() return Leveling.db.profile.professions.nagCap end,
		set = function(_, v) Leveling.db.profile.professions.nagCap = v end,
	},
	profOnStrip = {
		type = "toggle", order = 19.4, name = "Show capped professions on the strip",
		desc = "Only ones at or within ten points of the cap -- a skill at 43/75 is not news.",
		get = function() return Leveling.db.profile.professions.showOnStrip end,
		set = function(_, v) Leveling.db.profile.professions.showOnStrip = v; Leveling:RefreshStrip() end,
	},

	questHeader = { type = "header", order = 20, name = "Quest automation" },
	questDesc = {
		type = "description", order = 21, fontSize = "medium",
		name = "Hold the pause modifier while talking to an NPC to do things by hand.\n",
	},
	autoAccept = {
		type = "toggle", order = 22, name = "Auto-accept quests",
		get = function() return Leveling.db.profile.quest.autoAccept end,
		set = function(_, v) Leveling.db.profile.quest.autoAccept = v end,
	},
	autoTurnIn = {
		type = "toggle", order = 23, name = "Auto-turn-in quests",
		get = function() return Leveling.db.profile.quest.autoTurnIn end,
		set = function(_, v) Leveling.db.profile.quest.autoTurnIn = v end,
	},
	autoGossip = {
		type = "toggle", order = 24, name = "Skip gossip to quests",
		desc = "When an NPC's talk window lists quests, pick them automatically (completed turn-ins first).",
		get = function() return Leveling.db.profile.quest.autoGossip end,
		set = function(_, v) Leveling.db.profile.quest.autoGossip = v end,
	},
	skipTrivial = {
		type = "toggle", order = 25, name = "Leave grey quests alone",
		desc = "Don't auto-accept trivial (grey) quests.",
		get = function() return Leveling.db.profile.quest.skipTrivial end,
		set = function(_, v) Leveling.db.profile.quest.skipTrivial = v end,
	},
	pickSingleReward = {
		type = "toggle", order = 26, name = "Take the reward when there is only one",
		desc = "If a quest offers a choice of rewards the window stays open so you can pick.",
		get = function() return Leveling.db.profile.quest.pickSingleReward end,
		set = function(_, v) Leveling.db.profile.quest.pickSingleReward = v end,
	},
	acceptShared = {
		type = "toggle", order = 27, name = "Accept quests shared by party members",
		get = function() return Leveling.db.profile.quest.acceptShared end,
		set = function(_, v) Leveling.db.profile.quest.acceptShared = v end,
	},
	acceptEscort = {
		type = "toggle", order = 28, name = "Accept escort quests started by others",
		get = function() return Leveling.db.profile.quest.acceptEscort end,
		set = function(_, v) Leveling.db.profile.quest.acceptEscort = v end,
	},
	pauseModifier = {
		type = "select", order = 29, name = "Pause modifier", values = MODIFIERS,
		get = function() return Leveling.db.profile.quest.pauseModifier end,
		set = function(_, v) Leveling.db.profile.quest.pauseModifier = v end,
	},

	wayHeader = { type = "header", order = 30, name = "Waypoints" },
	wayDesc = {
		type = "description", order = 31, fontSize = "medium",
		name = "|cffffff7f/way 45.2 63.1 Note|r sets a native map pin with the floating arrow. |cffffff7f/way clear|r removes it. |cffffff7f/way|r alone prints where you are.\n",
	},
	wayEnabled = {
		type = "toggle", order = 32, name = "Enable /way",
		get = function() return Leveling.db.profile.waypoints.enabled end,
		set = function(_, v) Leveling.db.profile.waypoints.enabled = v end,
	},

	statsHeader = { type = "header", order = 40, name = "Level-up stats" },
	statsAnnounce = {
		type = "toggle", order = 41, name = "Announce time per level",
		desc = "On level-up, print how long the level took and total time played.",
		get = function() return Leveling.db.profile.stats.announce end,
		set = function(_, v) Leveling.db.profile.stats.announce = v end,
	},
	statsSync = {
		type = "toggle", order = 42, name = "Sync /played silently at login",
		desc = "Asks the server for your played time once at login and hides the chat spam, so level stats are exact.",
		get = function() return Leveling.db.profile.stats.syncPlayed end,
		set = function(_, v) Leveling.db.profile.stats.syncPlayed = v end,
	},
}

function Leveling:OnInitialize()
	self.L = L
end

function Leveling:OnEnable()
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:EnableXPTracker()
	self:EnableStatusStrip()
	self:EnableQuestAutomation()
	self:EnableWaypoints()
	self:EnableLevelStats()
	self:EnableProfessions()
	self:EnableCamp()
	self:EnableQuestLog()
end

function Leveling:PLAYER_LEVEL_UP(_, level)
	self:OnLevelUpStats(level)
	self:OnLevelUpXP(level)
end

function Leveling:OnDisable()
	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:DisableStatusStrip()
	self:DisableXPTracker()
	self:DisableQuestAutomation()
	self:DisableWaypoints()
	self:DisableLevelStats()
	self:DisableProfessions()
	self:DisableCamp()
	self:DisableQuestLog()
end

function Leveling:OnProfileChanged()
	self:UpdateXPFrame()
	self:RefreshStrip()
end

--- True while the configured pause modifier is held.
function Leveling:IsPaused()
	local mod = self.db.profile.quest.pauseModifier
	if mod == "SHIFT" then return IsShiftKeyDown() end
	if mod == "CTRL" then return IsControlKeyDown() end
	if mod == "ALT" then return IsAltKeyDown() end
	return false
end

Lodestar:RegisterModule(Leveling)

-- Lodestar_Guild: module definition, defaults and settings page.
local Lodestar = _G.Lodestar

local Guild = Lodestar:NewModule("Guild", "AceEvent-3.0", "AceTimer-3.0")
Guild.displayName = "Guild"
Guild.description = "Live guild presence: who is online, where, what level, and who wants a group."
Guild.order = 40

Guild.defaults = {
	profile = {
		share = true,
		heartbeatMinutes = 5,
		board = {
			pos = { point = "CENTER", x = 0, y = 0 },
			sameZoneFirst = true,
			showOffline = false,
		},
		notify = {
			lfg = true,
			levelUps = true,
		},
	},
	char = {
		lfgNote = nil,
	},
}

Guild.options = {
	shareHeader = { type = "header", order = 10, name = "Presence" },
	share = {
		type = "toggle", order = 11, name = "Share my presence with the guild",
		desc = "Sends your level, zone and XP progress to other Lodestar users in your guild over the addon channel. Nothing leaves the game.",
		get = function() return Guild.db.profile.share end,
		set = function(_, v) Guild.db.profile.share = v; if v then Guild:Broadcast() end end,
	},
	heartbeat = {
		type = "range", order = 12, name = "Refresh interval (minutes)", min = 1, max = 15, step = 1,
		get = function() return Guild.db.profile.heartbeatMinutes end,
		set = function(_, v) Guild.db.profile.heartbeatMinutes = v; Guild:RestartHeartbeat() end,
	},

	boardHeader = { type = "header", order = 20, name = "Guild board" },
	boardDesc = {
		type = "description", order = 21, fontSize = "medium",
		name = "|cffffff7f/lode guild|r opens the board. |cffffff7f/lode lfg <text>|r tells the guild what you're looking for; |cffffff7f/lode lfg clear|r removes it.\n",
	},
	sameZoneFirst = {
		type = "toggle", order = 22, name = "Guildmates in my zone first",
		get = function() return Guild.db.profile.board.sameZoneFirst end,
		set = function(_, v) Guild.db.profile.board.sameZoneFirst = v; Guild:RefreshBoard() end,
	},
	notifyLFG = {
		type = "toggle", order = 23, name = "Tell me when a guildmate posts a group request",
		get = function() return Guild.db.profile.notify.lfg end,
		set = function(_, v) Guild.db.profile.notify.lfg = v end,
	},
	notifyLevels = {
		type = "toggle", order = 24, name = "Tell me when a guildmate levels up",
		get = function() return Guild.db.profile.notify.levelUps end,
		set = function(_, v) Guild.db.profile.notify.levelUps = v end,
	},
}

function Guild:OnEnable()
	self:EnablePresence()
	self:EnableBoard()
end

function Guild:OnDisable()
	self:DisablePresence()
	self:DisableBoard()
end

Lodestar:RegisterModule(Guild)

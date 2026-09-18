-- Lodestar_UI: module definition, defaults and settings page.
local Lodestar = _G.Lodestar

local UI = Lodestar:NewModule("UI", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
UI.displayName = "UI"
UI.description = "Richer tooltips, map and minimap coordinates, clickable chat links with timestamps, faster looting."
UI.order = 30

UI.defaults = {
	profile = {
		tooltip = {
			ids = true,
			targetOfTarget = true,
			classColors = true,
			guild = true,
			itemLevel = false,
		},
		coords = {
			worldMap = true,
			minimap = true,
			minimapPos = { point = "TOP", relativePoint = "BOTTOM", x = 0, y = -4 },
		},
		chat = {
			urls = true,
			timestamps = true,
			timestampFormat = "%H:%M",
			copyButton = true,
		},
		loot = {
			fast = true,
		},
	},
}

UI.options = {
	tooltipHeader = { type = "header", order = 10, name = "Tooltips" },
	ttIDs = {
		type = "toggle", order = 11, name = "Item, spell and NPC IDs",
		get = function() return UI.db.profile.tooltip.ids end,
		set = function(_, v) UI.db.profile.tooltip.ids = v end,
	},
	ttToT = {
		type = "toggle", order = 12, name = "Target of target",
		desc = "Shows who a unit is targeting.",
		get = function() return UI.db.profile.tooltip.targetOfTarget end,
		set = function(_, v) UI.db.profile.tooltip.targetOfTarget = v end,
	},
	ttClass = {
		type = "toggle", order = 13, name = "Class-colored player names",
		get = function() return UI.db.profile.tooltip.classColors end,
		set = function(_, v) UI.db.profile.tooltip.classColors = v end,
	},
	ttGuild = {
		type = "toggle", order = 14, name = "Guild rank",
		desc = "Adds the player's guild rank next to the guild name.",
		get = function() return UI.db.profile.tooltip.guild end,
		set = function(_, v) UI.db.profile.tooltip.guild = v end,
	},
	ttIlvl = {
		type = "toggle", order = 15, name = "Item level on gear",
		get = function() return UI.db.profile.tooltip.itemLevel end,
		set = function(_, v) UI.db.profile.tooltip.itemLevel = v end,
	},

	coordsHeader = { type = "header", order = 20, name = "Coordinates" },
	coordsMap = {
		type = "toggle", order = 21, name = "World map: player and cursor",
		get = function() return UI.db.profile.coords.worldMap end,
		set = function(_, v) UI.db.profile.coords.worldMap = v; UI:UpdateCoordinates() end,
	},
	coordsMinimap = {
		type = "toggle", order = 22, name = "Under the minimap",
		get = function() return UI.db.profile.coords.minimap end,
		set = function(_, v) UI.db.profile.coords.minimap = v; UI:UpdateCoordinates() end,
	},

	chatHeader = { type = "header", order = 30, name = "Chat" },
	chatUrls = {
		type = "toggle", order = 31, name = "Clickable links",
		desc = "Web links in chat become clickable and open a box you can copy from.",
		get = function() return UI.db.profile.chat.urls end,
		set = function(_, v) UI.db.profile.chat.urls = v end,
	},
	chatTimestamps = {
		type = "toggle", order = 32, name = "Timestamps",
		desc = "Uses the game's own timestamp setting so it survives without the addon.",
		get = function() return UI.db.profile.chat.timestamps end,
		set = function(_, v) UI.db.profile.chat.timestamps = v; UI:ApplyTimestamps() end,
	},
	chatTimestampFormat = {
		type = "select", order = 33, name = "Timestamp format",
		values = { ["%H:%M"] = "13:05", ["%H:%M:%S"] = "13:05:42", ["%I:%M %p"] = "1:05 PM" },
		get = function() return UI.db.profile.chat.timestampFormat end,
		set = function(_, v) UI.db.profile.chat.timestampFormat = v; UI:ApplyTimestamps() end,
	},
	chatCopy = {
		type = "toggle", order = 34, name = "Copy-chat button",
		desc = "A small button on the chat frame that opens the recent chat in a copyable box.",
		get = function() return UI.db.profile.chat.copyButton end,
		set = function(_, v) UI.db.profile.chat.copyButton = v; UI:UpdateCopyButton() end,
	},

	lootHeader = { type = "header", order = 40, name = "Loot" },
	lootFast = {
		type = "toggle", order = 41, name = "Fast auto-loot",
		desc = "Takes every item the moment the loot window is ready instead of one at a time. Respects the game's auto-loot setting and its modifier key.",
		get = function() return UI.db.profile.loot.fast end,
		set = function(_, v) UI.db.profile.loot.fast = v end,
	},
}

function UI:OnEnable()
	self:EnableTooltips()
	self:EnableCoordinates()
	self:EnableChat()
	self:EnableLoot()
end

function UI:OnDisable()
	self:DisableTooltips()
	self:DisableCoordinates()
	self:DisableChat()
	self:DisableLoot()
end

function UI:OnProfileChanged()
	self:UpdateCoordinates()
	self:ApplyTimestamps()
	self:UpdateCopyButton()
end

Lodestar:RegisterModule(UI)

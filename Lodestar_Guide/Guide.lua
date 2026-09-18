-- Lodestar_Guide: module definition, defaults and settings page.
--
-- Guide packs register text guides with  Lodestar:GetModule("Guide"):RegisterGuide(text)  — see
-- Parser.lua for the format. The engine picks a guide for the character, shows the current step,
-- advances automatically from quest log events, and drives the navigation arrow.
local Lodestar = _G.Lodestar

local Guide = Lodestar:NewModule("Guide", "AceEvent-3.0", "AceTimer-3.0")
Guide.displayName = "Guide"
Guide.description = "Navigation arrow, step-by-step leveling guides, and a recorder that turns your playthrough into a guide."
Guide.order = 15

Guide.defaults = {
	profile = {
		arrow = {
			show = true,
			locked = false,
			scale = 1,
			mode = "AUTO",         -- AUTO | GUIDE | WAYPOINT | QUEST | OFF
			showETA = true,
			superTrack = true,     -- also super-track the quest the arrow points at
			pos = { point = "CENTER", x = 0, y = 180 },
			arrivalYards = 10,
		},
		steps = {
			show = true,
			locked = false,
			scale = 1,
			upcoming = 3,
			pos = { point = "TOPRIGHT", x = -40, y = -200 },
			autoAdvance = true,
			autoPickGuide = true,
			announce = true,
		},
	},
	char = {
		currentGuide = nil,          -- guide name
		progress = {},               -- [guideName] = step index
		recording = nil,             -- active recording (see Recorder.lua)
		recordings = {},             -- [name] = text
	},
}

local ARROW_MODES = { AUTO = "Automatic (guide, then waypoint, then quests)", GUIDE = "Guide step only", WAYPOINT = "/way waypoint only", QUEST = "Nearest quest objective", OFF = "Hidden" }

Guide.options = {
	arrowHeader = { type = "header", order = 10, name = "Navigation arrow" },
	arrowShow = {
		type = "toggle", order = 11, name = "Show arrow",
		get = function() return Guide.db.profile.arrow.show end,
		set = function(_, v) Guide.db.profile.arrow.show = v; Guide:UpdateArrowFrame() end,
	},
	arrowLocked = {
		type = "toggle", order = 12, name = "Lock position",
		get = function() return Guide.db.profile.arrow.locked end,
		set = function(_, v) Guide.db.profile.arrow.locked = v; Guide:UpdateArrowFrame() end,
	},
	arrowMode = {
		type = "select", order = 13, name = "Points at", values = ARROW_MODES,
		get = function() return Guide.db.profile.arrow.mode end,
		set = function(_, v) Guide.db.profile.arrow.mode = v; Guide:RetargetArrow() end,
	},
	arrowETA = {
		type = "toggle", order = 14, name = "Show time to arrival",
		get = function() return Guide.db.profile.arrow.showETA end,
		set = function(_, v) Guide.db.profile.arrow.showETA = v end,
	},
	arrowSuperTrack = {
		type = "toggle", order = 15, name = "Super-track the targeted quest",
		desc = "Also highlights the quest the arrow points at in the objective tracker and on the map.",
		get = function() return Guide.db.profile.arrow.superTrack end,
		set = function(_, v) Guide.db.profile.arrow.superTrack = v end,
	},
	arrowScale = {
		type = "range", order = 16, name = "Scale", min = 0.5, max = 2, step = 0.1,
		get = function() return Guide.db.profile.arrow.scale end,
		set = function(_, v) Guide.db.profile.arrow.scale = v; Guide:UpdateArrowFrame() end,
	},

	stepsHeader = { type = "header", order = 20, name = "Guide window" },
	stepsShow = {
		type = "toggle", order = 21, name = "Show guide window",
		get = function() return Guide.db.profile.steps.show end,
		set = function(_, v) Guide.db.profile.steps.show = v; Guide:UpdateStepFrame() end,
	},
	stepsLocked = {
		type = "toggle", order = 22, name = "Lock position",
		get = function() return Guide.db.profile.steps.locked end,
		set = function(_, v) Guide.db.profile.steps.locked = v; Guide:UpdateStepFrame() end,
	},
	stepsUpcoming = {
		type = "range", order = 23, name = "Upcoming steps shown", min = 0, max = 6, step = 1,
		get = function() return Guide.db.profile.steps.upcoming end,
		set = function(_, v) Guide.db.profile.steps.upcoming = v; Guide:RefreshStepFrame() end,
	},
	stepsScale = {
		type = "range", order = 24, name = "Scale", min = 0.6, max = 1.6, step = 0.1,
		get = function() return Guide.db.profile.steps.scale end,
		set = function(_, v) Guide.db.profile.steps.scale = v; Guide:UpdateStepFrame() end,
	},
	autoAdvance = {
		type = "toggle", order = 25, name = "Advance steps automatically",
		desc = "Move to the next step when the quest log shows the current one is done. Turn off to click through manually.",
		get = function() return Guide.db.profile.steps.autoAdvance end,
		set = function(_, v) Guide.db.profile.steps.autoAdvance = v end,
	},
	autoPick = {
		type = "toggle", order = 26, name = "Pick a guide for me at login",
		desc = "Chooses the installed guide that matches your faction, race, class and level.",
		get = function() return Guide.db.profile.steps.autoPickGuide end,
		set = function(_, v) Guide.db.profile.steps.autoPickGuide = v end,
	},
	stepsAnnounce = {
		type = "toggle", order = 27, name = "Announce step changes in chat",
		get = function() return Guide.db.profile.steps.announce end,
		set = function(_, v) Guide.db.profile.steps.announce = v end,
	},
	guidesHeader = { type = "header", order = 30, name = "Guides" },
	guidesDesc = {
		type = "description", order = 31, fontSize = "medium",
		name = function()
			local n = Guide.guides and #Guide.guides or 0
			return ("%d guide%s installed. |cffffff7f/lode guide list|r shows them, |cffffff7f/lode guide load <name>|r switches, |cffffff7f/lode record start|r begins recording your own route.\n"):format(n, n == 1 and "" or "s")
		end,
	},
	resetProgress = {
		type = "execute", order = 32, name = "Reset this character's guide progress", confirm = true,
		func = function() wipe(Guide.db.char.progress); Guide:LoadGuide(Guide.db.char.currentGuide, 1) end,
	},
}

-- One event dispatcher for the whole module (AceEvent keeps one handler per event per object).
local EVENTS = {
	"QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
	"PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "USER_WAYPOINT_UPDATED", "PLAYER_ENTERING_WORLD",
	"HEARTHSTONE_BOUND", "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
	"MERCHANT_SHOW", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_DATA_LOAD_RESULT", "QUESTLINE_UPDATE", "AREA_POIS_UPDATED",
}

function Guide:OnEnable()
	self:EnableArrow()
	self:EnableEngine()
	self:EnableStepFrame()
	self:EnableRecorder()
	for _, event in ipairs(EVENTS) do self:RegisterEvent(event, "OnGameEvent") end
end

function Guide:OnDisable()
	for _, event in ipairs(EVENTS) do self:UnregisterEvent(event) end
	self:DisableRecorder()
	self:DisableStepFrame()
	self:DisableEngine()
	self:DisableArrow()
end

function Guide:OnGameEvent(event, ...)
	self:RecorderOnEvent(event, ...)
	self:EngineOnEvent(event, ...)
	self:ArrowOnEvent(event, ...)
end

function Guide:OnProfileChanged()
	self:UpdateArrowFrame()
	self:UpdateStepFrame()
end

Lodestar:RegisterModule(Guide)

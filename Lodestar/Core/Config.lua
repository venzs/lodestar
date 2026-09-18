-- Lodestar core: AceConfig options and the Blizzard Settings integration.
local Lodestar = _G.Lodestar
local L = Lodestar.L

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local APP = "Lodestar"

local function generalOptions()
	return {
		type = "group",
		name = L["General"],
		order = 1,
		args = {
			header = {
				type = "description",
				order = 0,
				fontSize = "medium",
				name = Lodestar.COLOR .. "Lodestar|r " .. Lodestar.version .. "\n" .. L["Loaded modules: %s"]:format(Lodestar:GetModuleSummary()) .. "\n",
			},
			minimap = {
				type = "toggle",
				order = 10,
				width = "full",
				name = L["Minimap button"],
				desc = L["Show the Lodestar button on the minimap."],
				get = function() return not Lodestar.db.profile.minimap.hide end,
				set = function(_, v)
					Lodestar.db.profile.minimap.hide = not v
					Lodestar:UpdateMinimapButton()
				end,
			},
			chatMessages = {
				type = "toggle",
				order = 20,
				width = "full",
				name = L["Chat messages"],
				desc = L["Print Lodestar messages to chat (sold junk, repairs, level-ups, ...)."],
				get = function() return Lodestar.db.profile.chatMessages end,
				set = function(_, v) Lodestar.db.profile.chatMessages = v end,
			},
			versionNotices = {
				type = "toggle",
				order = 30,
				width = "full",
				name = L["Version notices"],
				desc = L["Tell me once per session when a guild or party member runs a newer Lodestar."],
				get = function() return Lodestar.db.profile.versionNotices end,
				set = function(_, v) Lodestar.db.profile.versionNotices = v end,
			},
			modulesHeader = { type = "header", order = 40, name = L["Modules"] },
			modules = {
				type = "group",
				inline = true,
				order = 41,
				name = "",
				args = {}, -- filled below
			},
		},
	}
end

local function moduleToggleArgs()
	local args = {}
	if #Lodestar.moduleList == 0 then
		args.none = { type = "description", order = 1, name = L["No modules loaded. Install Lodestar_Leveling, Lodestar_Economy, Lodestar_UI or Lodestar_Guild."] }
		return args
	end
	for i, module in ipairs(Lodestar.moduleList) do
		args[module.key] = {
			type = "toggle",
			order = i,
			width = "full",
			name = module.displayName,
			desc = module.description or L["Enable or disable this module. Changes take effect after /reload."],
			get = function() return Lodestar:IsModuleEnabled(module.key) end,
			set = function(_, v) Lodestar:SetModuleEnabled(module.key, v) end,
		}
	end
	return args
end

local function moduleOptions(module)
	local args = {
		__enabled = {
			type = "toggle",
			order = 0,
			width = "full",
			name = L["Enable %s"]:format(module.displayName),
			desc = module.description,
			disabled = false, -- own member beats the inherited group value
			get = function() return Lodestar:IsModuleEnabled(module.key) end,
			set = function(_, v) Lodestar:SetModuleEnabled(module.key, v) end,
		},
	}
	local source = type(module.options) == "function" and module.options(module) or module.options
	if type(source) == "table" then
		for k, v in pairs(source) do args[k] = v end
	end
	return {
		type = "group",
		name = module.displayName,
		order = module.order,
		disabled = function() return not Lodestar:IsModuleEnabled(module.key) end,
		args = args,
	}
end

function Lodestar:BuildOptions()
	local options = {
		type = "group",
		name = "Lodestar",
		childGroups = "tab",
		args = {
			general = generalOptions(),
		},
	}
	options.args.general.args.modules.args = moduleToggleArgs()
	for _, module in ipairs(self.moduleList) do
		options.args[module.key] = moduleOptions(module)
	end
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 1000
	return options
end

function Lodestar:SetupConfig()
	AceConfig:RegisterOptionsTable(APP, function() return self:BuildOptions() end)
	self.categoryIDs = {}
	local _, generalID = AceConfigDialog:AddToBlizOptions(APP, "Lodestar", nil, "general")
	self.categoryIDs.general = generalID
	self.configReady = true
	for _, module in ipairs(self.moduleList) do
		self:AddModuleToBlizOptions(module)
	end
	local _, profilesID = AceConfigDialog:AddToBlizOptions(APP, L["Profiles"], "Lodestar", "profiles")
	self.categoryIDs.profiles = profilesID
end

function Lodestar:AddModuleToBlizOptions(module)
	if self.categoryIDs[module.key] then return end
	local _, id = AceConfigDialog:AddToBlizOptions(APP, module.displayName, "Lodestar", module.key)
	self.categoryIDs[module.key] = id
end

function Lodestar:RefreshConfig()
	AceConfigRegistry:NotifyChange(APP)
end

--- Open the settings panel, optionally straight to a module page.
function Lodestar:OpenConfig(key)
	local id = (key and self.categoryIDs[key]) or self.categoryIDs.general
	if id and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(id)
	else
		AceConfigDialog:Open(APP)
	end
end

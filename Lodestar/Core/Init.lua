-- Lodestar core: addon object, saved variables, lifecycle.
local ADDON_NAME = ...

local Lodestar = LibStub("AceAddon-3.0"):NewAddon("Lodestar", "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
_G.Lodestar = Lodestar

Lodestar.L = LibStub("AceLocale-3.0"):GetLocale("Lodestar")
Lodestar.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
if Lodestar.version:find("^@") then Lodestar.version = "dev" end
Lodestar.COMM_PREFIX = "Lodestar"
Lodestar.COLOR = "|cff4fc3f7"

-- Build / flavor detection. Forever reports 1.60.x, so its interface number sits between Era (1.15.x) and TBC (2.x).
do
	local _, _, _, toc = GetBuildInfo()
	Lodestar.tocVersion = tonumber(toc) or 0
	Lodestar.IsForever = Lodestar.tocVersion >= 16000 and Lodestar.tocVersion < 20000
	Lodestar.IsMainlineAPI = Lodestar.IsForever or Lodestar.tocVersion >= 100000
end

local defaults = {
	profile = {
		modules = {},          -- [moduleName] = true/false (missing = enabled)
		minimap = { hide = false, minimapPos = 220 },
		chatMessages = true,
		versionNotices = true,
	},
	global = {
		debug = false,
	},
	char = {},
}

-- Where a contributor sends their harvest, and where they report a bug.
--
-- One constant, in one place, because it appears in /lode share, in the packaged INSTALL.txt and in
-- the addon listing, and three copies of an invite link is three chances for one of them to rot.
-- Change it here and tools/package.sh picks it up.
Lodestar.CONTACT = "https://discord.gg/dpAVzhyMC"

function Lodestar:OnInitialize()
	-- Saved.lua explains why these are not called LodestarDB and LodestarProbeDB any more.
	self:AdoptSaved("LodestarCore", "LodestarDB")
	self:AdoptSaved("LodestarProbes", "LodestarProbeDB")
	self:CountSession()
	self.db = LibStub("AceDB-3.0"):New("LodestarCore", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	self:RefreshPlayerInfo()

	self:SetupModuleRegistry()
	self:SetupConfig()
	self:SetupComm()
	self:SetupSlash()
end

--- Realm names: GetRealmName() is the display name ("Classic Beta PvP 2"); the normalized form (no
--- spaces) is what appears in Name-Realm strings from the API. GetNormalizedRealmName can be nil early
--- in the load, so this runs again at OnEnable.
function Lodestar:RefreshPlayerInfo()
	local display = GetRealmName() or "?"
	local normalized = GetNormalizedRealmName() or (display:gsub("[%s%-]", ""))
	self.player = self.player or {}
	self.player.name = UnitName("player")
	self.player.realm = display
	self.player.realmNormalized = normalized
	self.player.class = select(2, UnitClass("player"))
	self.player.faction = UnitFactionGroup("player")
	self.player.fullName = self.player.name .. "-" .. normalized
end

function Lodestar:OnEnable()
	self:RefreshPlayerInfo()
	self:InstallErrorCatcher()
	self:ApplyModuleStates()
	self:SetupMinimap()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function Lodestar:PLAYER_ENTERING_WORLD(_, isLogin, isReload)
	-- Instance in and out flips the Chat restriction, and the realm's restriction may only be
	-- readable once we are in the world. Either way the state is settled by the time this fires.
	self:CheckCommAvailability()
	if isLogin or isReload then
		self:ScheduleTimer("BroadcastVersion", 8)
	end
end

function Lodestar:OnProfileChanged()
	self:ApplyModuleStates()
	self:UpdateMinimapButton() -- rebinds LibDBIcon to the new profile's minimap table (hide + drag position)
	for _, module in self:IterateModules() do
		if module.OnProfileChanged then module:OnProfileChanged() end
	end
	self:RefreshConfig()
end

-- Luacheck configuration for the Lodestar suite.
-- Run tools/check.sh (or tools/check.ps1) which first generates tools/wow-api/luacheck_globals.lua
-- from Blizzard's UI source for the Forever client so every global we touch is verified to exist.
std = "lua51"
max_line_length = false
codes = true
self = false

exclude_files = {
	"Lodestar/Libs/**",
	"tools/**",
	".release/**",
}

ignore = {
	"212", -- unused argument
	"213", -- unused loop variable
	"631", -- line too long
	"542", -- empty if branch
}

globals = {
	"_G",            -- addon globals are set through _G on purpose
	"SlashCmdList",
	"Lodestar",
	"LodestarDB",
	"LodestarProbeDB",
	"SLASH_LODESTARWAY1",
	"SLASH_LODESTARWAY2",
	"Lodestar_OnAddonCompartmentClick",
	"Lodestar_OnAddonCompartmentEnter",
	"Lodestar_OnAddonCompartmentLeave",
	"ChatFrameUtil", -- we temporarily swap DisplayTimePlayed
}

-- Globals other addons provide.
local extra_read_globals = { "CUSTOM_CLASS_COLORS" }

local ok, generated = pcall(dofile, "tools/wow-api/luacheck_globals.lua")
if ok and type(generated) == "table" then
	local writable = {}
	for _, g in ipairs(globals) do writable[g] = true end
	local list = {}
	for _, g in ipairs(generated) do
		if not writable[g] then table.insert(list, g) end
	end
	for _, g in ipairs(extra_read_globals) do table.insert(list, g) end
	read_globals = list
else
	-- Fallback when the generated list is missing: keep luacheck useful for syntax and locals only.
	print("luacheck: tools/wow-api/luacheck_globals.lua not found; run tools/check.sh to verify WoW API usage")
	allow_defined_top = true
	read_globals = {
		"_G", "LibStub", "Enum", "Constants", "C_AddOns", "C_Timer", "C_Item", "C_Container", "C_Map", "C_QuestLog",
		"C_GossipInfo", "C_MerchantFrame", "C_AuctionHouse", "C_TooltipInfo", "C_ChatInfo", "C_GuildInfo", "C_Club",
		"C_CurrencyInfo", "C_CreatureInfo", "C_PartyInfo", "C_SuperTrack", "C_GameRules", "C_CVar", "C_PvP",
		"CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip", "Settings", "MenuUtil", "TooltipDataProcessor", "TooltipUtil",
		"UiMapPoint", "SlashCmdList", "hooksecurefunc", "strsplit", "strtrim", "tinsert", "tremove", "wipe", "date", "time",
		"GetTime", "GetBuildInfo", "UnitName", "UnitLevel", "UnitClass", "UnitXP", "UnitXPMax", "UnitGUID", "UnitExists",
		"UnitIsPlayer", "UnitIsUnit", "UnitFactionGroup", "GetXPExhaustion", "GetMoney", "IsInGuild", "IsInGroup", "IsInRaid",
	}
end

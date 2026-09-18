-- Lodestar core: /lode probe — records which APIs this client actually has into LodestarProbeDB.
-- Development aid for tracking the Forever beta as Blizzard changes it; harmless for users.
local Lodestar = _G.Lodestar
local L = Lodestar.L

-- Symbols the suite depends on, grouped by module. Dotted paths are resolved through _G.
local SYMBOLS = {
	core = {
		"C_AddOns.GetAddOnMetadata", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage",
		"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted", "C_Timer.After", "C_Timer.NewTicker",
		"Settings.OpenToCategory", "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory",
		"MenuUtil.CreateContextMenu", "AddonCompartmentFrame", "GetBuildInfo", "GetNormalizedRealmName",
		"C_CurrencyInfo.GetCoinTextureString", "C_GameRules.GetActiveGameMode", "C_GameRules.IsGameRuleActive",
		"StaticPopup_Show", "StaticPopupDialogs", "hooksecurefunc", "IsInGuild", "IsInGroup", "IsInRaid",
	},
	leveling = {
		"UnitXP", "UnitXPMax", "GetXPExhaustion", "GetRestState", "IsResting", "GetMaxLevelForPlayerExpansion",
		"C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.IsComplete", "C_QuestLog.ReadyForTurnIn",
		"C_QuestLog.GetTitleForQuestID", "C_QuestLog.IsQuestTrivial", "C_QuestLog.GetQuestDifficultyLevel",
		"C_QuestLog.GetSelectedQuest", "C_QuestLog.SetSelectedQuest", "GetQuestLogRewardXP", "GetQuestLogRewardMoney",
		"C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests", "C_GossipInfo.SelectAvailableQuest",
		"C_GossipInfo.SelectActiveQuest", "C_GossipInfo.GetOptions", "C_GossipInfo.SelectOption",
		"GetNumActiveQuests", "GetNumAvailableQuests", "GetActiveTitle", "GetAvailableTitle", "GetAvailableQuestInfo",
		"IsActiveQuestTrivial", "SelectActiveQuest", "SelectAvailableQuest", "GetActiveQuestID",
		"AcceptQuest", "DeclineQuest", "QuestGetAutoAccept", "AcknowledgeAutoAcceptQuest", "IsQuestCompletable",
		"CompleteQuest", "GetNumQuestChoices", "GetQuestReward", "GetQuestID", "GetTitleText", "ConfirmAcceptQuest",
		"GetRewardXP", "GetRewardMoney", "QuestFrame", "GossipFrame", "QuestFrameAcceptButton",
		"C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.SetUserWaypoint",
		"C_Map.ClearUserWaypoint", "C_Map.HasUserWaypoint", "C_Map.GetUserWaypoint", "C_Map.CanSetUserWaypointOnMap",
		"C_SuperTrack.SetSuperTrackedUserWaypoint", "C_SuperTrack.IsSuperTrackingUserWaypoint", "UiMapPoint.CreateFromCoordinates",
	},
	economy = {
		"C_MerchantFrame.SellAllJunkItems", "C_MerchantFrame.GetNumJunkItems", "C_MerchantFrame.IsSellAllJunkEnabled",
		"C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo", "C_Container.GetContainerItemLink",
		"C_Container.UseContainerItem", "C_Container.GetContainerItemID", "C_Container.GetBackpackSellJunkDisabled",
		"C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemCount", "C_Item.GetItemQualityColor",
		"C_Item.GetDetailedItemLevelInfo", "C_Item.GetItemNameByID", "C_Item.GetItemIconByID",
		"RepairAllItems", "GetRepairAllCost", "CanMerchantRepair", "CanGuildBankRepair", "GetMoney",
		"GetInventoryItemLink", "GetInventoryItemDurability", "MerchantFrame",
		"C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.GetBrowseResults", "C_AuctionHouse.HasFullBrowseResults",
		"C_AuctionHouse.RequestMoreBrowseResults", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
		"C_AuctionHouse.GetReplicateItemInfo", "C_AuctionHouse.GetReplicateItemLink", "C_AuctionHouse.GetCommoditySearchResultInfo",
		"C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetItemSearchResultInfo", "C_AuctionHouse.GetNumItemSearchResults",
		"C_AuctionHouse.GetItemKeyInfo", "C_AuctionHouse.MakeItemKey", "C_AuctionHouse.GetItemCommodityStatus",
		"C_AuctionHouse.SupportsCopperValues", "AuctionHouseFrame",
		"TooltipDataProcessor.AddTooltipPostCall", "TooltipUtil.GetDisplayedItem", "Enum.TooltipDataType",
	},
	ui = {
		"TooltipUtil.GetDisplayedUnit", "TooltipUtil.GetDisplayedSpell", "GameTooltip", "ItemRefTooltip",
		"GetPlayerInfoByGUID", "UnitGUID", "UnitIsPlayer", "UnitClass", "UnitName", "UnitLevel", "UnitCreatureType",
		"GetGuildInfo", "UnitPVPName", "UnitIsUnit", "UnitExists",
		"WorldMapFrame", "WorldMapFrame.ScrollContainer", "Minimap", "MinimapCluster",
		"ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter", "SetItemRef", "ChatFrameUtil",
		"GetNumLootItems", "LootSlot", "GetLootSlotInfo", "GetCVarBool", "IsModifiedClick", "C_CVar.GetCVar",
		"NUM_CHAT_WINDOWS", "ChatFrame1", "ChatFrame1EditBox", "CreateFrame", "BackdropTemplateMixin",
	},
	guild = {
		"C_Club.GetGuildClubId", "C_Club.GetClubMembers", "C_Club.GetMemberInfo", "C_Club.GetMemberInfoForSelf",
		"C_GuildInfo.GuildRoster", "C_GuildInfo.GetMOTD", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo",
		"GetGuildRosterMOTD", "GetRealZoneText", "GetSubZoneText", "GetMinimapZoneText", "UnitInParty", "UnitInRaid",
		"C_PartyInfo", "C_LFGList.GetActiveEntryInfo", "GetNumGroupMembers", "UnitIsGroupLeader", "Ambiguate",
	},
}

local function resolve(path)
	local node = _G
	for part in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil end
		node = rawget(node, part)
		if node == nil then return nil end
	end
	return node
end

local function safe(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return "ERR: " .. tostring(a)
end

function Lodestar:RunProbe()
	local version, build, buildDate, toc = GetBuildInfo()
	local probe = {
		when = date("%Y-%m-%d %H:%M:%S"),
		lodestar = self.version,
		client = { version = version, build = build, date = buildDate, toc = toc },
		project = {
			WOW_PROJECT_ID = _G.WOW_PROJECT_ID,
			WOW_PROJECT_MAINLINE = _G.WOW_PROJECT_MAINLINE,
			WOW_PROJECT_CLASSIC = _G.WOW_PROJECT_CLASSIC,
			LE_EXPANSION_LEVEL_CURRENT = _G.LE_EXPANSION_LEVEL_CURRENT,
			maxLevel = _G.GetMaxLevelForPlayerExpansion and safe(GetMaxLevelForPlayerExpansion) or nil,
			IsForever = self.IsForever,
		},
		gameRules = {},
		checks = {},
		missing = {},
		counts = {},
	}

	if C_GameRules then
		probe.gameRules.activeGameMode = C_GameRules.GetActiveGameMode and safe(C_GameRules.GetActiveGameMode) or nil
		probe.gameRules.gameModeRecordID = C_GameRules.GetCurrentGameModeRecordID and safe(C_GameRules.GetCurrentGameModeRecordID) or nil
		probe.gameRules.isHardcore = C_GameRules.IsHardcoreActive and safe(C_GameRules.IsHardcoreActive) or nil
		if C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then
			for _, rule in ipairs({ "UserAddonsDisabled", "UserScriptsDisabled", "MacrosDisabled", "WorldMapDisabled",
				"WorldMapTrackingPinDisabled", "IngameCalendarDisabled", "RepairArmorDisabled", "AchievementsPanelDisabled" }) do
				local id = Enum.GameRule[rule]
				if id then probe.gameRules[rule] = safe(C_GameRules.IsGameRuleActive, id) end
			end
		end
	end

	if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
		probe.restrictions = {}
		for name, id in pairs(Enum.AddOnRestrictionType) do
			probe.restrictions[name] = safe(C_RestrictedActions.IsAddOnRestrictionActive, id)
		end
	end
	if C_CombatLog and C_CombatLog.IsCombatLogRestricted then probe.checks.combatLogRestricted = safe(C_CombatLog.IsCombatLogRestricted) end
	probe.blocked = _G.LodestarProbeDB and _G.LodestarProbeDB.blocked or nil
	probe.errors = self:GetRecordedErrors()

	-- Live feature checks (things that exist but may be disabled by rules).
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	probe.checks.bestMapID = mapID
	if mapID and C_Map.CanSetUserWaypointOnMap then probe.checks.canSetWaypoint = safe(C_Map.CanSetUserWaypointOnMap, mapID) end
	if mapID and C_Map.GetPlayerMapPosition then
		local pos = safe(C_Map.GetPlayerMapPosition, mapID, "player")
		probe.checks.playerMapPosition = (type(pos) == "table" and pos.GetXY) and { pos:GetXY() } or tostring(pos)
	end
	if mapID and C_QuestLine and C_QuestLine.GetAvailableQuestLines then
		local lines = safe(C_QuestLine.GetAvailableQuestLines, mapID)
		probe.checks.questLinesOnMap = type(lines) == "table" and #lines or lines
	end
	if mapID and C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap then
		local hubs = safe(C_AreaPoiInfo.GetQuestHubsForMap, mapID)
		probe.checks.questHubsOnMap = type(hubs) == "table" and #hubs or hubs
		if type(hubs) == "table" and hubs[1] then probe.checks.firstHub = { name = hubs[1].name, description = hubs[1].description } end
	end
	if C_QuestLog.GetAllCompletedQuestIDs then
		local done = safe(C_QuestLog.GetAllCompletedQuestIDs)
		probe.checks.completedQuests = type(done) == "table" and #done or done
	end
	probe.checks.playerFacing = GetPlayerFacing and safe(GetPlayerFacing) or nil
	probe.checks.questLogEntries = C_QuestLog.GetNumQuestLogEntries and safe(C_QuestLog.GetNumQuestLogEntries) or nil
	if C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled then probe.checks.sellAllJunkEnabled = safe(C_MerchantFrame.IsSellAllJunkEnabled) end
	if C_AuctionHouse and C_AuctionHouse.SupportsCopperValues then probe.checks.ahSupportsCopper = safe(C_AuctionHouse.SupportsCopperValues) end
	if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then probe.checks.addonMsgRestricted = safe(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) end
	if C_Club and C_Club.GetGuildClubId then probe.checks.guildClubId = safe(C_Club.GetGuildClubId) end
	probe.checks.tooltipDataTypes = Enum and Enum.TooltipDataType and (function() local n = 0 for _ in pairs(Enum.TooltipDataType) do n = n + 1 end return n end)() or 0
	probe.checks.numAddonPrefixes = C_ChatInfo.GetRegisteredAddonMessagePrefixes and #(C_ChatInfo.GetRegisteredAddonMessagePrefixes() or {}) or nil

	local total, missing = 0, 0
	for group, list in pairs(SYMBOLS) do
		local n = 0
		for _, path in ipairs(list) do
			total = total + 1
			local value = resolve(path)
			local present = value ~= nil
			probe.checks[path] = present and type(value) or false
			if not present then
				missing = missing + 1
				tinsert(probe.missing, group .. ":" .. path)
			end
			n = n + 1
		end
		probe.counts[group] = n
	end
	table.sort(probe.missing)

	_G.LodestarProbeDB = probe
	self:Say(L["Probe written to LodestarProbeDB (%d symbols checked, %d missing). Log out or /reload to flush it to disk."], total, missing)
	if missing > 0 then
		self:Say("Missing: " .. table.concat(probe.missing, ", "))
	end
	self:Say(("Client %s (%s) toc %s · project %s · gameMode %s"):format(tostring(version), tostring(build), tostring(toc),
		tostring(_G.WOW_PROJECT_ID), tostring(probe.gameRules.activeGameMode)))
	return probe
end

-- Minimal WoW client stub for smoke-testing the Lodestar suite under plain Lua 5.1.
-- It is NOT the real API: values are plausible defaults so load/enable paths and event handlers
-- can run and crash loudly on typos, nil arithmetic and bad signatures.
local stub = {}
_G.STUB = stub
stub.now = 1000
stub.frames = {}
stub.timers = {}
stub.chat = {}
stub.sent = {}
stub.events = {}
stub.unknownGlobals = {}

-- Lua globals WoW provides --------------------------------------------------------
-- WoW's xpcall forwards extra arguments (Lua 5.2 semantics); plain 5.1 drops them.
local oxpcall = xpcall
xpcall = function(f, h, ...)
	local n, args = select("#", ...), { ... }
	return oxpcall(function() return f(unpack(args, 1, n)) end, h)
end
strsplit = function(delim, str, pieces)
	local out, pos = {}, 1
	if str == nil then return nil end
	while true do
		local s, e = str:find(delim, pos, true)
		if not s or (pieces and #out == pieces - 1) then
			out[#out + 1] = str:sub(pos)
			break
		end
		out[#out + 1] = str:sub(pos, s - 1)
		pos = e + 1
	end
	return unpack(out)
end
strjoin = function(delim, ...) return table.concat({ ... }, delim) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, strlen, strrep, strsub, strfind, strmatch = string.lower, string.upper, string.len, string.rep, string.sub, string.find, string.match
gsub, format, gmatch, strbyte, strchar = string.gsub, string.format, string.gmatch, string.byte, string.char
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
sort = table.sort
floor, ceil, abs, max, min, sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
fastrandom = math.random
debugstack = function() return "stack" end
stub.errors = {}
geterrorhandler = function() return function(err) tinsert(stub.errors, tostring(err)) io.stderr:write("LUA ERROR: " .. tostring(err) .. "\n") end end
seterrorhandler = function() end
issecure = function() return true end
securecallfunction = function(f, ...) return f(...) end
hooksecurefunc = function(tbl, name, hook)
	if type(tbl) == "string" then hook, name, tbl = name, tbl, _G end
	local orig = tbl[name]
	tbl[name] = function(...)
		local r = { orig(...) }
		hook(...)
		return unpack(r)
	end
end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
Mixin = function(obj, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end return obj end
CreateFromMixins = function(...) return Mixin({}, ...) end
tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
BreakUpLargeNumbers = function(n) return tostring(n) end
Round = function(n) return math.floor(n + 0.5) end
Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
GetTime = function() return stub.now end
GetTimePreciseSec = GetTime
GetFramerate = function() return 60 end
IsLoggedIn = function() return stub.loggedIn end
InCombatLockdown = function() return false end
GetBuildInfo = function() return "1.60.1", "69893", "Sep 16 2026", 16001 end
GetLocale = function() return "enUS" end
GetCVar = function(k) return stub.cvars[k] end
SetCVar = function(k, v) stub.cvars[k] = tostring(v) end
GetCVarBool = function(k) return stub.cvars[k] == "1" end
stub.cvars = { autoLootDefault = "1", showTimestamps = "none" }
RegisterCVar = function() end
IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = function() return stub.shift end, function() return false end, function() return false end
IsModifiedClick = function() return false end
GetRealmName = function() return "Classic Beta PvP 2" end
GetNormalizedRealmName = function() return "ClassicBetaPvP2" end
UnitName = function(u) if u == "player" then return "Venz" end if u == "questnpc" then return "Marshal McBride" end if u == "target" then return "Kobold Vermin" end if u == "targettarget" then return "Venz" end return nil end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitLevel = function() return stub.level end
UnitXP = function() return stub.xp end
UnitXPMax = function() return stub.xpMax end
UnitFactionGroup = function() return "Horde", "Horde" end
UnitGUID = function(u) if u == "player" then return "Player-1-000001" end return "Creature-0-1-2-3-6-000ABC" end
UnitExists = function(u) return u == "player" or u == "target" or u == "targettarget" or u == "questnpc" end
UnitIsPlayer = function(u) return u == "player" or u == "targettarget" end
UnitIsUnit = function(a, b) return a == b or (a == "targettarget" and b == "player") end
UnitAffectingCombat = function() return false end
GetXPExhaustion = function() return stub.rested end
GetRestState = function() return 1 end
IsResting = function() return true end
IsXPUserDisabled = function() return false end
GetMaxLevelForPlayerExpansion = function() return 60 end
GetMoney = function() return stub.money end
GetRealZoneText = function() return "Elwynn Forest" end
GetSubZoneText = function() return "Northshire Valley" end
GetMinimapZoneText = GetSubZoneText
IsInGuild = function() return true end
IsInGroup = function() return false end
IsInRaid = function() return false end
GetGuildInfo = function() return "Lodestar Test", "Member", 3 end
GetGuildBankWithdrawMoney = function() return -1 end
RequestTimePlayed = function() stub.fire("TIME_PLAYED_MSG", 36000, 1200) end
GetNumLootItems = function() return 2 end
LootSlot = function(i) stub.looted = (stub.looted or 0) + 1 end
-- quests
GetNumActiveQuests = function() return 1 end
GetNumAvailableQuests = function() return 1 end
GetActiveTitle = function() return "Kobold Camp Cleanup", true end
GetAvailableQuestInfo = function() return false, 0, false, false, 7, false, false end
IsActiveQuestTrivial = function() return false end
SelectActiveQuest = function() stub.selectedActive = true end
SelectAvailableQuest = function() stub.selectedAvailable = true end
AcceptQuest = function() stub.accepted = (stub.accepted or 0) + 1 end
AcknowledgeAutoAcceptQuest = function() stub.acknowledged = true end
QuestGetAutoAccept = function() return false end
QuestFlagsPVP = function() return false end
GetQuestID = function() return 7 end
IsQuestCompletable = function() return true end
CompleteQuest = function() stub.completed = true end
GetNumQuestChoices = function() return stub.choices or 0 end
GetQuestReward = function(i) stub.rewardTaken = i end
ConfirmAcceptQuest = function() stub.confirmed = true end
-- merchant
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return 1234, true end
RepairAllItems = function(guild) stub.repaired = guild and "guild" or "self" end
CanGuildBankRepair = function() return false end
-- chat
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) tinsert(stub.chat, msg) end, GetNumMessages = function() return #stub.chat end, GetMessageInfo = function(_, i) return stub.chat[i] end }
ChatFrame1 = DEFAULT_CHAT_FRAME
ChatFontNormal = {}
stub.filters = {}
ChatFrame_AddMessageEventFilter = function(event, fn) stub.filters[event] = stub.filters[event] or {} tinsert(stub.filters[event], fn) end
ChatFrame_RemoveMessageEventFilter = function() end
ChatFrameUtil = { DisplayTimePlayed = function() stub.displayedPlayed = true end, OpenChat = function(text) stub.openChat = text end }
ChatFrame_OpenChat = ChatFrameUtil.OpenChat
SetItemRef = function(link) stub.lastItemRef = link end
SendChatMessage = function() end
SlashCmdList = {}
UISpecialFrames = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0, WrapTextInColorCode = function(_, t) return t end }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, WrapTextInColorCode = function(_, t) return "|cffc79c6e" .. t .. "|r" end } }
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_ID = 1, 2, 1
LE_EXPANSION_LEVEL_CURRENT = 0
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
PlaySound = function() end
GameFontNormal, GameFontHighlight, GameFontNormalSmall, GameFontHighlightSmall, GameFontNormalLarge, GameFontDisableSmall = {}, {}, {}, {}, {}, {}

-- Enums / namespaces ----------------------------------------------------------------------
Enum = {
	ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4 },
	TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
	ClubMemberPresence = { Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5 },
	GameRule = { UserAddonsDisabled = 1, MacrosDisabled = 2 },
	GameMode = { Standard = 0 },
}
C_AddOns = { GetAddOnMetadata = function(_, k) if k == "Version" then return "0.1.0" end end, IsAddOnLoaded = function() return true end }
C_Timer = {
	After = function(delay, fn) tinsert(stub.timers, { at = stub.now + delay, fn = fn }) end,
	NewTicker = function(delay, fn) local t = { cancelled = false } tinsert(stub.timers, { at = stub.now + delay, fn = fn, every = delay, handle = t }) return t end,
}
C_CurrencyInfo = { GetCoinTextureString = function(c) return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100) end }
C_ChatInfo = {
	RegisterAddonMessagePrefix = function() return true end,
	SendAddonMessage = function(prefix, msg, dist, target) tinsert(stub.sent, { prefix = prefix, msg = msg, dist = dist, target = target }) return 0 end,
	SendAddonMessageLogged = function() return 0 end,
	SendChatMessage = function() end,
	AreOutgoingAddonChatMessagesRestricted = function() return false end,
	GetRegisteredAddonMessagePrefixes = function() return { "Lodestar" } end,
	IsAddonMessagePrefixRegistered = function() return true end,
}
C_GameRules = { GetActiveGameMode = function() return 0 end, IsGameRuleActive = function() return false end, GetCurrentGameModeRecordID = function() return 14 end, IsHardcoreActive = function() return false end }
C_QuestLog = { IsQuestTrivial = function() return false end, GetNumQuestLogEntries = function() return 0 end }
C_GossipInfo = {
	GetActiveQuests = function() return { { questID = 5, title = "Done", isComplete = true } } end,
	GetAvailableQuests = function() return { { questID = 6, title = "New", isTrivial = false } } end,
	SelectActiveQuest = function(id) stub.gossipActive = id end,
	SelectAvailableQuest = function(id) stub.gossipAvailable = id end,
	GetOptions = function() return {} end,
}
local vec = { GetXY = function() return 0.452, 0.631 end }
C_Map = {
	GetBestMapForUnit = function() return 37 end,
	GetPlayerMapPosition = function() return vec end,
	GetMapInfo = function(id) return { name = "Elwynn Forest", mapID = id } end,
	CanSetUserWaypointOnMap = function() return true end,
	SetUserWaypoint = function(p) stub.waypoint = p end,
	ClearUserWaypoint = function() stub.waypoint = nil end,
	HasUserWaypoint = function() return stub.waypoint ~= nil end,
	GetUserWaypoint = function() return stub.waypoint end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) stub.superTrack = v end, IsSuperTrackingUserWaypoint = function() return stub.superTrack end }
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = { x = x, y = y } } end }
stub.bags = {
	[0] = { [1] = { hyperlink = "|Hitem:1234::::::::1:::::|h[Broken Fang]|h", quality = 0, stackCount = 3, itemID = 1234, hasNoValue = false, isLocked = false },
	        [2] = { hyperlink = "|Hitem:5555::::::::1:::::|h[Nice Sword]|h", quality = 2, stackCount = 1, itemID = 5555, hasNoValue = false, isLocked = false } },
}
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
	GetContainerItemInfo = function(bag, slot) return stub.bags[bag] and stub.bags[bag][slot] end,
	UseContainerItem = function(bag, slot) stub.sold = (stub.sold or 0) + 1 stub.bags[bag][slot] = nil end,
}
C_Item = {
	GetItemInfo = function(link) return "Broken Fang", link, 0, 1, 1, "Junk", "Junk", 5, "", 134, 25 end,
	GetItemInfoInstant = function() return 1234, "Junk", "Junk", "", 134, 15, 0 end,
	GetItemNameByID = function(id) return "Item" .. id end,
	GetDetailedItemLevelInfo = function() return 10 end,
}
C_MerchantFrame = { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 1 end, SellAllJunkItems = function() end }
C_AuctionHouse = {
	GetBrowseResults = function() return { { itemKey = { itemID = 1234 }, minPrice = 5000, totalQuantity = 12 } } end,
	GetNumCommoditySearchResults = function() return 1 end,
	GetCommoditySearchResultInfo = function(id) return { itemID = id, unitPrice = 777, quantity = 3 } end,
	GetCommoditySearchResultsQuantity = function() return 3 end,
	GetNumItemSearchResults = function() return 1 end,
	GetItemSearchResultInfo = function() return { buyoutAmount = 9999 } end,
	ReplicateItems = function() end,
	GetNumReplicateItems = function() return 2 end,
	GetReplicateItemInfo = function() return "n", "t", 5, 1, true, 1, 1, 100, 1, 5000, 0, false, nil, "o", "o", 0, 4321, true end,
	SupportsCopperValues = function() return true end,
}
C_Club = {
	GetGuildClubId = function() return 42 end,
	GetClubMembers = function() return { 1, 2 } end,
	GetMemberInfo = function(_, id)
		if id == 1 then return { name = "Venz", isSelf = true, presence = 1, level = 12, zone = "Elwynn Forest", classID = 1 } end
		return { name = "Guildie-ClassicBetaPvP2", isSelf = false, presence = 1, level = 20, zone = "Westfall", classID = 1, guildRank = "Member" }
	end,
	GetMemberInfoForSelf = function() return { name = "Venz" } end,
}
C_GuildInfo = { GuildRoster = function() end, GetMOTD = function() return "" end }
C_CreatureInfo = { GetClassInfo = function() return { classFile = "WARRIOR", className = "Warrior" } end }
C_PartyInfo = { InviteUnit = function(n) stub.invited = n end }
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { ID = name, GetID = function(self) return self.ID end }, name end,
	RegisterCanvasLayoutSubcategory = function(cat, frame, name) return { ID = name, GetID = function(self) return self.ID end }, name end,
	RegisterAddOnCategory = function() end,
	GetCategory = function(id) return { ID = id } end,
	OpenToCategory = function(id) stub.openedCategory = id end,
}
MenuUtil = { CreateContextMenu = function(_, gen) local root = {} root.CreateTitle = function() end root.CreateCheckbox = function() end root.CreateDivider = function() end root.CreateButton = function() return root end root.CreateRadio = function() end gen(nil, root) stub.menuShown = true end }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) stub.tooltipCalls = stub.tooltipCalls or {} stub.tooltipCalls[kind] = stub.tooltipCalls[kind] or {} tinsert(stub.tooltipCalls[kind], fn) end }
TooltipUtil = {
	GetDisplayedItem = function() return "Broken Fang", "|Hitem:1234::::::::1:::::|h[Broken Fang]|h", 1234 end,
	GetDisplayedUnit = function() return "Kobold Vermin", "target", "Creature-0-1-2-3-6-000ABC" end,
	GetDisplayedSpell = function() return "Charge", 100 end,
}
LibStub = nil -- provided by the addon

-- Frames -------------------------------------------------------------------------------------
local Frame = {}
local function noop() end
-- Any unknown widget method is a no-op; unknown non-method keys stay nil.
Frame.__index = function(t, k)
	local v = rawget(Frame, k)
	if v ~= nil then return v end
	if type(k) == "string" and k:match("^[A-Z]") then return noop end
	return nil
end
local frameMethods = {
	"SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen",
	"SetMovable", "EnableMouse", "EnableMouseWheel", "RegisterForDrag", "RegisterForClicks", "SetBackdrop", "SetBackdropColor",
	"SetBackdropBorderColor", "StartMoving", "StopMovingOrSizing", "SetScale", "SetAlpha", "SetJustifyH", "SetWordWrap",
	"SetShadowOffset", "SetTextColor", "SetNormalTexture", "SetHighlightTexture", "SetMultiLine", "SetAutoFocus", "SetFontObject",
	"SetFocus", "HighlightText", "SetScrollChild", "UpdateScrollChildRect", "SetAllPoints", "SetColorTexture", "SetOwner", "AddLine",
	"AddDoubleLine", "SetText", "Disable", "Enable", "SetID", "SetParent", "SetTitle", "SetHitRectInsets", "SetPushedTexture",
	"SetDisabledTexture", "SetChecked", "SetMinMaxValues", "SetValue", "SetValueStep", "SetObeyStepOnDrag", "SetOrientation",
	"SetThumbTexture", "SetTexture", "SetTexCoord", "SetVertexColor", "SetBlendMode", "SetDrawLayer", "SetResizable",
	"SetResizeBounds", "SetMinResize", "SetMaxResize", "SetToplevel", "Raise", "Lower", "SetUserPlaced", "SetDontSavePosition",
	"SetTextInsets", "SetMaxLetters", "ClearFocus", "SetCursorPosition", "Insert", "SetNumeric", "SetPassword", "SetSpacing",
	"SetIndentedWordWrap", "SetNonSpaceWrap", "SetMaxLines", "SetFormattedText", "SetFont", "SetHyperlinksEnabled", "SetFading",
	"SetTimeVisible", "SetInsertMode", "ScrollToBottom", "SetTexelSnappingBias", "SetSnapToPixelGrid", "SetAtlas", "SetGradient",
	"SetDesaturated", "SetRotation", "SetPropagateKeyboardInput", "SetClipsChildren", "SetIgnoreParentScale", "SetIgnoreParentAlpha",
	"SetScript", "HookScript", "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "Show", "Hide", "SetShown",
}
for _, m in ipairs(frameMethods) do Frame[m] = noop end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn) local prev = self.scripts[name] self.scripts[name] = function(...) if prev then prev(...) end fn(...) end end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:UnregisterAllEvents() wipe(self.events) end
function Frame:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:IsMouseOver() return false end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:GetOwner() return self.owner end
function Frame:SetOwner(o) self.owner = o end
function Frame:GetPoint() return "TOP", UIParent, "TOP", 0, -120 end
function Frame:GetWidth() return 200 end
function Frame:GetHeight() return 20 end
function Frame:GetStringWidth() return 150 end
function Frame:GetText() return self.text end
function Frame:SetText(t) self.text = t end
function Frame:GetID() return self.id or 1 end
function Frame:GetBagID() return 0 end
function Frame:GetObjectType() return self.kind end
function Frame:GetMapID() return 37 end
function Frame:GetUnit() return "Kobold Vermin", "target" end
function Frame:GetNumMessages() return #stub.chat end
function Frame:GetMessageInfo(i) return stub.chat[i] end
function Frame:NumLines() return 1 end
function Frame:GetNormalizedCursorPosition() return 0.5, 0.5 end
function Frame:CreateFontString(name, layer, template) return stub.newFrame("FontString", name, self) end
function Frame:CreateTexture(name) return stub.newFrame("Texture", name, self) end
function Frame:CreateLine(name) local l = stub.newFrame("Line", name, self) l.SetStartPoint = function() end l.SetEndPoint = function(_, _, _, x, y) l.endX, l.endY = x, y end l.SetThickness = function() end return l end
function Frame:CreateAnimationGroup(name) return stub.newFrame("AnimationGroup", name, self) end
function Frame:CreateAnimation(kind) return stub.newFrame(kind or "Animation", nil, self) end
function Frame:CreateMaskTexture(name) return stub.newFrame("MaskTexture", name, self) end
function Frame:GetFrameLevel() return 1 end
function Frame:GetNormalTexture() return stub.newFrame("Texture", nil, self) end
function Frame:GetPushedTexture() return stub.newFrame("Texture", nil, self) end
function Frame:GetHighlightTexture() return stub.newFrame("Texture", nil, self) end
function Frame:GetFontString() return stub.newFrame("FontString", nil, self) end
function Frame:GetScrollChild() return self.child end
function Frame:SetScrollChild(c) self.child = c end
function Frame:GetTop() return 100 end
function Frame:GetBottom() return 0 end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return 100 end
function Frame:GetCenter() return 50, 50 end
function Frame:GetSize() return 200, 20 end
function Frame:GetFont() return "font", 12, "" end
function Frame:GetAlpha() return 1 end
function Frame:IsMovable() return true end
function Frame:GetVerticalScroll() return 0 end
function Frame:GetHorizontalScroll() return 0 end
function Frame:GetMinMaxValues() return 0, 1 end
function Frame:GetValue() return 0 end
function Frame:GetChecked() return false end
function Frame:GetTextColor() return 1, 1, 1 end
function Frame:GetStringHeight() return 12 end
function Frame:GetNumRegions() return 0 end
function Frame:GetNumChildren() return 0 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:GetMaxLetters() return 255 end
function Frame:GetCursorPosition() return 0 end
function Frame:IsEnabled() return true end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetScale() return 1 end
function Frame:GetChildren() return end
function Frame:GetRegions() return end
function Frame:GetNumPoints() return 1 end
function Frame:IsObjectType(kind) return self.kind == kind end
function stub.newFrame(kind, name, parent)
	local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, shown = true }, Frame)
	if name then _G[name] = f end
	tinsert(stub.frames, f)
	return f
end
CreateFrame = function(kind, name, parent, template) return stub.newFrame(kind, name, parent) end
UIParent = stub.newFrame("Frame", "UIParent")
WorldFrame = stub.newFrame("Frame", "WorldFrame")
GameTooltip = stub.newFrame("GameTooltip", "GameTooltip")
ItemRefTooltip = stub.newFrame("GameTooltip", "ItemRefTooltip")
Minimap = stub.newFrame("Frame", "Minimap")
Minimap.GetZoom = function() return stub.minimapZoom or 0 end
Minimap.GetWidth = function() return 140 end
MinimapCluster = stub.newFrame("Frame", "MinimapCluster")
MerchantFrame = stub.newFrame("Frame", "MerchantFrame")
MerchantFrame.shown = false
WorldMapFrame = stub.newFrame("Frame", "WorldMapFrame")
WorldMapFrame.ScrollContainer = stub.newFrame("Frame", nil, WorldMapFrame)
AuctionHouseFrame = stub.newFrame("Frame", "AuctionHouseFrame")
AddonCompartmentFrame = { RegisterAddon = function(_, data) stub.compartment = data end, registeredAddons = {}, UpdateDisplay = function() end }

-- Event dispatch and time --------------------------------------------------------------------
function stub.fire(event, ...)
	tinsert(stub.events, event)
	for _, f in ipairs(stub.frames) do
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end
function stub.advance(seconds)
	local target = stub.now + seconds
	while true do
		local nextT, idx
		for i, t in ipairs(stub.timers) do
			if (not t.handle or not t.handle.cancelled) and (not nextT or t.at < nextT) then nextT, idx = t.at, i end
		end
		if not nextT or nextT > target then break end
		local t = tremove(stub.timers, idx)
		stub.now = nextT
		t.fn()
		if t.every and not t.handle.cancelled then tinsert(stub.timers, { at = stub.now + t.every, fn = t.fn, every = t.every, handle = t.handle }) end
	end
	stub.now = target
	for _, f in ipairs(stub.frames) do
		if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, seconds) end
	end
end
function stub.slash(line)
	local cmd, rest = line:match("^(/%S+)%s*(.*)$")
	for key, fn in pairs(SlashCmdList) do
		local i = 1
		while _G["SLASH_" .. key .. i] do
			if _G["SLASH_" .. key .. i]:lower() == cmd:lower() then fn(rest) return true end
			i = i + 1
		end
	end
	error("no slash handler for " .. cmd)
end

-- State defaults
stub.level, stub.xp, stub.xpMax, stub.rested, stub.money, stub.loggedIn = 12, 4000, 10000, 500, 123456, false

-- Extras discovered while smoke testing the libraries ---------------------------------
UnitRace = function() return "Human", "Human", 1 end
GetCurrentRegion = function() return 1 end
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
IsAddOnLoaded = function() return true end
GetNumAddOns = function() return 5 end
UnitInBattleground = function() return nil end
UnitInRaid = function() return nil end
UnitInParty = function() return nil end
GetNumGroupMembers = function() return 0 end
UnitIsGroupLeader = function() return false end
C_PvP = { IsInBrawl = function() return false end }
GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, "Venz", "" end
GetServerTime = function() return os.time() end
IsInInstance = function() return false, "none" end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
GetCursorPosition = function() return 0, 0 end
GetMouseFoci = function() return {} end
ReloadUI = function() end
ITEM_QUALITY_COLORS = {}
FACTION_BAR_COLORS = {}
HIGHLIGHT_FONT_COLOR, RED_FONT_COLOR, GREEN_FONT_COLOR, GRAY_FONT_COLOR, YELLOW_FONT_COLOR = NORMAL_FONT_COLOR, NORMAL_FONT_COLOR, NORMAL_FONT_COLOR, NORMAL_FONT_COLOR, NORMAL_FONT_COLOR
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, WrapTextInColorCode = function(_, t) return t end, GetRGB = function(c) return c.r, c.g, c.b end } end
GameFontHighlightLarge, GameFontDisable, NumberFontNormal = {}, {}, {}

GetCurrentRegionName = function() return "US" end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
moduleByKey = function() return nil end
time = os.time
date = os.date
Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
strlenutf8 = string.len
GetMinimapShape = function() return "ROUND" end
issecretvalue = function() return false end
issecurevariable = function() return false end
ACCEPT, CANCEL, GAME_LOCALE = "Accept", "Cancel", "enUS"
ChatEdit_InsertLink = function() return false end
GetCursorInfo = function() return nil end
ClearCursor = function() end
-- Navigation / guide APIs
GetPlayerFacing = function() return stub.facing or 0 end
UnitRace = function() return "Undead", "Scourge", 5 end
UnitCanAttack = function() return true end
UnitIsDead = function() return true end
issecretvalue = function() return false end
GetBindLocation = function() return "Deathknell" end
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
stub.playerMap = { map = 18, x = 0.308, y = 0.662 }
C_Map.GetBestMapForUnit = function() return stub.playerMap.map end
C_Map.GetPlayerMapPosition = function(mapID) return { GetXY = function() return stub.playerMap.x, stub.playerMap.y end } end
C_Map.GetWorldPosFromMapPos = function(mapID, pos) return 0, { x = -pos.y * 10000, y = -pos.x * 10000 } end -- fake continent 0
C_Map.GetMapInfo = function(id) return { name = id == 18 and "Tirisfal Glades" or ("Map " .. tostring(id)), mapID = id, parentMapID = id == 18 and 947 or 0 } end
C_Map.GetMapChildrenInfo = function() return { { name = "Tirisfal Glades", mapID = 18 }, { name = "Elwynn Forest", mapID = 37 } } end
stub.questLog = {}   -- [questID] = { title, complete, objectives = { {text, finished} }, flagged }
stub.flagged = {}
C_QuestLog.GetNumQuestLogEntries = function() local n = 0 for _ in pairs(stub.questLog) do n = n + 1 end return n, n end
C_QuestLog.GetInfo = function(i) local n = 0 for id, q in pairs(stub.questLog) do n = n + 1 if n == i then return { questID = id, title = q.title, isHeader = false, isHidden = false } end end end
C_QuestLog.IsOnQuest = function(id) return stub.questLog[id] ~= nil end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return stub.flagged[id] == true end
C_QuestLog.IsComplete = function(id) local q = stub.questLog[id] return q and q.complete or false end
C_QuestLog.GetQuestObjectives = function(id) local q = stub.questLog[id] return q and q.objectives or {} end
C_QuestLog.GetTitleForQuestID = function(id) local q = stub.questLog[id] return q and q.title or ({ [3901] = "Rude Awakening", [364] = "The Mindless Ones" })[id] end
C_QuestLog.RequestLoadQuestByID = function(id) stub.requestedQuests = (stub.requestedQuests or 0) + 1 local known = ({ [3901] = true, [364] = true })[id] tinsert(stub.timers, { at = stub.now + 0.1, fn = function() stub.fire("QUEST_DATA_LOAD_RESULT", id, known == true) end }) end
C_QuestLog.GetNextWaypoint = function(id) local q = stub.questLog[id] if q and q.wp then return q.wp.map, q.wp.x, q.wp.y end end
C_QuestLog.GetNextWaypointText = function() return "Objective" end
C_QuestLog.GetQuestDifficultyLevel = function() return 2 end
C_SuperTrack.SetSuperTrackedQuestID = function(id) stub.superTrackedQuest = id end
C_CombatLog = { GetCurrentEventInfo = function() return 0, "UNIT_DIED", false, nil, nil, 0, 0, stub.diedGUID end }
ScriptErrorsFrame = { errorData = {}, GetCount = function(self) return #self.errorData end, GetErrorData = function(self, i) return self.errorData[i] end }
C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
Enum.AddOnRestrictionType = { Combat = 2, Chat = 1 }
C_QuestLine = { RequestQuestLinesForMap = function() end, GetAvailableQuestLines = function() return { { questID = 999, questName = "A Fresh Start", questLineName = "Deathknell", x = 0.52, y = 0.85 } } end }
C_AreaPoiInfo = { GetQuestHubsForMap = function() return { { areaPoiID = 1, name = "Brill", description = "Quest hub", position = { GetXY = function() return 0.6, 0.5 end } } } end }
UnitOnTaxi = function() return false end
UnitPosition = function() return -stub.playerMap.y * 10000, -stub.playerMap.x * 10000, 0, 0 end
-- Harvest / data APIs -----------------------------------------------------------------------
bit = bit or {}
if not bit.band then
	bit.band = function(a, b) local r, m = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end
	bit.bor = function(a, b) local r, m = 0, 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end
end
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
UnitClassification = function() return "normal" end
UnitReaction = function() return 4 end
UnitCreatureType = function() return "Undead" end
GetTaxiMapID = function() return 947 end
C_TaxiMap = { GetAllTaxiNodes = function() return {
	{ nodeID = 10, name = "Brill, Tirisfal Glades", position = { GetXY = function() return 0.6, 0.5 end }, state = 0 },
	{ nodeID = 11, name = "The Sepulcher, Silverpine Forest", position = { GetXY = function() return 0.5, 0.6 end }, state = 1 },
	{ nodeID = 12, name = "Tarren Mill, Hillsbrad", position = { GetXY = function() return 0.7, 0.7 end }, state = 2 },
} end }
C_QuestLog.GetQuestsOnMap = function() return stub.questsOnMap or {} end
C_QuestLog.GetDistanceSqToQuest = function(id) local q = stub.questLog[id] if q and q.distSq then return q.distSq, true end return nil end
C_QuestLog.GetLogIndexForQuestID = function(id) local n = 0 for qid in pairs(stub.questLog) do n = n + 1 if qid == id then return n end end end
C_QuestLog.GetQuestTagInfo = function() return nil end
C_QuestInfoSystem = { GetQuestClassification = function() return 0 end }
GetActiveQuestID = function() return 5 end
GetAvailableTitle = function() return "New" end
GetTitleText = function() return "A Quest" end
GetRewardXP = function() return 250 end
GetRewardMoney = function() return 50 end
QuestGetAutoAccept = function() return false end
-- Review-fix APIs (12.x) ----------------------------------------------------------------------
canaccessvalue = function() return true end
GameRulesUtil = { GetEffectiveMaxLevelForPlayer = function() return 60 end }
GetMaxPlayerLevel = function() return 60 end
Enum.GameRule.ExperienceBarDisabled = 3
LinkProcessorResponse = { Handled = 0, Unhandled = 1 }
LinkUtil = {
	handlers = {},
	RegisterLinkHandler = function(linkType, fn) LinkUtil.handlers[linkType] = fn end,
	IsLinkHandlerRegistered = function(linkType) return LinkUtil.handlers[linkType] ~= nil end,
	SplitLinkData = function(linkData) local t, o = linkData:match("^([^:]+):?(.*)$") return t, o end,
}
ChatFrameUtil.AddMessageEventFilter = function(event, fn) stub.chatFilters = stub.chatFilters or {} tinsert(stub.chatFilters, { event = event, fn = fn }) end
ChatFrameUtil.RemoveMessageEventFilter = function() end
GetGuildBankMoney = function() return stub.guildBankMoney or 0 end
C_ChatInfo.InChatMessagingLockdown = function() return stub.chatLockdown or false end
StaticPopup_Hide = function(which) stub.hiddenPopups = stub.hiddenPopups or {} stub.hiddenPopups[which] = true end
GetQuestMoneyToGet = function() return stub.questMoneyToGet or 0 end
QuestIsFromAreaTrigger = function() return false end
MAX_QUESTS = 25
C_GuildInfo.GuildRoster = function() stub.rosterRequested = (stub.rosterRequested or 0) + 1 end
Enum.PlayerInteractionType = { Merchant = 5 }
C_Texture = { GetAtlasInfo = function(name) if name == "Navigation-Tracked-Arrow" then return { width = 34, height = 44 } end end }
-- Trails APIs -------------------------------------------------------------------------------------
C_Map.GetMapWorldSize = function() return 10000, 10000 end -- matches the fake GetWorldPosFromMapPos scale above
UnitIsDeadOrGhost = function() return stub.dead or false end
-- Guide DSL: items, professions, trainers -------------------------------------------------------
stub.itemCounts = {}                 -- [itemID] = count in bags (+bank)
stub.professions = {}                -- { "Skinning", "Herbalism" } in the two primary slots
C_Item.GetItemCount = function(id) return stub.itemCounts[id] or 0 end
C_Item.RequestLoadItemDataByID = function() end
GetProfessions = function() return stub.professions[1] and 1 or nil, stub.professions[2] and 2 or nil, nil, nil, nil, nil end
GetProfessionInfo = function(index) local n = stub.professions[index] if n then return n, 134, 1, 75, 0, 0, 0, 0 end end
IsTradeskillTrainer = function() return stub.tradeskillTrainer or false end
-- Lodestar_Character: stat APIs and Blizzard's camelot stats-pane tables ----------------------------------
Enum.ItemClass = { Weapon = 2, Armor = 4 }
Enum.ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6, Sword1H = 7, Sword2H = 8, Obsolete3 = 9, Staff = 10, Bearclaw = 11, Catclaw = 12, Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19, Fishingpole = 20 }
Enum.Damageclass = { Physical = 0, Holy = 1, Fire = 2, Nature = 3, Frost = 4, Shadow = 5, Arcane = 6 }
Enum.PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
Enum.PvPRanks = { RankNone = 0, Rank_1 = 5, Rank_14 = 18 }
CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL, CR_EXPERTISE, CR_SPEED = 6, 7, 8, 24, 14
MAX_SPELL_SCHOOLS, BASE_MOVEMENT_SPEED = 7, 7
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED, INVSLOT_LAST_EQUIPPED = 16, 17, 18, 19
HIGHLIGHT_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE, GREEN_FONT_COLOR_CODE, RED_FONT_COLOR_CODE = "|cffffffff", "|r", "|cff20ff20", "|cffff2020"
STAT_FORMAT, PAPERDOLLFRAME_TOOLTIP_FORMAT = "%s:", "%s"
for i, school in ipairs({ "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }) do _G["DAMAGE_SCHOOL" .. (i + 1)] = school end
Constants = { LegacyConsts = { LEGACY_REWARD_TRACK_FACTION_ID = 2802, LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225, LEGACY_TREE_PROFESSIONS_ID = 1187, LEGACY_TREE_ADVENTURE_ID = 1188, LEGACY_TREE_PROGRESSION_ID = 1189 } }
GetCombatRatingBonus = function(rating) return ({ [6] = 2, [7] = 1, [8] = 3 })[rating] or 0 end
GetHitModifier = function() return 3 end        -- melee hit 2 + 3 = 5.0%
GetRangedHitModifier = function() return 2 end  -- ranged hit 1 + 2 = 3.0%
GetSpellHitModifier = function() return 1 end   -- spell hit 3 + 1 = 4.0%
GetCritChance = function() return 5.5 end
GetRangedCritChance = function() return 4.3 end
GetSpellCritChance = function() return 6.1 end
GetSpellBonusDamage = function(school) return school == 5 and 120 or 100 end -- Frost above the other schools
GetSpellBonusHealing = function() return 110 end
GetManaRegen = function() return 8.4, 2.2 end
GetManaRegenFromSpirit = function() return 6, 0 end
GetHealthRegen = function() return 6, 1.2 end
GetHealthRegenFromSpirit = function() return 4, 0 end
GetMeleeHaste = function() return stub.meleeHaste or 0 end
GetRangedHaste = function() return 0, 0 end
UnitSpellHaste = function() return 0 end
UnitAttackSpeed = function() return 2.6, 1.8 end
UnitDamage = function() return 40, 60, 20, 30, 0, 0, 1 end
UnitRangedDamage = function() return 2.9, 30, 50, 0, 0, 1 end
GetInventoryItemID = function(_, slot) return ({ [16] = 2001, [17] = 2002, [18] = 2003 })[slot] end
C_SkillInfo = { GetSkillLineInfoByID = function(id) return { skillID = id, name = ({ [43] = "Swords", [173] = "Daggers", [45] = "Bows", [162] = "Unarmed" })[id] or ("Skill " .. id), rank = 87, maxRank = 100, modifier = 5 } end }
UnitDefenseSkill = function() return 60, 5 end
GetShieldBlock = function() return 42 end
GetBlockChance = function() return 5 end
GetDodgeChance = function() return 8.2 end
GetParryChance = function() return 5 end
GetDodgeChanceFromAttribute = function() return 0.032 end
GetParryChanceFromAttribute = function() return 0 end
UnitArmor = function() return 900, 1000, 1000, 100 end
C_PaperDollInfo = {
	GetArmorEffectiveness = function(armor, level) return armor / (armor + 400 + 85 * level) end,
	GetArmorEffectivenessAgainstTarget = function() return nil end,
	OffhandHasShield = function() return stub.shield or false end,
	GetMinItemLevel = function() return 0 end,
}
UnitResistance = function(_, damageClass) local r = damageClass == 1 and (stub.holyResist or 0) or 10 return r, r, r, 0 end
ResistancePercent = function(resistance, casterLevel) return resistance / (casterLevel * 5) * 75 end
GetExpertise = function() return 0, 0, 0 end
GetArmorPenetration = function() return 0 end
GetSpellPenetration = function() return 0 end
GetAverageItemLevel = function() return 24.5, 23.2, 23.2 end
GetInventoryItemDurability = function(slot) if slot == 5 then return 62, 100 end if slot <= 10 then return 90, 100 end return nil end
GetRestState = function() return 1, "Rested", 2 end
GetUnitSpeed = function() return 7, 7, 0, stub.swimSpeed or 7 end
GetNumUnspentTalents = function() return stub.unspentTalents or 3 end
UnitPowerMax = function(_, powerType) if powerType == 0 then return stub.manaMax or 0 end return 100 end
GetShapeshiftForm = function() return 0 end
IsDualWielding = function() return true end
IsRangedWeapon = function() return true end
UnitEffectiveLevel = function() return stub.level end
UnitSex = function() return 2 end
GetText = function(key) return key end
C_MajorFactions = {
	GetCurrentRenownLevel = function() return stub.legacyRenown or 0 end,
	GetMajorFactionProgressionInfo = function() return { renownLevel = stub.pvpRank or 0, renownReputationEarned = 1234, renownLevelThreshold = 5000 } end,
}
C_Traits = {
	GetConfigIDByTreeID = function() return 77 end,
	GetTreeCurrencyInfo = function() return { { traitCurrencyID = 4225, quantity = 5, spent = 7 } } end,
	GetConfigInfo = function() return { treeIDs = { 1 } } end,
}
C_ClassTalents = { GetActiveConfigID = function() return nil end }
-- Camelot/PaperDollFrameConstants.lua + PaperDollFrame.lua, reduced to what the injection touches.
STAT_CATEGORY_GENERAL, STAT_CATEGORY_MODIFIERS = "General", "Modifiers"
PAPERDOLL_STATCATEGORIES = {
	{ categoryName = "General", unit = "player", stats = { { stat = "HEALTH" }, { stat = "POWER" } } },
	{ categoryName = "Modifiers", unit = "player", stats = { { stat = "HITCHANCE", hideAt = 0 }, { stat = "CRITCHANCE", hideAt = 0 }, { stat = "HASTE", hideAt = 0 } } },
	{ categoryName = "General", unit = "pet", stats = { { stat = "HEALTH" } } },
}
PaperDollFrame_SetLabelAndText = function(statFrame, label, text, isPercentage, numericValue)
	if statFrame.Label then statFrame.Label:SetText(STAT_FORMAT:format(label)) end
	if isPercentage then text = ("%d%%"):format(numericValue + 0.5) end
	statFrame.Value:SetText(text)
	statFrame.numericValue = numericValue
end
local function blizzardStat(label, value)
	return { updateFunc = function(statFrame) PaperDollFrame_SetLabelAndText(statFrame, label, tostring(value), false, value) return value end }
end
PAPERDOLL_STATINFO = { HEALTH = blizzardStat("Health", 1000), POWER = blizzardStat("Rage", 100), HITCHANCE = blizzardStat("Hit chance", 5), CRITCHANCE = blizzardStat("Critical strike", 6.1), HASTE = blizzardStat("Haste", 0) }
CharacterFrame = stub.newFrame("Frame", "CharacterFrame")
CharacterFrame.shown = false
-- Mirrors CharacterStatsPaneScrollBoxMixin:UpdateStats: walks the player categories, honours showFunc and hideAt.
stub.paperDollUpdates = 0
PaperDollFrame_UpdateStats = function()
	stub.paperDollUpdates = stub.paperDollUpdates + 1
	stub.paperDollRows = {}
	local statFrame = stub.paperDollStatFrame
	if not statFrame then
		statFrame = stub.newFrame("Frame")
		statFrame.Label, statFrame.Value = statFrame:CreateFontString(), statFrame:CreateFontString()
		stub.paperDollStatFrame = statFrame
	end
	for _, category in ipairs(PAPERDOLL_STATCATEGORIES) do
		if category.unit == "player" then
			for _, stat in ipairs(category.stats) do
				if not stat.showFunc or stat.showFunc() then
					statFrame.tooltip, statFrame.tooltip2, statFrame.tooltip3 = nil, nil, nil
					local numericValue = PAPERDOLL_STATINFO[stat.stat].updateFunc(statFrame, "player", stat.id)
					if numericValue ~= stat.hideAt then
						tinsert(stub.paperDollRows, { category = category.categoryName, stat = stat.stat, label = statFrame.Label.text, value = statFrame.Value.text, numeric = numericValue, tooltip2 = statFrame.tooltip2 })
					end
				end
			end
		end
	end
end
-- Quest tooltips: the world-object tooltip type, Blizzard's own quest line types, comparison tooltips --
Enum.TooltipDataType.Object = 4
Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17 }
ShoppingTooltip1 = stub.newFrame("GameTooltip", "ShoppingTooltip1")
ShoppingTooltip2 = stub.newFrame("GameTooltip", "ShoppingTooltip2")
-- Comm fallback / status strip / turn-ins ---------------------------------------------------------
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return stub.commRestricted or false end
stub.bagFree = { [0] = 3 }          -- [bag] = free slots (general-purpose bags; family 0)
stub.durability = { [1] = { 62, 100 }, [5] = { 90, 100 } } -- [slot] = { current, max }
stub.auras = { "Well Fed" }         -- player HELPFUL aura names in slot order
C_Container.GetContainerNumFreeSlots = function(bag) return stub.bagFree[bag] or 0, 0 end
GetInventoryItemDurability = function(slot) local d = stub.durability[slot] if d then return d[1], d[2] end return nil end
C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter) local name = stub.auras[i] if name then return { name = name, spellId = 1000 + i } end return nil end }
AuraUtil = { ForEachAura = function(unit, filter, maxCount, fn, usePacked)
	for i, name in ipairs(stub.auras) do
		local done
		if usePacked then done = fn({ name = name, spellId = 1000 + i }) else done = fn(name, 134, 1, nil, 0, 0, "player", false, false, 1000 + i) end
		if done then return end
	end
end }
stub.selectedQuest = 0
C_QuestLog.ReadyForTurnIn = function(id) local q = stub.questLog[id] return q and q.complete == true or false end
C_QuestLog.SetSelectedQuest = function(id) stub.selectedQuest = id end
C_QuestLog.GetSelectedQuest = function() return stub.selectedQuest end
GetQuestLogRewardXP = function(id) local q = stub.questLog[id or stub.selectedQuest] return q and q.xp or 0 end
-- Complain (but don't crash) on unknown globals so the stub can be extended deliberately.
setmetatable(_G, { __index = function(_, k)
	stub.unknownGlobals[k] = (stub.unknownGlobals[k] or 0) + 1
	return nil
end })
return stub

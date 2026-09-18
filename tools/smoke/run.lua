-- Smoke test: load the whole suite under the WoW stub, simulate login, poke every feature.
-- Usage (from the repo root): lua5.1 tools/smoke/run.lua
local ROOT = arg and arg[0] and arg[0]:match("^(.*)tools[/\\]smoke[/\\]run%.lua$") or "./"
if ROOT == "" then ROOT = "./" end
package.path = ROOT .. "tools/smoke/?.lua;" .. package.path
local stub = require("wow_stub")

local function loadLua(path)
	local chunk, err = loadfile(ROOT .. path)
	if not chunk then error("load " .. path .. ": " .. tostring(err)) end
	local addonName = path:match("^([^/\\]+)")
	local ok, perr = pcall(chunk, addonName, {})
	if not ok then error("run " .. path .. ": " .. tostring(perr)) end
end

--- Follow a TOC (and any XML includes) to load files in the same order the client would.
local function loadXml(path)
	local base = path:match("^(.*)[/\\][^/\\]+$") or ""
	for line in io.lines(ROOT .. path) do
		line = line:gsub("<!%-%-.-%-%->", "")
		local script = line:match('<Script%s+file="([^"]+)"')
		local include = line:match('<Include%s+file="([^"]+)"')
		local rel = script or include
		if rel then
			rel = rel:gsub("\\", "/")
			local full = base .. "/" .. rel
			if script then loadLua(full) else loadXml(full) end
		end
	end
end

local function loadToc(addon)
	local toc = addon .. "/" .. addon .. ".toc"
	for line in io.lines(ROOT .. toc) do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			local rel = line:gsub("\\", "/")
			local full = addon .. "/" .. rel
			if rel:match("%.xml$") then loadXml(full) elseif rel:match("%.lua$") then loadLua(full) end
		end
	end
	stub.fire("ADDON_LOADED", addon)
end

local addons = { "Lodestar", "Lodestar_Leveling", "Lodestar_Economy", "Lodestar_UI", "Lodestar_Guild", "Lodestar_Guide", "Lodestar_Guides_Horde" }
for _, a in ipairs(addons) do loadToc(a) end

stub.loggedIn = true
stub.fire("PLAYER_LOGIN")
stub.fire("PLAYER_ENTERING_WORLD", true, false)
stub.advance(15) -- login timers: version broadcast, presence, played sync

local checks, failures = 0, {}
local function check(cond, what)
	checks = checks + 1
	if not cond then tinsert(failures, what) end
end
local function try(what, fn)
	checks = checks + 1
	local ok, err = xpcall(fn, function(e) return os.getenv("SMOKE_TRACE") and debug.traceback(e, 2) or e end)
	if not ok then tinsert(failures, what .. ": " .. tostring(err)) end
end

local Lodestar = _G.Lodestar
check(Lodestar and Lodestar.db, "core initialised")
check(#Lodestar.moduleList == 5, "five modules registered, got " .. tostring(#Lodestar.moduleList))
for _, m in ipairs(Lodestar.moduleList) do check(m:IsEnabled(), "module enabled: " .. m.key) end
check(#stub.sent >= 2, "login comms sent (version + presence), got " .. #stub.sent)
check(stub.displayedPlayed ~= true, "played-time chat lines were muted")

-- Slash commands
for _, line in ipairs({ "/lode", "/lode version", "/lode modules", "/lode xp", "/lode probe", "/lode gold", "/lode levels",
	"/lode loc", "/lode way 45.2 63.1 Kobold cave", "/way 12,5 88,0", "/way", "/way clear", "/lode keep 1234", "/lode keep",
	"/lode ah", "/lode ah 1234", "/lode lfg Deadmines tank", "/lode guild", "/lode guild", "/lode modules Economy off", "/lode modules Economy on", "/lode debug", "/lode debug", "/lode nonsense" }) do
	try("slash " .. line, function() stub.slash(line) end)
end
check(stub.openedCategory ~= nil, "/lode opened settings")
check(LodestarProbeDB and LodestarProbeDB.checks, "probe wrote LodestarProbeDB")
try("way syntax", function()
	stub.slash("/way 18 45.0 63.0 pasted pin")
	check(stub.waypoint and stub.waypoint.uiMapID == 18 and math.abs(stub.waypoint.position.x - 0.45) < 1e-9, "Blizzard's '<mapID> x y' pin-command form accepted")
	stub.slash("/way #37 10 20")
	check(stub.waypoint and stub.waypoint.uiMapID == 37, "#mapID form still works")
	local savedMap = stub.playerMap.map
	stub.playerMap.map = nil
	stub.slash("/way 45 63")
	check((stub.chat[#stub.chat] or ""):find("Can't tell which map", 1, true) ~= nil, "no current map reports an error, not the x coordinate")
	stub.playerMap.map = savedMap
	local setWaypoint = C_Map.SetUserWaypoint
	C_Map.SetUserWaypoint = function() return false end
	stub.slash("/way 45 63")
	check((stub.chat[#stub.chat] or ""):find("Couldn't place a waypoint", 1, true) ~= nil, "SetUserWaypoint returning false is reported")
	C_Map.SetUserWaypoint = setWaypoint
	stub.slash("/way clear")
end)

-- Leveling: XP events and quest automation
try("xp update", function()
	stub.xp = 4500 stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("QUEST_TURNED_IN", 7, 900, 100)
	stub.xp = 5400 stub.fire("PLAYER_XP_UPDATE", "player")
	local rolling, average, ttl = Lodestar:GetModule("Leveling"):GetXPRates()
	check(rolling > 0 and average > 0 and ttl, "xp rates computed")
end)
local function sessionXP() -- parses "/lode xp" output: "... · 1234 xp this session in ..."
	stub.slash("/lode xp")
	return tonumber((stub.chat[#stub.chat] or ""):match("(%d+) xp this session"))
end
try("level up", function()
	local before = sessionXP()
	-- fields already fresh when PLAYER_LEVEL_UP fires: carry-over must use the OLD max (10000 - 5400 + 100)
	stub.level, stub.xp, stub.xpMax = 13, 100, 12000
	stub.fire("PLAYER_LEVEL_UP", 13)
	stub.fire("PLAYER_XP_UPDATE", "player")
	check(sessionXP() == before + 4700, "level-up carry-over uses the previous level's max, got +" .. tostring(sessionXP() - before))
	-- fields stale when PLAYER_LEVEL_UP fires (UnitLevel still 13): the payload decides the cap check
	stub.fire("PLAYER_LEVEL_UP", 60)
	check(LodestarXPFrame.shown == false, "xp frame hidden on the ding to max level (payload level)")
	stub.fire("PLAYER_XP_UPDATE", "player") -- level unchanged: no corruption, frame stays as decided
	check(sessionXP() == before + 4700, "stale-field level-up did not count phantom xp")
	Lodestar:GetModule("Leveling"):UpdateXPFrame()
	check(LodestarXPFrame.shown == true, "xp frame back at level 13")
end)
try("gossip", function() stub.fire("GOSSIP_SHOW") check(stub.gossipActive == 5, "gossip picked completed quest first") end)
try("greeting", function() stub.fire("QUEST_GREETING") check(stub.selectedActive, "greeting selected active quest") end)
try("detail", function() stub.fire("QUEST_DETAIL") check((stub.accepted or 0) >= 1, "quest accepted") end)
try("progress", function() stub.fire("QUEST_PROGRESS") check(stub.completed, "quest completed") end)
try("complete 0", function() stub.choices = 0 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == 0, "reward 0 taken") end)
try("complete 1", function() stub.choices = 1 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == 1, "single reward taken") end)
try("complete 2", function() stub.rewardTaken = nil stub.choices = 2 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == nil, "multi-choice left alone") end)
try("complete costs money", function()
	stub.rewardTaken = nil stub.choices = 0 stub.questMoneyToGet = 500
	stub.fire("QUEST_COMPLETE")
	check(stub.rewardTaken == nil, "quest with a money cost left for Blizzard's confirmation")
	stub.questMoneyToGet = 0
end)
try("paused", function() stub.shift = true stub.accepted = 0 stub.fire("QUEST_DETAIL") check(stub.accepted == 0, "shift pauses automation") stub.shift = false end)
try("detail closed by blizzard", function()
	stub.accepted = 0
	stub.fire("QUEST_DETAIL", 6948) -- item-started: QuestFrame already closed it and queued an OFFER popup
	check(stub.accepted == 0, "item-started quest offer not accepted behind the tracker popup")
	local autoAccept, areaTrigger = QuestGetAutoAccept, QuestIsFromAreaTrigger
	QuestGetAutoAccept, QuestIsFromAreaTrigger = function() return true end, function() return true end
	stub.acknowledged = nil
	stub.fire("QUEST_DETAIL", 0)
	check(stub.accepted == 0 and not stub.acknowledged, "area-trigger auto-accept offer left alone")
	QuestGetAutoAccept, QuestIsFromAreaTrigger = autoAccept, areaTrigger
	stub.fire("QUEST_DETAIL", 0)
	check(stub.accepted == 1, "normal offer still accepted")
end)
try("escort", function()
	stub.fire("QUEST_ACCEPT_CONFIRM", "Bob", "Escort")
	check(stub.confirmed, "escort confirmed")
	check(stub.hiddenPopups and stub.hiddenPopups.QUEST_ACCEPT, "Blizzard's QUEST_ACCEPT popup hidden after confirming")
	-- full quest log: leave Blizzard's QUEST_ACCEPT_LOG_FULL dialog to explain it
	local savedLog = stub.questLog
	stub.questLog = {}
	for i = 1, MAX_QUESTS do stub.questLog[90000 + i] = { title = "Filler " .. i, complete = false, objectives = {} } end
	stub.confirmed = nil stub.hiddenPopups = {}
	stub.fire("QUEST_ACCEPT_CONFIRM", "Bob", "Escort")
	check(not stub.confirmed and not stub.hiddenPopups.QUEST_ACCEPT, "escort not confirmed with a full quest log")
	stub.questLog = savedLog
end)

-- Economy: merchant
local function countChat(pattern)
	local n = 0
	for _, line in ipairs(stub.chat) do if line:find(pattern) then n = n + 1 end end
	return n
end
try("merchant", function()
	stub.slash("/lode keep 1234") -- undo the protection toggled above
	-- MerchantFrame stays hidden during MERCHANT_SHOW on this client (the interaction manager shows it later);
	-- auto-sell must not gate on the frame.
	check(not MerchantFrame:IsShown(), "merchant frame hidden while MERCHANT_SHOW is handled")
	stub.fire("MERCHANT_SHOW")
	stub.advance(2)
	check(stub.repaired == "self", "auto-repaired")
	check(stub.sold == 1, "sold exactly the one junk stack, got " .. tostring(stub.sold))
	check(countChat("Sold 1 junk item for") == 1, "single-item sale announced")
	stub.fire("MERCHANT_CLOSED")
end)
try("merchant re-show", function()
	-- A second MERCHANT_SHOW while the queue is draining must not leave a timer behind that spams the summary.
	for slot = 3, 5 do
		stub.bags[0][slot] = { hyperlink = "|Hitem:777::::::::1:::::|h[Grey Thing]|h", quality = 0, stackCount = 1, itemID = 777, hasNoValue = false, isLocked = false }
	end
	stub.sold = 0
	stub.fire("MERCHANT_SHOW")
	stub.fire("MERCHANT_SHOW")
	stub.advance(2)
	check(stub.sold == 3, "all three junk items sold across the re-show, got " .. tostring(stub.sold))
	stub.fire("MERCHANT_CLOSED")
	local before = countChat("Sold %d+ junk item")
	stub.advance(3)
	check(countChat("Sold %d+ junk item") == before, "no orphaned sell timer after re-show")
end)
try("guild repair", function()
	local E = Lodestar:GetModule("Economy")
	local cfg = E.db.profile.merchant
	cfg.guildRepair = true
	CanGuildBankRepair = function() return true end
	-- empty guild bank: personal gold pays, no "(guild funds)" claim
	stub.guildBankMoney = 0 stub.repaired = nil
	E:AutoRepair()
	check(stub.repaired == "self", "empty guild bank falls back to personal repair, got " .. tostring(stub.repaired))
	check(countChat("guild funds") == 0, "no guild-funds announcement without guild money")
	-- partial guild bank: split, announced as such
	stub.guildBankMoney = 1000 stub.repaired = nil
	E:AutoRepair()
	check(stub.repaired == "guild" and countChat("0g 10s 0c guild funds, 0g 2s 34c personal") == 1, "partial guild bank repair announces the split")
	-- partial guild bank but the player cannot cover the rest: no repair
	local money = stub.money
	stub.money = 100 stub.repaired = nil
	E:AutoRepair()
	check(stub.repaired == nil and countChat("not enough gold") == 1, "short on both guild and personal gold: no repair")
	stub.money = money
	-- guild bank covers it all
	stub.guildBankMoney = 5000 stub.repaired = nil
	E:AutoRepair()
	check(stub.repaired == "guild" and countChat("%(guild funds%)") == 1, "full guild bank repair announced")
	cfg.guildRepair = false
	CanGuildBankRepair = function() return false end
	stub.guildBankMoney = nil
end)
try("money", function() stub.money = 200000 stub.fire("PLAYER_MONEY") check(Lodestar:GetModule("Economy"):GetSessionGoldDelta() == 76544, "session gold delta") end)
try("auction", function()
	stub.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	stub.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2222)
	stub.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 3333 })
	stub.fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.advance(1)
	local E = Lodestar:GetModule("Economy")
	check(E:GetAHPrice(1234) and E:GetAHPrice(1234).p == 5000, "browse price recorded")
	check(E:GetAHPrice(2222) and E:GetAHPrice(2222).p == 777, "commodity price recorded")
	check(E:GetAHPrice(3333) and E:GetAHPrice(3333).p == 9999, "item search price recorded")
	check(E:GetAHPrice(4321) and E:GetAHPrice(4321).p == 1000, "replicate price recorded per unit")
end)

-- Tooltips (economy + ui post-calls)
try("tooltips", function()
	for kind, list in pairs(stub.tooltipCalls or {}) do
		for _, fn in ipairs(list) do fn(GameTooltip, { id = 1234, guid = "Creature-0-1-2-3-6-000ABC" }) end
	end
end)
try("tooltip item level", function()
	-- equipLoc is the 4th return of GetItemInfoInstant; the tooltip must read that slot.
	local UI = Lodestar:GetModule("UI")
	local lines = {}
	GameTooltip.AddDoubleLine = function(_, left, right) lines[left] = right end
	local instant = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function() return 1234, "Weapon", "Swords", "INVTYPE_WEAPON", 134, 2, 7 end
	UI.db.profile.tooltip.itemLevel = true
	for _, fn in ipairs(stub.tooltipCalls[Enum.TooltipDataType.Item]) do fn(GameTooltip, { id = 1234 }) end
	check(lines["Item level"] == "10", "item level line added for gear, got " .. tostring(lines["Item level"]))
	check(lines["Item ID"] == "1234", "item id line added")
	-- unit path goes through TooltipUtil.GetDisplayedUnit
	for _, fn in ipairs(stub.tooltipCalls[Enum.TooltipDataType.Unit]) do fn(GameTooltip, { guid = "Creature-0-1-2-3-6-000ABC" }) end
	check(lines["Targeting"] ~= nil and lines["NPC ID"] == "6", "unit tooltip decorated via TooltipUtil.GetDisplayedUnit")
	UI.db.profile.tooltip.itemLevel = false
	C_Item.GetItemInfoInstant = instant
	GameTooltip.AddDoubleLine = nil
end)

-- UI: chat filter, loot, coordinates
local function chatFilterFor(event)
	for _, entry in ipairs(stub.chatFilters or {}) do
		if entry.event == event then return entry.fn end
	end
end
try("url filter", function()
	-- filters are registered through ChatFrameUtil.AddMessageEventFilter, not the deprecation shim
	check(stub.filters.CHAT_MSG_SAY == nil, "legacy ChatFrame_AddMessageEventFilter not used")
	local fn = chatFilterFor("CHAT_MSG_SAY")
	check(fn ~= nil, "url filter registered via ChatFrameUtil")
	local _, msg = fn(nil, "CHAT_MSG_SAY", "see https://example.com/x?y=1 now", "Bob")
	check(msg and msg:find("|Hlodeurl:https://example.com/x?y=1|h", 1, true), "url linkified: " .. tostring(msg))
	-- lodeurl links go through the 12.x link-handler registry, short-circuiting SetItemRef
	check(LinkUtil.IsLinkHandlerRegistered("lodeurl"), "lodeurl link handler registered")
	local handler = LinkUtil.handlers.lodeurl
	local response = handler("lodeurl:https://example.com/a:b", "[https://example.com/a:b]", { type = "lodeurl", options = "https://example.com/a:b" })
	check(response == LinkProcessorResponse.Handled, "link handler reports Handled")
	check(LodestarCopyFrame and LodestarCopyFrame.shown, "copy box opened from link")
	check(LodestarCopyFrame.edit.text == "https://example.com/a:b", "copy box holds the full url, got " .. tostring(LodestarCopyFrame.edit.text))
end)
try("copy chat secrets", function()
	-- a secret (lockdown) chat line is placeholdered rather than passed to string functions
	local access = canaccessvalue
	canaccessvalue = function(v) return v ~= "SECRET LINE" end
	tinsert(stub.chat, "|cff00ff00visible|r line")
	tinsert(stub.chat, "SECRET LINE")
	LodestarCopyChatButton.scripts.OnClick(LodestarCopyChatButton)
	local text = LodestarCopyFrame.edit.text or ""
	check(text:find("visible line", 1, true) and text:find("[message hidden by chat restrictions]", 1, true), "secret chat line placeholdered")
	check(not text:find("SECRET LINE", 1, true), "secret chat line not copied")
	canaccessvalue = access
end)
try("loot", function() stub.fire("LOOT_READY", true) check(stub.looted == 2, "fast loot took both slots") end)
try("coords", function()
	WorldMapFrame.shown = true stub.advance(0.5)
	check(LodestarCoordsFrame ~= nil, "minimap coords frame exists")
	-- the world-map readout sits on an overlay frame above the canvas, not as a region of ScrollContainer
	local readout
	for _, f in ipairs(stub.frames) do
		if f.kind == "FontString" and f.text and f.text:find("Player|r 30.8, 66.2", 1, true) then readout = f end
	end
	check(readout ~= nil, "world-map coordinates rendered")
	local holder = readout and readout.parent
	check(holder and holder.kind == "Frame" and holder ~= WorldMapFrame.ScrollContainer, "readout is on its own holder frame")
	check(holder and holder.parent == WorldMapFrame, "holder falls back to the container's parent when BorderFrame is absent")
end)
try("timestamps", function() check(stub.cvars.showTimestamps == "%H:%M ", "timestamp cvar applied: " .. tostring(stub.cvars.showTimestamps)) end)

-- Guild: incoming presence and board
try("presence in", function()
	local ser = Lodestar:Serialize({ t = "P", v = "0.1.0", l = 20, z = "Westfall", s = "Moonbrook", x = 55, m = 52, c = "WARRIOR", n = "Deadmines" })
	Lodestar:OnCommReceived("Lodestar", ser, "GUILD", "Guildie-ClassicBetaPvP2")
	local G = Lodestar:GetModule("Guild")
	check(G.presence["Guildie"] and G.presence["Guildie"].l == 20, "presence stored under short name")
	local rows = G:CollectRows()
	check(#rows == 1 and rows[1].lodestar and rows[1].note == "Deadmines", "board row merged roster + presence")
	local dev = Lodestar:Serialize({ t = "V", v = "dev" })
	Lodestar:OnCommReceived("Lodestar", dev, "GUILD", "Someone")
	check(not Lodestar.versionNoticeShown, "unpackaged (dev) sender does not trigger the version notice")
	local ser2 = Lodestar:Serialize({ t = "V", v = "9.9.9" })
	Lodestar:OnCommReceived("Lodestar", ser2, "GUILD", "Someone")
	check(Lodestar.versionNoticeShown, "newer version notice shown")
	local q = Lodestar:Serialize({ t = "Q", v = "0.1.0" })
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Someone")
	stub.advance(5)
end)

-- Module toggling and profile change. AceAddon.statuses is the "actually running" flag that OnEnable /
-- OnDisable flip; module:IsEnabled() only reports the desired state.
local statuses = LibStub("AceAddon-3.0").statuses
-- Guild: query replies are unicast and coalesced, queries are rate-limited
local function countSent(dist)
	local n = 0
	for _, s in ipairs(stub.sent) do if s.dist == dist then n = n + 1 end end
	return n
end
try("query replies", function()
	local G = Lodestar:GetModule("Guild")
	local q = Lodestar:Serialize({ t = "Q", v = "0.1.0" })
	local sentBefore, whispersBefore, guildBefore = #stub.sent, countSent("WHISPER"), countSent("GUILD")
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Someone")
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Someone")
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Other-ClassicBetaPvP2")
	stub.advance(6)
	local targets = {}
	for i = sentBefore + 1, #stub.sent do
		local s = stub.sent[i]
		if s.dist == "WHISPER" then targets[s.target] = (targets[s.target] or 0) + 1 end
	end
	check(countSent("WHISPER") - whispersBefore == 2, "three Qs from two senders got two whispered replies, got " .. (countSent("WHISPER") - whispersBefore))
	check(targets["Someone"] == 1 and targets["Other-ClassicBetaPvP2"] == 1, "one reply per querier")
	check(countSent("GUILD") == guildBefore, "queries were not answered guild-wide")
	check(G.replyTimer == nil, "reply timer cleared after sending")
	-- Q rate limit: the login query was under a minute ago, so this one is dropped
	local before = #stub.sent
	G:Query()
	check(#stub.sent == before, "query rate-limited within a minute")
	stub.advance(60)
	before = #stub.sent
	G:Query()
	check(#stub.sent == before + 1 and stub.sent[#stub.sent].dist == "GUILD", "query sent again after the interval")
end)

-- Guild: disabling the module stops comm handling and notifications
try("guild disable", function()
	local G = Lodestar:GetModule("Guild")
	Lodestar:SetModuleEnabled("Guild", false)
	check(not G:IsEnabled(), "Guild disabled live")
	local chatBefore, sentBefore = #stub.chat, #stub.sent
	local p = Lodestar:Serialize({ t = "P", v = "0.1.0", l = 30, z = "Duskwood", s = "", x = 10, m = 47, c = "MAGE", n = "Stockades healer" })
	Lodestar:OnCommReceived("Lodestar", p, "GUILD", "Quiet")
	local q = Lodestar:Serialize({ t = "Q", v = "0.1.0" })
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Quiet")
	stub.advance(6)
	check(G.presence["Quiet"] == nil, "presence ignored while disabled")
	check(#stub.chat == chatBefore, "no LFG notification while disabled")
	check(#stub.sent == sentBefore, "no reply sent while disabled")
	stub.slash("/lode lfg Nope") -- prints a "module is disabled" notice, sends nothing
	check(#stub.sent == sentBefore and G.db.char.lfgNote ~= "Nope", "/lode lfg does nothing while disabled")
	Lodestar:SetModuleEnabled("Guild", true)
	check(G:IsEnabled(), "Guild re-enabled live")
	chatBefore = #stub.chat
	Lodestar:OnCommReceived("Lodestar", p, "GUILD", "Quiet")
	check(G.presence["Quiet"] and G.presence["Quiet"].l == 30, "presence handled again after re-enable")
	check(#stub.chat == chatBefore + 1 and stub.chat[#stub.chat]:find("Stockades healer", 1, true), "LFG notification printed again after re-enable")
	stub.advance(15) -- re-enable announce timer
end)

-- Guild: chat-messaging lockdown skips the (secret) roster, guild change wipes presence
try("guild lockdown + guild change", function()
	local G = Lodestar:GetModule("Guild")
	stub.chatLockdown = true
	local rows = G:CollectRows()
	local fromRoster = false
	for _, r in ipairs(rows) do if r.rank then fromRoster = true end end
	check(#rows >= 1 and not fromRoster, "lockdown: presence-only rows, roster skipped (" .. #rows .. " rows)")
	local before = #stub.sent
	G:Broadcast(true)
	G:Query()
	check(#stub.sent == before, "lockdown: nothing sent")
	stub.slash("/lode guild")
	check(LodestarGuildBoard.shown, "board opened under lockdown without error")
	stub.slash("/lode guild")
	stub.chatLockdown = false
	rows = G:CollectRows()
	fromRoster = false
	for _, r in ipairs(rows) do if r.rank then fromRoster = true end end
	check(fromRoster, "roster merged again once lockdown lifts")
	-- roster refresh request honours canRequestRosterUpdate only while the board is shown
	local requested = stub.rosterRequested or 0
	stub.fire("GUILD_ROSTER_UPDATE", true)
	check((stub.rosterRequested or 0) == requested, "no roster request while the board is hidden")
	stub.slash("/lode guild")
	requested = stub.rosterRequested or 0
	stub.fire("GUILD_ROSTER_UPDATE", true)
	check((stub.rosterRequested or 0) == requested + 1, "roster re-requested when the server says it is stale")
	stub.fire("GUILD_ROSTER_UPDATE", false)
	check((stub.rosterRequested or 0) == requested + 1, "no roster request when the server says it is fresh")
	stub.fire("CLUB_MEMBER_PRESENCE_UPDATED", 42, 2, 1)
	stub.advance(1.5)
	stub.slash("/lode guild")
	-- guild change
	check(next(G.presence) ~= nil, "presence populated before guild change")
	stub.fire("PLAYER_GUILD_UPDATE", "target")
	check(next(G.presence) ~= nil, "another unit's guild update is ignored")
	local realGetGuildInfo = GetGuildInfo
	GetGuildInfo = function() return "Another Guild", "Initiate", 9 end
	before = #stub.sent
	stub.fire("PLAYER_GUILD_UPDATE", "player")
	check(next(G.presence) == nil, "presence wiped on guild change")
	stub.advance(3)
	check(#stub.sent == before + 2 and stub.sent[#stub.sent].dist == "GUILD", "announced to and queried the new guild, sent " .. (#stub.sent - before))
	stub.fire("PLAYER_GUILD_UPDATE", "player")
	check(#stub.sent == before + 2, "same guild again: nothing re-sent")
	GetGuildInfo = realGetGuildInfo
	stub.fire("PLAYER_GUILD_UPDATE", "player")
	stub.advance(3)
end)

-- Module toggling and profile change
try("toggle module", function()
	Lodestar:SetModuleEnabled("UI", false)
	check(not Lodestar:GetModule("UI"):IsEnabled(), "UI disabled live")
	check(statuses["Lodestar_UI"] == false, "UI OnDisable ran")
	Lodestar:SetModuleEnabled("UI", true)
	check(Lodestar:GetModule("UI"):IsEnabled(), "UI re-enabled live")
	check(statuses["Lodestar_UI"] == true, "UI OnEnable ran")
	stub.slash("/lode modules Economy off")
	check(statuses["Lodestar_Economy"] == false and not Lodestar:IsModuleEnabled("Economy"), "/lode modules Economy off ran OnDisable")
	stub.slash("/lode modules Economy on")
	check(statuses["Lodestar_Economy"] == true, "/lode modules Economy on ran OnEnable")
	-- re-enabling Leveling must not stack another minimap tooltip provider
	local providers = #Lodestar.tooltipProviders
	Lodestar:SetModuleEnabled("Leveling", false)
	Lodestar:SetModuleEnabled("Leveling", true)
	check(#Lodestar.tooltipProviders == providers, "tooltip provider registered once across toggles, got " .. #Lodestar.tooltipProviders .. " vs " .. providers)
	-- profile switch: the new profile's module flags are applied live
	Lodestar.db.profile.modules.Guild = false
	Lodestar:OnProfileChanged()
	check(statuses["Lodestar_Guild"] == false, "profile change disabled Guild")
	Lodestar.db.profile.modules.Guild = nil
	Lodestar:OnProfileChanged()
	check(statuses["Lodestar_Guild"] == true, "profile change re-enabled Guild")
end)
try("profile change rebinds minimap", function()
	local DBIcon = LibStub("LibDBIcon-1.0")
	local newMinimap = { hide = true, minimapPos = 90 }
	Lodestar.db.profile.minimap = newMinimap
	Lodestar:OnProfileChanged()
	local button = DBIcon:GetMinimapButton("Lodestar")
	check(button and button.db == newMinimap, "LibDBIcon bound to the current profile's minimap table")
	check(button and button.shown == false, "new profile's hide flag applied")
	newMinimap.hide = false
	Lodestar:UpdateMinimapButton()
	check(button and button.shown == true, "button shown again")
end)
try("options build", function()
	local opts = Lodestar:BuildOptions()
	check(opts.args.Leveling and opts.args.Economy and opts.args.UI and opts.args.Guild and opts.args.profiles, "options tree has all groups")
	-- exercise every get/set once
	local function walk(group)
		for _, opt in pairs(group.args or {}) do
			if opt.type == "group" then walk(opt)
			elseif opt.get then
				local v = opt.get({})
				if opt.set and opt.type == "toggle" then opt.set({}, v) end
				if opt.set and opt.type == "range" then opt.set({}, v) end
				if opt.set and opt.type == "select" then opt.set({}, v) end
			end
		end
	end
	walk(opts.args.Leveling) walk(opts.args.Economy) walk(opts.args.UI) walk(opts.args.Guild) walk(opts.args.general)
end)
try("blocked call capture", function()
	stub.fire("ADDON_ACTION_FORBIDDEN", "Lodestar", "SomeProtectedFunction")
	check(LodestarProbeDB.blocked and LodestarProbeDB.blocked[1].func == "SomeProtectedFunction", "forbidden call recorded")
	ScriptErrorsFrame.errorData[1] = { message = "Interface/AddOns/Lodestar_UI/Chat.lua:12: boom", stack = "stack", count = 2, time = "x" }
	ScriptErrorsFrame.errorData[2] = { message = "SomeOtherAddon.lua:1: nope", stack = "stack", count = 1, time = "x" }
	check(#Lodestar:GetRecordedErrors() == 1, "only Lodestar errors listed")
	stub.slash("/lode errors")
	stub.slash("/lode errors clear")
end)
try("minimap menu", function() Lodestar:ShowModuleMenu() check(stub.menuShown, "context menu built") end)

-- Guide: parser, engine, arrow, recorder
local G = Lodestar:GetModule("Guide")
try("parser", function()
	local P = G.Parser
	local g, err = P.Parse([[
#guide Test 1-2: Parser
#faction Horde
#race Undead
#levels 1-2
#next Nope
step
  .goto 18,30.8,66.2
  .accept 3901 >>Accept Rude Awakening
step Kill things
  .goto Tirisfal Glades,31,67,15
  .complete 364,1
  .complete 364,2 >>Second objective
step
  .turnin 364
  .xp 3
step
  .goto 18,40,40
step
  .hs Deathknell
  .train
  .class Paladin
]])
	check(g, "parsed: " .. tostring(err))
	check(g and #g.steps == 5, "five steps")
	check(g and g.steps[1].actions[1].type == "accept" and g.steps[1].actions[1].questID == 3901, "accept parsed")
	check(g and g.steps[1].actions[1].text == "Accept Rude Awakening", ">> text parsed")
	check(g and g.steps[2].label == "Kill things" and g.steps[2].go.map == "Tirisfal Glades" and g.steps[2].go.radius == 15, "label and named map goto")
	check(g and g.steps[2].actions[2].objective == 2, "objective index parsed")
	check(g and g.steps[3].actions[2].type == "level" and g.steps[3].actions[2].level == 3, "xp parsed")
	check(g and g.steps[4].arrival, "goto-only step marks arrival")
	check(g and g.steps[5].classes and g.steps[5].classes["paladin"], "class filter parsed")
	check(g and g.races and g.races["undead"], "race header parsed")
	local bad, berr = P.Parse("#guide X\nstep\n  .bogus 1")
	check(bad == nil and berr and berr:find("unknown directive"), "bad directive rejected: " .. tostring(berr))
	check(P.StepText(g.steps[1], function(id) return "Rude Awakening" end) == "Accept Rude Awakening", "step text")
	check(P.StepText(g.steps[4], nil, nil, function(m) return "Tirisfal Glades" end):find("Go to 40.0, 40.0"), "goto-only text")
end)
try("guide pack loaded", function()
	check(G.guideByName["Horde/Undead 1-5: Deathknell"] ~= nil, "Deathknell sample registered")
	check(G.current and G.current.name == "Horde/Undead 5-12: Tirisfal Glades", "level-12 character got the 5-12 guide at login: " .. tostring(G.current and G.current.name))
	stub.level = 3
	local picked = G:PickGuide()
	check(picked and picked.name == "Horde/Undead 1-5: Deathknell", "auto-pick chose the undead guide at level 3: " .. tostring(picked and picked.name))
	G:LoadGuide(picked.name, 1)
	check(G.current and G.current.name == picked.name, "guide loaded")
	check(G.stepIndex == 1, "starts at step 1")
end)
try("engine advance", function()
	-- accept 363 -> step 1 done
	stub.questLog[363] = { title = "Rude Awakening", complete = false, objectives = {} }
	stub.fire("QUEST_ACCEPTED", 363)
	stub.advance(1)
	check(G.stepIndex == 2, "advanced to step 2 after accept, at " .. tostring(G.stepIndex))
	-- turn in 363 and accept 364 -> step 2 done
	stub.questLog[363] = nil stub.flagged[363] = true
	stub.fire("QUEST_TURNED_IN", 363, 250, 0)
	stub.questLog[364] = { title = "The Mindless Ones", complete = false, objectives = { { text = "Mindless Zombie slain: 0/8", finished = false } } }
	stub.fire("QUEST_ACCEPTED", 364)
	stub.advance(1)
	check(G.stepIndex == 3, "advanced to step 3, at " .. tostring(G.stepIndex))
	-- manual next / prev
	G:NextStep() check(G.stepIndex == 4, "manual next")
	G:PrevStep() check(G.stepIndex == 3, "manual prev")
	stub.slash("/lode guide step 2")
	check(G.stepIndex >= 3, "step 2 is already complete so evaluate skips forward, at " .. tostring(G.stepIndex))
	stub.slash("/lode guide list")
	stub.slash("/lode guide load Deathknell")
	stub.slash("/lode guide")
	stub.slash("/lode guide")
end)
try("arrow", function()
	stub.slash("/lode arrow guide")
	G:RetargetArrow()
	local t = G:GetArrowTarget()
	check(t and t.kind == "guide", "arrow targets the guide step: " .. tostring(t and t.kind))
	local dist, bearing = G:VectorTo(18, 0.308, 0.60)
	check(dist and dist > 0 and bearing, "vector computed: " .. tostring(dist))
	stub.slash("/lode arrow quest")
	wipe(G:HarvestDB().npcs) -- the gossip stub's npc offers quest 6 right here; keep it out of this check
	stub.questLog[364].wp = { map = 18, x = 0.309, y = 0.661 }
	G:RetargetArrow()
	t = G:GetArrowTarget()
	check(t and t.kind == "quest" and t.questID == 364, "arrow targets nearest quest waypoint: " .. tostring(t and t.questID))
	check(stub.superTrackedQuest == 364, "super-tracked the quest")
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	check(LodestarArrow.dist.text and LodestarArrow.dist.text:find("yd"), "distance text rendered: " .. tostring(LodestarArrow.dist.text))
	stub.slash("/lode arrow auto")
	stub.slash("/lode arrow")
	stub.slash("/lode arrow")
end)
try("recorder", function()
	stub.slash("/lode record start Test route")
	check(G.db.char.recording ~= nil, "recording started")
	stub.fire("GOSSIP_SHOW")
	stub.questLog[364] = { title = "The Mindless Ones", complete = false, objectives = { { text = "Mindless Zombie slain: 0/8", finished = false } } }
	stub.fire("QUEST_ACCEPTED", 364)
	-- objective ticks up while a Kobold Vermin is targeted -> kill credited to it
	stub.questLog[364].objectives[1].text = "Mindless Zombie slain: 1/8"
	stub.fire("QUEST_LOG_UPDATE")
	stub.questLog[364].objectives[1].text = "Mindless Zombie slain: 8/8"
	stub.questLog[364].objectives[1].finished = true
	stub.playerMap.x, stub.playerMap.y = 0.304, 0.689
	stub.fire("QUEST_LOG_UPDATE")
	stub.fire("PLAYER_LEVEL_UP", 14)
	stub.fire("HEARTHSTONE_BOUND")
	stub.fire("TRAINER_SHOW") stub.fire("TRAINER_CLOSED")
	stub.questLog[364].complete = true
	stub.playerMap.x, stub.playerMap.y = 0.308, 0.662
	stub.fire("QUEST_COMPLETE")
	stub.questLog[364] = nil stub.flagged[364] = true
	stub.fire("QUEST_TURNED_IN", 364, 450, 0)
	stub.slash("/lode record status")
	local r = G.db.char.recording
	local types = {}
	for _, e in ipairs(r.entries) do types[e.type] = (types[e.type] or 0) + 1 end
	check(types.accept == 1 and types.complete == 1 and types.turnin == 1 and types.level == 1 and types.hs == 1 and types.train == 1, "recorded all entry types")
	local text = G:BuildRecordingText(r)
	check(text:find("#guide Test route", 1, true) and text:find(".accept 364", 1, true) and text:find(".complete 364,1", 1, true) and text:find(".turnin 364", 1, true), "export text has the quest steps")
	check(text:find("mobs: Kobold Vermin x8", 1, true), "export text has mob levels: " .. tostring(text:match("mobs:[^\n]*")))
	check(text:find("%.hs Deathknell") and text:find("%.train"), "export has hs and train")
	local parsed, perr = G.Parser.Parse(text)
	check(parsed ~= nil, "exported guide parses back: " .. tostring(perr))
	stub.slash("/lode record export")
	check(G.guideByName["Test route"] ~= nil, "exported recording registered as a guide")
	check(LodestarCopyFrame.shown, "copy box shown for export")
	stub.slash("/lode record stop")
	stub.slash("/lode record list")
	stub.slash("/lode record show Test route")
	stub.slash("/lode record discard")
end)
try("engine sync + abandon", function()
	stub.level = 3
	-- fresh load with no saved progress: quests 363 + 364 done -> suggested start skips the first three steps
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = nil
	stub.flagged[363] = true stub.flagged[364] = true
	stub.questLog[364] = nil
	G:LoadGuide("Horde/Undead 1-5: Deathknell")
	check(G.stepIndex == 4, "suggested starting point skipped completed steps, at " .. tostring(G.stepIndex))
	-- turn-in grace: flag not yet set, event just fired -> still counts as turned in
	stub.fire("QUEST_TURNED_IN", 4444, 100, 0)
	check(G:IsActionComplete({ type = "turnin", questID = 4444 }), "recent turn-in counts before the flag lands")
	stub.advance(10)
	check(not G:IsActionComplete({ type = "turnin", questID = 4444 }), "turn-in grace expires")
	-- abandon 3901 (accepted at step 4) while at step 16 -> regress to step 4
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = false, objectives = {} }
	G:SetStep(16, true)
	stub.questLog[3901] = nil
	stub.fire("QUEST_REMOVED", 3901, false)
	check(G.stepIndex == 4, "abandon regressed to the accept step, at " .. tostring(G.stepIndex))
	-- vendor completes on close, not open
	G:LoadGuide("Horde/Undead 1-5: Deathknell", 1)
	stub.fire("MERCHANT_SHOW")
	check(not (G.stepFlags[G.stepIndex] and G.stepFlags[G.stepIndex].vendor), "vendor not complete while open")
	stub.fire("MERCHANT_CLOSED")
	check(G.stepFlags[G.stepIndex] and G.stepFlags[G.stepIndex].vendor, "vendor complete on close")
	stub.slash("/lode guide sync")
end)
try("smart mode", function()
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = false, objectives = { { text = "x: 0/8", finished = false } }, wp = { map = 18, x = 0.33, y = 0.66 } }
	stub.slash("/lode guide smart")
	check(G.current == nil, "guide unloaded")
	local items = G:CollectSmartItems(true)
	local kinds = {}
	for _, it in ipairs(items) do kinds[it.kind] = (kinds[it.kind] or 0) + 1 end
	check((kinds.available or 0) >= 1 and kinds.hub == 1 and (kinds.objective or 0) >= 1, "smart items include log, available and hub: " .. tostring(#items))
	stub.slash("/lode guide nextup")
	G:RetargetArrow()
	local t = G:GetArrowTarget()
	check(t and t.kind == "quest", "arrow follows smart target in smart mode")
	G:PinSmartItem(items[#items])
	check(G:GetArrowTarget() and G:GetArrowTarget().title == items[#items].title, "pinned item becomes the arrow target")
	G:RefreshStepFrame()
	check(LodestarGuideFrame.title.text and LodestarGuideFrame.title.text:find("smart mode"), "window shows smart mode")
	-- level 10 picks the 5-12 guide; level 20 has nothing and must not load an outleveled guide
	stub.level = 10
	check(G:PickGuide() and G:PickGuide().name == "Horde/Undead 5-12: Tirisfal Glades", "level 10 picks the Tirisfal guide")
	stub.level = 20
	check(G:PickGuide() == nil, "outleveled guides are not auto-picked")
	stub.level = 10
	stub.slash("/lode guide load Deathknell")
	stub.slash("/lode guide auto")
end)
try("vanilla data", function()
	wipe(G:HarvestDB().npcs) wipe(G:HarvestDB().quests)
	check(G.VanillaData and G.VanillaData.quests[3901] and G.VanillaData.quests[3901].t == "Rattling the Rattlecages", "Vanilla data loaded with quest 3901")
	local mapID, x, y, how = G:DataQuestPosition(3901, true)
	check(mapID == 18 and math.abs(x - 0.308) < 0.001 and math.abs(y - 0.662) < 0.001, "turn-in position for 3901 resolves to Sarvis via zone name: " .. tostring(mapID))
	check(how and how:find("Sarvis", 1, true), "turn-in subtitle names the NPC: " .. tostring(how))
	local omap = G:DataQuestPosition(3901, false)
	check(omap == 18, "objective position for 3901 (Rattlecage Skeleton) found")
	stub.level = 3
	stub.questLog = {}
	stub.flagged = { [363] = true }
	local items = {}
	G:DataAvailableItems(items, 18)
	local titles = {}
	for _, it in ipairs(items) do titles[it.title] = it end
	check(titles["The Damned"] ~= nil, "pick-up list offers The Damned at level 3 in Deathknell")
	check(titles["The Mindless Ones"] ~= nil, "pick-up list offers The Mindless Ones once Rude Awakening is flagged")
	check(titles["Rattling the Rattlecages"] == nil, "pick-up list withholds Rattling the Rattlecages until The Mindless Ones is done")
	check(titles["Simple Scroll"] == nil, "pick-up list hides other classes' scrolls")
	stub.slash("/lode quest 363")
	stub.slash("/lode quest rattl")
	stub.slash("/lode quest")
	-- smart mode with no client waypoint at all: data must still give the arrow a target
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = true, objectives = { { text = "Rattlecage Skeleton slain: 8/8", finished = true } } }
	stub.slash("/lode guide smart")
	local smart = G:CollectSmartItems(true)
	local lead = smart[1]
	check(lead and lead.questID == 3901 and lead.kind == "turnin" and lead.source == "data", "smart mode falls back to data for a turn-in: " .. tostring(lead and lead.source))
	G:PinSmartItem(nil)
	G:RetargetArrow()
	check(G:GetArrowTarget() and G:GetArrowTarget().questID == 3901, "arrow points at the data turn-in")
	stub.slash("/lode guide diag")
	check(LodestarProbeDB.guideDiag and LodestarProbeDB.guideDiag.quests[3901], "diag saved per-quest details")
	stub.slash("/lode guide next")
	stub.slash("/lode guide prev")
end)
try("harvest", function()
	local H = G:HarvestDB()
	check(H and H.npcs, "LodestarScanDB initialised")
	stub.fire("GOSSIP_SHOW")
	local npc = H.npcs[6]
	check(npc and npc.gives and npc.gives[6] and npc.ends and npc.ends[5], "gossip harvested offered/accepted quests for npc 6")
	check(npc.map == 18 and npc.exact, "interaction position stored as exact")
	stub.fire("QUEST_DETAIL")
	check(H.quests[7] and H.quests[7].giver == 6 and H.quests[7].xp and H.quests[7].xp[2] == 250, "quest detail recorded giver and reward xp")
	stub.fire("QUEST_COMPLETE")
	check(H.quests[7].ender == 6, "quest complete recorded ender")
	stub.fire("TAXIMAP_OPENED")
	check(H.taxi[10] and H.taxi[10].state == "current" and H.taxi[11] and H.taxi[11].state == "reachable" and H.taxi[10].links and H.taxi[10].links[11], "taxi nodes and links harvested")
	stub.fire("PLAYER_TARGET_CHANGED")
	check(H.npcs[6].minL == stub.level, "target level harvested")
	stub.fire("PLAYER_LEVEL_UP", 4)
	stub.advance(2)
	check(H.levels[stub.level] == stub.xpMax, "xp max per level harvested")
	-- census
	stub.slash("/lode scan quests 360 366")
	stub.advance(3)
	check(H.scan.found and H.scan.found >= 1 and H.quests[364] and H.quests[364].scanned, "quest scan found 364: " .. tostring(H.scan.found))
	check(H.scan.next and H.scan.next > 366, "scan ran to the end of the range")
	stub.slash("/lode scan status")
	stub.slash("/lode scan stop")
	stub.slash("/lode scan npc")
	stub.slash("/lode scan wipe")
	stub.slash("/lode scan rate 40")
	stub.slash("/lode scan")
	-- harvest read-back: a quest not in the vanilla data gets its position from the harvest
	stub.questLog[77777] = { title = "New Forever Quest", complete = true, objectives = {} }
	H.quests[77777] = { t = "New Forever Quest", ender = 6 }
	local hmap, _, _, how = G:HarvestQuestPosition(77777, true)
	check(hmap == 18 and how == "ender", "harvest gives a turn-in position for an unknown quest")
	local smart = G:CollectSmartItems(true)
	local found
	for _, it in ipairs(smart) do if it.questID == 77777 then found = it end end
	check(found and found.source and found.source:find("harvest", 1, true), "smart mode uses the harvest for new quests: " .. tostring(found and found.source))
	stub.questLog[77777] = nil
end)
try("trails", function()
	-- Until Guide.lua / the TOC wire them up, load the trail files and enable the recorder here.
	if not G.TrailPath then loadLua("Lodestar_Guide/Trails.lua") end
	if not G.TrailSeed then loadLua("Lodestar_Guide/Data/Trails_Seed.lua") end
	G:EnableTrails()
	local T = G:HarvestDB().trails
	check(type(T) == "table", "LodestarScanDB.trails created")
	local savedMap, savedX, savedY = stub.playerMap.map, stub.playerMap.x, stub.playerMap.y
	stub.playerMap.map = 18
	-- walk an L: 600 yd east, then 600 yd south, one 10 yd step per second (cells are 20 yd on the 10000 yd stub map)
	local function walk(x0, y0, dx, dy, steps)
		stub.playerMap.x, stub.playerMap.y = x0, y0
		stub.advance(1)
		for _ = 1, steps do
			stub.playerMap.x, stub.playerMap.y = stub.playerMap.x + dx, stub.playerMap.y + dy
			stub.advance(1)
		end
	end
	walk(0.200, 0.200, 0.001, 0, 60)
	walk(0.260, 0.200, 0, 0.001, 60)
	local s = G:TrailStats()
	check(T[18] and T[18].nx == 500 and T[18].ny == 500, "grid tuned to ~20 yd cells from the map size: " .. tostring(T[18] and T[18].nx))
	check(s.mapCells >= 60 and s.mapCells <= 64, "L walk recorded ~61 cells, got " .. s.mapCells)
	check(s.mapLinks >= 59 and s.mapLinks <= 63, "L walk recorded ~60 links, got " .. s.mapLinks)
	check(s.mapBytes < 3000, "L walk costs under 3 KB, got " .. s.mapBytes)
	-- teleport: a jump of many cells marks the new cell but links nothing
	local links = T[18].l
	stub.playerMap.x, stub.playerMap.y = 0.400, 0.400
	stub.advance(1)
	check(T[18].l == links, "teleport did not create a link")
	-- dead / taxi / recording off: nothing recorded
	local cells = T[18].n
	stub.dead = true walk(0.500, 0.500, 0.001, 0, 4) stub.dead = false
	local onTaxi = UnitOnTaxi
	UnitOnTaxi = function() return true end walk(0.520, 0.500, 0.001, 0, 4) UnitOnTaxi = onTaxi
	stub.slash("/lode trails off")
	walk(0.540, 0.500, 0.001, 0, 4)
	stub.slash("/lode trails on")
	check(T[18].n == cells, "dead, on taxi or recording off: no cells recorded, got +" .. (T[18].n - cells))
	-- path query: end to end of the L goes via the corner, string-pulled to start / corner / goal
	local path = G:TrailPath(18, 0.200, 0.200, 0.260, 0.260)
	check(path and #path == 3, "L path found and string-pulled to 3 nodes, got " .. tostring(path and #path))
	check(path and math.abs(path[2].x - 0.261) < 0.005 and math.abs(path[2].y - 0.201) < 0.005, "middle node is the corner (within a cell or two): " .. tostring(path and path[2].x) .. "," .. tostring(path and path[2].y))
	check(path and path[3].x == 0.260 and path[3].y == 0.260 and path[3].rest == 0, "last node is the exact goal")
	check(path and math.abs(path[1].rest - 1200) < 40, "path length ~1200 yd, got " .. tostring(path and path[1].rest))
	check(G:TrailPath(18, 0.200, 0.200, 0.260, 0.260) == path, "repeated query served from the cache")
	check(G:TrailPath(18, 0.200, 0.200, 0.300, 0.300) == nil, "no path to a point off the trail")
	check(G:TrailPath(18, 0.200, 0.200, 0.262, 0.262) ~= nil, "a goal one cell off the trail is still reachable")
	-- arrow: from the start with the far end as target, it points at the corner (east), not diagonally
	stub.playerMap.x, stub.playerMap.y = 0.200, 0.200
	local rotation
	LodestarArrow.arrow.SetRotation = function(_, r) rotation = r end
	stub.waypoint = { uiMapID = 18, position = { x = 0.260, y = 0.260 } }
	stub.slash("/lode arrow waypoint")
	G:RetargetArrow()
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	local toCorner, toGoal = -math.pi / 2, math.atan2(-600, -600) -- world bearing: east is -pi/2, the goal is south-east
	check(rotation and math.abs(rotation - toCorner) < 0.1, "arrow points east at the corner node, not diagonally: " .. tostring(rotation))
	check((LodestarArrow.dist.text or ""):find("848 yd", 1, true) and LodestarArrow.dist.text:find("via trail %(1%d%d%d yd%)"), "distance line shows the real distance and the trail length: " .. tostring(LodestarArrow.dist.text))
	-- follow toggle off: straight line again
	stub.slash("/lode trails follow off")
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	check(math.abs(rotation - toGoal) < 0.05 and not LodestarArrow.dist.text:find("via trail", 1, true), "follow off: straight line")
	stub.slash("/lode trails follow on")
	-- no trail near the player or target: straight-line fallback
	stub.playerMap.x, stub.playerMap.y = 0.100, 0.900
	stub.waypoint = { uiMapID = 18, position = { x = 0.150, y = 0.950 } }
	G:RetargetArrow()
	stub.advance(1.1)
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	check(math.abs(rotation - toGoal) < 0.05 and not LodestarArrow.dist.text:find("via trail", 1, true), "no trail: straight line, " .. tostring(LodestarArrow.dist.text))
	-- seeded roads: Deathknell -> Brill is routable on the 0.4 % seed resampled onto the 20 yd grid
	local seed = G:TrailSeedFor(18)
	check(seed and seed.n > 300, "Tirisfal seed resampled: " .. tostring(seed and seed.n) .. " cells")
	local road = G:TrailPath(18, 0.308, 0.662, 0.610, 0.525)
	check(road and #road >= 3 and road[1].rest > 3000, "seeded road Deathknell -> Brill routes: " .. tostring(road and #road) .. " nodes, " .. tostring(road and math.floor(road[1].rest)) .. " yd")
	-- explicit step waypoints: walked point by point, 12 yd arrival, then the step's own goto
	stub.playerMap.x, stub.playerMap.y = 0.200, 0.200
	stub.slash("/lode guide load Deathknell")
	local step = G:CurrentStep()
	check(step and step.go, "guide step with a goto is current")
	step.path = { { x = 21, y = 20 }, { 22, 20 } }
	stub.slash("/lode arrow guide")
	G:RetargetArrow()
	local t = G:GetArrowTarget()
	check(t and t.waypoint == 1 and math.abs(t.x - 0.21) < 1e-9, "arrow targets waypoint 1: " .. tostring(t and t.waypoint))
	stub.playerMap.x = 0.210
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	t = G:GetArrowTarget()
	check(t and t.waypoint == 2 and math.abs(t.x - 0.22) < 1e-9, "reaching waypoint 1 moves on to waypoint 2: " .. tostring(t and t.waypoint))
	stub.playerMap.x = 0.220
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	t = G:GetArrowTarget()
	check(t and not t.waypoint and math.abs(t.x - step.go.x / 100) < 1e-9, "after the last waypoint the step's goto is the target")
	step.path = nil
	-- slash + wipe
	stub.slash("/lode trails")
	stub.slash("/lode trails wipe")
	check(T[18] ~= nil, "wipe without confirm keeps the data")
	stub.slash("/lode trails wipe confirm")
	check(next(T) == nil and G:TrailStats().cells == 0, "wipe confirm empties the store")
	stub.slash("/lode trails nonsense")
	-- restore
	LodestarArrow.arrow.SetRotation = nil
	stub.slash("/way clear")
	stub.slash("/lode arrow auto")
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = savedMap, savedX, savedY
end)
try("guide menus", function() G:ShowGuideMenu() G:ShowArrowMenu() end)
try("guide options", function()
	local opts = Lodestar:BuildOptions()
	check(opts.args.Guide ~= nil, "guide options group present")
	local function walk(group)
		for _, opt in pairs(group.args or {}) do
			if opt.type == "group" then walk(opt)
			elseif opt.get then
				local v = opt.get({})
				if opt.set and (opt.type == "toggle" or opt.type == "range" or opt.type == "select") then opt.set({}, v) end
			elseif opt.type == "description" and type(opt.name) == "function" then opt.name() end
		end
	end
	walk(opts.args.Guide)
end)

-- AceDB strips defaults from the saved tables on logout, so this must be the last thing we do.
try("logout", function() stub.fire("PLAYER_LOGOUT") end)

-- Report
print(("smoke: %d checks, %d failures"):format(checks, #failures))
for _, f in ipairs(failures) do print("  FAIL " .. f) end
local unknown = {}
for k, n in pairs(stub.unknownGlobals) do tinsert(unknown, k .. "(" .. n .. ")") end
table.sort(unknown)
if #unknown > 0 then print("unknown globals touched: " .. table.concat(unknown, " ")) end
if #failures > 0 then os.exit(1) end

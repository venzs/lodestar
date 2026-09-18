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
-- Data/Trainers.lua belongs in the Guide TOC after Data/Vanilla.lua; load it here while that line is pending.
if not _G.Lodestar:GetModule("Guide").TrainerData then loadLua("Lodestar_Guide/Data/Trainers.lua") end

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
-- Guide DSL: buy / optional / path / profession / camp / cook / item / train <name>
try("dsl parse", function()
	local P = G.Parser
	local g, err = P.Parse([[
#guide Test: DSL
#levels 1-60
step
  .goto 18,61.0,52.4
  .buy 2320,2 >>Buy two Coarse Thread
step
  .buy 2320
step
  .optional >>Skip on a speed run
  .path 30.8,66.2;31.0,65.5;32.7,65.6
  .accept 590
step
  .profession Skinning,Herbalism
step
  .camp
  .cook
step
  .train Shan Stillwell
  .class Paladin
step
  .item 6948
  .complete 6395
step
  .optional
  .camp >>Camp by the inn
]])
	check(g, "dsl guide parsed: " .. tostring(err))
	if not g then return end
	local s = g.steps
	check(s[1].actions[1].type == "buy" and s[1].actions[1].itemID == 2320 and s[1].actions[1].count == 2 and s[1].actions[1].text == "Buy two Coarse Thread", "buy with count and text")
	check(s[2].actions[1].type == "buy" and s[2].actions[1].count == 1, "buy defaults to one")
	check(P.StepText(s[2]) == "Buy item #2320", "buy text before the item name loads: " .. P.StepText(s[2]))
	check(P.StepText(s[2], nil, nil, nil, function(id) return "Coarse Thread" end) == "Buy Coarse Thread", "buy text with the item name")
	check(P.StepText(s[1], nil, nil, nil, function(id) return "Coarse Thread" end) == "Buy two Coarse Thread", "buy keeps >> text")
	check(s[3].optional == true and s[3].optionalReason == "Skip on a speed run", "optional with reason")
	check(s[3].path and #s[3].path == 3 and s[3].path[2].x == 31.0 and s[3].path[3].y == 65.6, "path points parsed")
	check(s[3].actions[1].type == "accept" and s[3].actions[1].questID == 590, "optional step keeps its actions")
	check(s[4].actions[1].type == "profession" and s[4].actions[1].names[2] == "Herbalism", "profession names parsed")
	check(P.StepText(s[4]) == "Train Skinning and Herbalism", "profession text: " .. P.StepText(s[4]))
	check(s[5].actions[1].type == "camp" and s[5].actions[2].type == "cook", "camp and cook parsed")
	check(P.StepText(s[5]) == "Set up camp / use a campfire · Cook food for the XP buff", "camp/cook default text: " .. P.StepText(s[5]))
	check(s[6].actions[1].type == "train" and s[6].actions[1].name == "Shan Stillwell" and s[6].classes.paladin, "train with a trainer name")
	check(P.StepText(s[6]) == "Train new skills at Shan Stillwell", "train text names the trainer: " .. P.StepText(s[6]))
	check(s[7].requireItems and s[7].requireItems[1] == 6948, "item filter parsed")
	check(s[8].optional and s[8].optionalReason == nil and s[8].actions[1].text == "Camp by the inn", "bare optional")
	check(P.StepApplies(s[3], "warrior", "undead", false) == false and P.StepApplies(s[3], "warrior", "undead", true) == true, "Parser.StepApplies honours completionist")
	check(P.StepApplies(s[7], "warrior", "undead", false, function() return false end) == false and P.StepApplies(s[7], "warrior", "undead", false, function() return true end), "Parser.StepApplies honours item filters")
	local bad, berr = P.Parse("#guide X\nstep\n  .buy")
	check(bad == nil and berr and berr:find("buy needs an item id"), "buy without an id rejected: " .. tostring(berr))
	bad, berr = P.Parse("#guide X\nstep\n  .path 1;2")
	check(bad == nil and berr and berr:find("path points"), "bad path rejected: " .. tostring(berr))
	bad, berr = P.Parse("#guide X\nstep\n  .profession")
	check(bad == nil and berr and berr:find("profession needs"), "profession without a name rejected")
	-- the shipped Horde guide uses the new directives and still parses
	local tirisfal = G.guideByName["Horde/Undead 5-12: Tirisfal Glades"]
	local kinds = {}
	for _, st in ipairs(tirisfal.steps) do
		if st.optional then kinds.optional = (kinds.optional or 0) + 1 end
		for _, a in ipairs(st.actions) do kinds[a.type] = (kinds[a.type] or 0) + 1 end
	end
	check((kinds.optional or 0) >= 14 and kinds.buy == 1 and kinds.profession == 2 and kinds.camp == 1 and kinds.cook == 1 and kinds.train >= 7, "Tirisfal guide carries buy/optional/profession/camp/cook/train steps: " .. tostring(kinds.optional))
end)
try("dsl engine", function()
	stub.level = 10
	stub.itemCounts = {}
	stub.professions = {}
	G.db.profile.steps.completionist = false
	local g = G:RegisterGuide([[
#guide Test: DSL engine
#levels 1-60
step
  .buy 2320,2 >>Buy two Coarse Thread
step
  .optional >>Skip on a speed run
  .camp
step
  .profession Skinning
step
  .item 777
  .text >>Use the thing you looted
step
  .cook
step
  .text >>Done
]], "smoke")
	check(g ~= nil, "engine guide registered")
	G.db.char.progress["Test: DSL engine"] = nil
	G:LoadGuide("Test: DSL engine", 1)
	check(G.stepIndex == 1, "buy step waits while the bag is empty, at " .. tostring(G.stepIndex))
	check(G:StepText(G:CurrentStep()) == "Buy two Coarse Thread", "buy step text")
	stub.itemCounts[2320] = 1
	stub.fire("BAG_UPDATE_DELAYED")
	stub.advance(1)
	check(G.stepIndex == 1, "one of two is not enough")
	stub.itemCounts[2320] = 2
	stub.fire("BAG_UPDATE_DELAYED")
	stub.advance(1)
	-- speed run: the optional camp step (2) is skipped; the profession step (3) waits
	check(G.stepIndex == 3, "buy complete, optional step skipped in speed-run mode, at " .. tostring(G.stepIndex))
	check(not G:IsActionComplete({ type = "profession", names = { "Skinning" } }, nil), "profession not known yet")
	stub.professions = { "Skinning" }
	stub.fire("SKILL_LINES_CHANGED")
	stub.advance(1)
	-- .item 777 filter: no item -> step 4 skipped; cook (5) is manual
	check(G.stepIndex == 5, "profession learned, item-gated step skipped, at cook step: " .. tostring(G.stepIndex))
	check(G:StepText(G:CurrentStep()) == "Cook food for the XP buff", "cook default text")
	G:NextStep()
	check(G.stepIndex == 6, "cook is manual (Next)")
	-- with the item, the .item step applies
	stub.itemCounts[777] = 1
	G:SetStep(4, true) G:EvaluateStep()
	check(G.stepIndex == 4, "item-gated step shown once the item is in the bag, at " .. tostring(G.stepIndex))
	stub.itemCounts[777] = nil
	-- completionist: the optional step is shown and tagged
	G:SetCompletionist(true)
	check(G.db.profile.steps.completionist == true, "completionist on")
	G:SetStep(2, true) G:EvaluateStep()
	check(G.stepIndex == 2, "optional step shown in completionist mode, at " .. tostring(G.stepIndex))
	G:RefreshStepFrame()
	check(LodestarGuideFrame.step.text and LodestarGuideFrame.step.text:find("(optional)", 1, true), "window tags the optional step: " .. tostring(LodestarGuideFrame.step.text))
	G:SetCompletionist(false)
	G:SetStep(1, true) G:EvaluateStep()
	check(G.stepIndex == 6, "speed run skips the optional step again (buy, profession done; item step gated), at " .. tostring(G.stepIndex))
	-- upcoming rows leave out steps that do not apply (optional in speed-run mode, item-gated without the item)
	local function upcomingTexts()
		local texts = {}
		for _, f in ipairs(stub.frames) do
			if f.parent == LodestarGuideFrame and f.kind == "Button" and f.hl and f.shown and f.text.text ~= "" then tinsert(texts, f.text.text) end
		end
		return texts
	end
	G.db.profile.steps.upcoming = 3
	G:SetStep(1, true)
	G:RefreshStepFrame()
	local rows = upcomingTexts()
	check(#rows == 3 and rows[1]:find("^3%. Train Skinning") and rows[2]:find("^5%. Cook") and rows[3]:find("^6%. Done"), "speed-run upcoming rows skip optional and item-gated steps: " .. table.concat(rows, " | "))
	G:SetCompletionist(true)
	G:SetStep(1, true)
	G:RefreshStepFrame()
	rows = upcomingTexts()
	check(#rows == 3 and rows[1]:find("^2%. Set up camp") and rows[1]:find("(optional)", 1, true) and rows[2]:find("^3%."), "completionist upcoming rows include the tagged optional step: " .. table.concat(rows, " | "))
	G:SetCompletionist(false)
	stub.slash("/lode guide completionist on")
	check(G.db.profile.steps.completionist == true, "/lode guide completionist on")
	stub.slash("/lode guide completionist off")
	check(G.db.profile.steps.completionist == false, "/lode guide completionist off")
	stub.slash("/lode guide completionist")
	check(G.db.profile.steps.completionist == true, "/lode guide completionist toggles")
	G:SetCompletionist(false)
end)
try("dsl menu", function()
	-- the right-click menu carries a Completionist checkbox that flips the profile flag
	local realMenu = MenuUtil.CreateContextMenu
	local boxes = {}
	MenuUtil.CreateContextMenu = function(_, gen)
		local root = { CreateTitle = function() end, CreateDivider = function() end, CreateButton = function() end, CreateRadio = function() end,
			CreateCheckbox = function(_, label, isSelected, toggle) boxes[label] = { isSelected = isSelected, toggle = toggle } end }
		gen(nil, root)
	end
	G:ShowGuideMenu()
	MenuUtil.CreateContextMenu = realMenu
	local box = boxes["Completionist (do optional quests)"]
	check(box ~= nil, "guide menu has the completionist checkbox")
	if not box then return end
	check(box.isSelected() == false, "checkbox reflects speed-run mode")
	box.toggle()
	check(G.db.profile.steps.completionist == true and box.isSelected() == true, "checkbox toggles completionist on")
	box.toggle()
	check(G.db.profile.steps.completionist == false, "checkbox toggles completionist off")
end)
try("class trainers", function()
	check(G.TrainerData and G.TrainerData.WARRIOR and G.TrainerData.PALADIN and G.TrainerData.DRUID, "trainer data loaded for the classes")
	local n = 0
	for _ in pairs(G.TrainerData) do n = n + 1 end
	check(n == 9, "nine classes in the trainer data, got " .. n)
	for cls, ids in pairs(G.TrainerData) do
		for _, id in ipairs(ids) do
			check(G.VanillaData.npcs[id] ~= nil, cls .. " trainer #" .. id .. " exists in the Vanilla data")
		end
	end
	check(G.SpellLevels.WARRIOR[4] and G.SpellLevels.WARRIOR[30] and not G.SpellLevels.WARRIOR[5], "spell levels: even levels 4-30")
	local mapID, _, _, name, dist, npcID = G:DataNearestNPC({ 2119 })
	check(mapID == 18 and name == "Dannal Stern" and npcID == 2119 and dist and dist < 300, "DataNearestNPC finds Dannal Stern near Deathknell: " .. tostring(dist))
	-- suggestion: a level 3 warrior has nothing to train; at 4 the Deathknell trainer is suggested
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.308, 0.662
	G.db.char.lastTrainedLevel = nil
	stub.level = 3
	check(G:TrainerSuggestion(true) == nil, "no trainer suggestion at level 3")
	stub.level = 4
	local t = G:TrainerSuggestion(true)
	check(t and t.npcID == 2119 and t.name == "Dannal Stern" and t.level == 4 and t.mapID == 18, "level 4 warrior: Dannal Stern suggested: " .. tostring(t and t.name))
	check(t and t.dist and t.dist > 100 and t.dist < 300, "trainer distance in range: " .. tostring(t and t.dist))
	-- guided mode banner
	G:LoadGuide("Horde/Undead 1-5: Deathknell", 1)
	G:RefreshStepFrame()
	check(LodestarGuideFrame.banner.text and LodestarGuideFrame.banner.text:find("Dannal Stern", 1, true) and LodestarGuideFrame.banner.text:find("New spells", 1, true), "window banner names the trainer: " .. tostring(LodestarGuideFrame.banner.text))
	-- smart mode list item
	stub.slash("/lode guide smart")
	local items = G:CollectSmartItems(true)
	local trainItem
	for _, it in ipairs(items) do if it.kind == "train" then trainItem = it end end
	check(trainItem and trainItem.npcID == 2119 and trainItem.title:find("Dannal Stern", 1, true), "smart mode lists the trainer: " .. tostring(trainItem and trainItem.title))
	G:RefreshStepFrame()
	-- recompute is throttled to 5 s
	stub.level = 3
	check(G:TrainerSuggestion() ~= nil, "cached suggestion within 5 s")
	stub.advance(6)
	check(G:TrainerSuggestion() == nil, "recomputed after 5 s")
	stub.level = 4
	-- a class trainer visit at level 4 clears the suggestion; the harvest entry is tagged with the class
	stub.tradeskillTrainer = false
	stub.fire("TRAINER_SHOW") stub.fire("TRAINER_CLOSED")
	check(G.db.char.lastTrainedLevel == 4, "lastTrainedLevel recorded from the trainer window: " .. tostring(G.db.char.lastTrainedLevel))
	check(G:HarvestDB().npcs[6] and G:HarvestDB().npcs[6].trains == "WARRIOR" and G:HarvestDB().npcs[6].kind.trainer, "harvested trainer tagged with the class")
	check(G:TrainerSuggestion(true) == nil, "no suggestion right after training")
	stub.level = 5
	check(G:TrainerSuggestion(true) == nil, "level 5 has no new spells")
	stub.level = 6
	t = G:TrainerSuggestion(true)
	check(t and t.npcID == 6 and t.dist == 0, "level 6: the harvested trainer standing here wins by distance: " .. tostring(t and t.npcID))
	-- a tradeskill trainer window does not count as class training
	stub.tradeskillTrainer = true
	stub.fire("TRAINER_SHOW") stub.fire("TRAINER_CLOSED")
	stub.tradeskillTrainer = false
	check(G.db.char.lastTrainedLevel == 4, "profession trainer visit leaves lastTrainedLevel alone")
	G:HarvestDB().npcs[6].trains = nil G:HarvestDB().npcs[6].kind.trainer = nil
	t = G:TrainerSuggestion(true)
	check(t and t.npcID == 2119, "back to the data trainer once the harvest entry is untagged")
	-- far away: nothing within 300 yd
	stub.playerMap.x, stub.playerMap.y = 0.60, 0.50
	check(G:TrainerSuggestion(true) == nil, "no suggestion when the nearest trainer is out of range")
	stub.playerMap.x, stub.playerMap.y = 0.308, 0.662
	stub.slash("/lode guide train")
	stub.fire("TRAINER_SHOW") stub.fire("TRAINER_CLOSED")
	stub.slash("/lode guide train")
	G:HarvestDB().npcs[6].trains = nil G:HarvestDB().npcs[6].kind.trainer = nil
	-- class quests are tagged in the pick-up list (Simple Scroll is a warrior quest after The Mindless Ones)
	stub.level = 3
	stub.flagged = { [363] = true, [364] = true }
	stub.questLog = {}
	local found = {}
	G:DataAvailableItems(found, 18)
	local scroll, rogueScroll
	for _, it in ipairs(found) do
		if it.title == "Simple Scroll" then scroll = it end
		if it.title == "Encrypted Scroll" then rogueScroll = it end
	end
	check(scroll and scroll.classQuest == true and scroll.subtitle:find("^Class quest · Pick up from Shadow Priest Sarvis"), "warrior class quest tagged: " .. tostring(scroll and scroll.subtitle))
	check(rogueScroll == nil, "other classes' scrolls still hidden by the class mask")
	stub.level = 10
	stub.slash("/lode guide auto")
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

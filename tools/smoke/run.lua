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

local addons = { "Lodestar", "Lodestar_Leveling", "Lodestar_Economy", "Lodestar_UI", "Lodestar_Guild", "Lodestar_Guide", "Lodestar_Guides_Horde", "Lodestar_Guides_Alliance", "Lodestar_Character" }
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
check(#Lodestar.moduleList == 6, "six modules registered, got " .. tostring(#Lodestar.moduleList))
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

-- Comm fallback
-- The Forever beta restricts outgoing addon messages realm-wide: nothing is sent or queued, the
-- heartbeat stays off, the board is roster-only and /lode lfg drafts a guild chat line for the player.
try("comm fallback", function()
	local G = Lodestar:GetModule("Guild")
	check(Lodestar:CanSendComm() and Lodestar.commAvailable == true, "comms available by default")
	check(G.heartbeat ~= nil, "heartbeat running while comms are available")
	stub.commRestricted = true
	check(not Lodestar:CanSendComm(), "restricted realm: CanSendComm false")
	local before = #stub.sent
	check(Lodestar:SendComm({ t = "V" }, "GUILD") == false and #stub.sent == before, "SendComm refuses without queueing")
	Lodestar:BroadcastVersion()
	check(#stub.sent == before, "BroadcastVersion is a silent no-op")
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, true)
	check(Lodestar.commAvailable == false, "core noticed the restriction")
	check(G.heartbeat == nil, "heartbeat stopped when comms went away")
	stub.advance(301) -- a full heartbeat interval
	check(#stub.sent == before, "nothing sent while restricted")
	G:RestartHeartbeat()
	check(G.heartbeat == nil, "changing the interval does not start the heartbeat while restricted")
	G:Broadcast(true) G:Query()
	check(#stub.sent == before, "explicit broadcast/query send nothing while restricted")
	-- /lode lfg: drafted into the chat box with the /g prefix, never sent
	stub.openChat = nil
	stub.slash("/lode lfg Deadmines tank")
	check(stub.openChat == "/g LFG: Deadmines tank", "lfg drafted into the chat box: " .. tostring(stub.openChat))
	check(#stub.sent == before, "lfg sent nothing")
	check(G.db.char.lfgNote == "Deadmines tank", "note kept for when comms return")
	check((stub.chat[#stub.chat] or ""):find("press Enter", 1, true), "user told to send it themselves")
	-- board: roster only, notice shown, summary without the Lodestar count
	stub.slash("/lode guild")
	check(LodestarGuildBoard.shown, "board opens while restricted")
	check(LodestarGuildBoard.notice.shown == true, "restriction notice shown")
	check(LodestarGuildBoard.notice.text == "Addon messages are restricted on this realm — showing the guild roster only", "notice wording")
	check(LodestarGuildBoard.summary.text and not LodestarGuildBoard.summary.text:find("running Lodestar", 1, true), "summary drops the Lodestar count: " .. tostring(LodestarGuildBoard.summary.text))
	check((LodestarGuildBoard.hint.text or ""):find("drafts a guild chat line", 1, true), "hint explains the lfg fallback")
	local rows = G:CollectRows()
	local fromRoster = false
	for _, r in ipairs(rows) do if r.rank then fromRoster = true end end
	check(#rows >= 1 and fromRoster, "roster rows still listed")
	stub.slash("/lode guild")
	-- minimap tooltip line
	local lines = {}
	local tt = { AddDoubleLine = function(_, l, r) lines[l] = r end, AddLine = function() end }
	for _, fn in ipairs(Lodestar.tooltipProviders) do fn(tt) end
	check(lines["Guild board"] and lines["Guild board"]:find("restricted", 1, true), "minimap tooltip says roster only: " .. tostring(lines["Guild board"]))
	check(lines["Guildmates with Lodestar"] == nil, "presence count not shown while restricted")
	-- comms come back (a launch realm without the restriction): announce + query, heartbeat on
	stub.commRestricted = false
	before = #stub.sent
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, false)
	check(Lodestar.commAvailable == true, "core noticed comms are back")
	check(G.heartbeat ~= nil, "heartbeat restarted")
	stub.advance(3)
	check(#stub.sent == before + 2, "announced and queried when comms came back, sent " .. (#stub.sent - before))
	local kinds = {}
	for i = before + 1, #stub.sent do
		local s = stub.sent[i]
		if s.dist == "GUILD" then kinds[s.msg:match("%^St%^S(%a)") or "?"] = s.msg end
	end
	check(kinds.P and kinds.Q, "presence and query both went to the guild")
	check(kinds.P and kinds.P:find("Deadmines", 1, true) ~= nil, "the kept note rides along in the presence") -- AceSerializer escapes the space
	-- same event again with no change: no second announce
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, false)
	stub.advance(3)
	check(#stub.sent == before + 2, "unchanged state does not re-announce")
	-- lfg broadcasts again instead of drafting
	before = #stub.sent
	stub.openChat = nil
	stub.slash("/lode lfg clear")
	check(stub.openChat == nil and #stub.sent == before + 1 and G.db.char.lfgNote == nil, "lfg clear broadcasts again once comms are available")
	stub.slash("/lode guild")
	check(LodestarGuildBoard.notice.shown == false, "notice hidden once comms are back")
	check((LodestarGuildBoard.summary.text or ""):find("running Lodestar", 1, true), "summary shows the Lodestar count again")
	stub.slash("/lode guild")
	lines = {}
	for _, fn in ipairs(Lodestar.tooltipProviders) do fn(tt) end
	check(lines["Guildmates with Lodestar"] ~= nil and lines["Guild board"] == nil, "minimap tooltip back to the presence count")
end)

-- Status strip
-- Second line under the XP readout: bags / durability / rested / resting / watched buffs, with the
-- bag-space and repair nags throttled to one chat line per five minutes each.
try("status strip", function()
	local Lv = Lodestar:GetModule("Leveling")
	stub.level, stub.xp, stub.xpMax, stub.rested = 13, 100, 12000, 500
	Lv:UpdateXPFrame()
	Lv:RefreshStrip()
	check(LodestarXPFrame.strip.shown == true, "strip line shown by default")
	local text = LodestarXPFrame.strip.text or ""
	check(text:find("bags |cffffffff3|r free", 1, true) ~= nil, "bags part: " .. text)
	check(text:find("dur |cffffffff62%|r", 1, true) ~= nil, "durability part is the lowest slot: " .. text)
	check(text:find("rested |cff6b9eff4%|r", 1, true) ~= nil, "rested part as % of level: " .. text)
	check(text:find("Resting", 1, true) ~= nil, "resting state shown")
	check(text:find("|cff7fff7fWell Fed|r", 1, true) ~= nil, "watched buff shown")
	local state = Lv:GetStripState()
	check(state.bags == 3 and math.floor(state.durability) == 62 and state.resting and state.buffs[1] == "Well Fed", "strip state exposed")
	-- events coalesce into one refresh per second; other units' auras are ignored
	stub.auras = {}
	stub.fire("UNIT_AURA", "player")
	stub.fire("UNIT_AURA", "player")
	check((LodestarXPFrame.strip.text or ""):find("Well Fed", 1, true) ~= nil, "no refresh before the throttle interval")
	stub.advance(1)
	check((LodestarXPFrame.strip.text or ""):find("Well Fed", 1, true) == nil, "buff gone after the throttled refresh")
	stub.auras = { "Well Fed" }
	stub.fire("UNIT_AURA", "target")
	stub.advance(1)
	check((LodestarXPFrame.strip.text or ""):find("Well Fed", 1, true) == nil, "another unit's UNIT_AURA does not refresh")
	-- bag nag: once, throttled, again after five minutes, red when full
	local bagNags = countChat("Bags: only")
	stub.bagFree[0] = 2
	stub.fire("BAG_UPDATE_DELAYED")
	stub.advance(1)
	check(countChat("Bags: only 2 slots free") == bagNags + 1, "bag nag printed at 2 free")
	check((LodestarXPFrame.strip.text or ""):find("bags |cffff9933" , 1, true) ~= nil, "bags part orange: " .. tostring(LodestarXPFrame.strip.text))
	stub.fire("BAG_UPDATE_DELAYED") stub.advance(1)
	check(countChat("Bags: only") == bagNags + 1, "bag nag throttled")
	stub.advance(300)
	stub.fire("BAG_UPDATE_DELAYED") stub.advance(1)
	check(countChat("Bags: only") == bagNags + 2, "bag nag repeats after 5 minutes")
	stub.bagFree[0] = 0
	stub.fire("BAG_UPDATE_DELAYED") stub.advance(1)
	check((LodestarXPFrame.strip.text or ""):find("bags |cffff4040" , 1, true) ~= nil, "full bags red")
	-- durability nag
	local durNags = countChat("Durability at")
	stub.durability[1] = { 15, 100 }
	stub.fire("UPDATE_INVENTORY_DURABILITY") stub.advance(1)
	check(countChat("Durability at 15%%") == durNags + 1, "durability nag printed at 15%")
	check((LodestarXPFrame.strip.text or ""):find("dur |cffff9933" , 1, true) ~= nil, "durability part orange")
	stub.durability[1] = { 5, 100 }
	stub.fire("UPDATE_INVENTORY_DURABILITY") stub.advance(1)
	check(countChat("Durability at") == durNags + 1, "durability nag throttled")
	check((LodestarXPFrame.strip.text or ""):find("dur |cffff4040", 1, true) ~= nil, "durability red at 5%")
	-- both toggles off: nothing printed even after the interval
	Lv.db.profile.xp.strip.nagBags = false
	Lv.db.profile.xp.strip.nagDurability = false
	stub.advance(300)
	stub.fire("BAG_UPDATE_DELAYED") stub.fire("UPDATE_INVENTORY_DURABILITY") stub.advance(1)
	check(countChat("Bags: only") == bagNags + 2 and countChat("Durability at") == durNags + 1, "nags off: nothing printed")
	Lv.db.profile.xp.strip.nagBags = true
	Lv.db.profile.xp.strip.nagDurability = true
	-- rested / resting events reach the strip too
	stub.rested = 0
	stub.fire("UPDATE_EXHAUSTION") stub.advance(1)
	check((LodestarXPFrame.strip.text or ""):find("rested ", 1, true) == nil, "rested part dropped at 0")
	IsResting = function() return false end
	stub.fire("PLAYER_UPDATE_RESTING") stub.advance(1)
	check((LodestarXPFrame.strip.text or ""):find("Resting", 1, true) == nil, "resting part dropped when not resting")
	IsResting = function() return true end
	stub.rested = 500
	-- configurable buff list, case-insensitive, in the configured order
	Lv.db.profile.xp.strip.buffs = "sharpened blade, WELL FED"
	stub.auras = { "Well Fed", "Sharpened Blade", "Blessing of Might" }
	Lv:RefreshStrip()
	text = LodestarXPFrame.strip.text or ""
	check(text:find("sharpened blade|r  |cff666666·|r  |cff7fff7fWELL FED", 1, true) ~= nil and text:find("Blessing", 1, true) == nil, "buff list configurable and ordered: " .. text)
	-- index walk when AuraUtil is missing
	local au = AuraUtil
	AuraUtil = false -- absent (false keeps the stub's unknown-global tally clean)
	Lv:RefreshStrip()
	check((LodestarXPFrame.strip.text or ""):find("WELL FED", 1, true) ~= nil, "buff found through C_UnitAuras.GetAuraDataByIndex")
	AuraUtil = au
	Lv.db.profile.xp.strip.buffs = "Well Fed"
	-- strip off: single line again, nags still run
	Lv.db.profile.xp.strip.show = false
	Lv:UpdateXPFrame()
	check(LodestarXPFrame.strip.shown == false, "strip hidden by option")
	Lv.db.profile.xp.strip.show = true
	Lv:UpdateXPFrame()
	-- restore
	stub.bagFree[0] = 3
	stub.durability[1] = { 62, 100 }
	stub.auras = { "Well Fed" }
	Lv:RefreshStrip()
end)

-- Turn-ins to ding
-- Reward XP of quests ready to turn in, summed through SetSelectedQuest + GetQuestLogRewardXP,
-- with "(ding!)" once the sum covers the rest of the level.
try("turn-ins to ding", function()
	local Lv = Lodestar:GetModule("Leveling")
	local savedLog = stub.questLog
	stub.level, stub.xp, stub.xpMax = 13, 100, 12000
	stub.questLog = {
		[501] = { title = "Done A", complete = true, objectives = {}, xp = 800 },
		[502] = { title = "Done B", complete = true, objectives = {}, xp = 440 },
		[503] = { title = "Not yet", complete = false, objectives = {}, xp = 5000 },
	}
	stub.selectedQuest = 503
	local scanned = false
	local realSet = C_QuestLog.SetSelectedQuest
	C_QuestLog.SetSelectedQuest = function(id) scanned = true stub.selectedQuest = id end
	stub.fire("QUEST_LOG_UPDATE")
	stub.fire("QUEST_LOG_UPDATE")
	check(not scanned, "scan waits for the 1 s throttle")
	stub.advance(1)
	C_QuestLog.SetSelectedQuest = realSet
	local xp, count = Lv:GetTurnInXP()
	check(scanned and xp == 1240 and count == 2, "two ready quests summed: " .. tostring(xp) .. " xp / " .. tostring(count))
	check(stub.selectedQuest == 503, "previous quest selection restored, got " .. tostring(stub.selectedQuest))
	-- same set of ready quests: no re-selection (a SetSelectedQuest -> QUEST_LOG_UPDATE echo must not loop)
	local selections = 0
	C_QuestLog.SetSelectedQuest = function(id) selections = selections + 1 stub.selectedQuest = id end
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	check(selections == 0 and select(1, Lv:GetTurnInXP()) == 1240, "unchanged ready set served from the cache")
	stub.questLog[504] = { title = "Done C", complete = true, objectives = {}, xp = 100 }
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	check(selections == 4 and select(1, Lv:GetTurnInXP()) == 1340, "new ready quest rescans (3 selections + restore), got " .. selections .. " / " .. tostring(Lv:GetTurnInXP()))
	stub.questLog[504] = nil
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	C_QuestLog.SetSelectedQuest = realSet
	local text = Lv:TurnInText()
	check(text and text:find("|cffffffff1240|r xp (10% of level)", 1, true) ~= nil, "percent-of-level wording: " .. tostring(text))
	check((LodestarXPFrame.text.text or ""):find("turn-ins: |cffffffff1240|r xp", 1, true) ~= nil, "XP line carries the suffix: " .. tostring(LodestarXPFrame.text.text))
	stub.xp = 11000 -- 1000 to go, 1240 waiting
	Lv:RefreshXPText()
	text = Lv:TurnInText()
	check(text and text:find("1240|r xp |cffffff00(ding!)|r", 1, true) ~= nil, "ding wording when the sum covers the level: " .. tostring(text))
	check((LodestarXPFrame.text.text or ""):find("(ding!)", 1, true) ~= nil, "XP line shows the ding")
	-- option off: line clean, minimap tooltip still has it
	Lv.db.profile.xp.showTurnIns = false
	Lv:RefreshXPText()
	check((LodestarXPFrame.text.text or ""):find("turn-ins", 1, true) == nil, "suffix hidden by option")
	local lines = {}
	local tt = { AddDoubleLine = function(_, l, r) lines[l] = r end, AddLine = function() end }
	for _, fn in ipairs(Lodestar.tooltipProviders) do fn(tt) end
	check(lines["Turn-ins ready"] and lines["Turn-ins ready"]:find("(ding!)", 1, true) ~= nil, "minimap tooltip always lists turn-ins: " .. tostring(lines["Turn-ins ready"]))
	Lv.db.profile.xp.showTurnIns = true
	-- frame tooltip: turn-ins and strip lines
	lines = {}
	GameTooltip.AddDoubleLine = function(_, l, r) lines[l] = r end
	LodestarXPFrame.scripts.OnEnter(LodestarXPFrame)
	GameTooltip.AddDoubleLine = nil
	check(lines["Ready to turn in (2)"] ~= nil and lines["Ready to turn in (2)"]:find("ding", 1, true) ~= nil, "frame tooltip lists ready quests")
	check(lines["Bag slots free"] == "3" and lines["Lowest durability"] == "62%" and lines["Buffs"] == "Well Fed", "frame tooltip has the strip lines")
	stub.slash("/lode xp")
	check((stub.chat[#stub.chat] or ""):find("2 quests ready to turn in", 1, true) ~= nil, "/lode xp reports the turn-ins")
	-- missing GetQuestLogRewardXP: nothing counted, no error
	local realReward = GetQuestLogRewardXP
	GetQuestLogRewardXP = false -- absent (false rather than nil keeps the stub's unknown-global tally clean)
	Lv:RefreshTurnIns()
	check(select(2, Lv:GetTurnInXP()) == 0, "no reward API: nothing counted")
	GetQuestLogRewardXP = realReward
	-- empty log
	stub.questLog = {}
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	check(Lv:TurnInText() == nil and select(2, Lv:GetTurnInXP()) == 0, "empty log: no turn-in text")
	lines = {}
	for _, fn in ipairs(Lodestar.tooltipProviders) do fn(tt) end
	check(lines["Turn-ins ready"] == "none", "minimap tooltip says none")
	stub.questLog = savedLog
	stub.xp = 100
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
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
	check(opts.args.Leveling and opts.args.Economy and opts.args.UI and opts.args.Guild and opts.args.Character and opts.args.profiles, "options tree has all groups")
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
	-- level 10 picks the 5-12 guide; level 40 has nothing and must not load an outleveled guide
	stub.level = 10
	check(G:PickGuide() and G:PickGuide().name == "Horde/Undead 5-12: Tirisfal Glades", "level 10 picks the Tirisfal guide")
	stub.level = 40
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
try("minimap line", function()
	stub.slash("/lode guide smart")
	wipe(G:HarvestDB().npcs) -- the gossip stub's npc offers a quest at 0 yd, which would win the smart list
	G:PinSmartItem(nil)
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = true, objectives = {}, wp = { map = 18, x = 0.318, y = 0.662 } }
	G:RetargetArrow()
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	check(LodestarMinimapLine and LodestarMinimapLine.shown, "minimap line shown for a target on this map")
	-- target 100 yd east: with 140 px for 466 yd the end point is ~30 px to the right, inside the radius
	local ex, ey, clamped = G:MinimapLineState()
	check(ex and ex > 20 and ex < 40 and math.abs(ey) < 2 and not clamped, "line end scaled by minimap yards: " .. tostring(ex))
	stub.questLog[3901].wp = { map = 18, x = 0.5, y = 0.662 }
	G:RetargetArrow()
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	ex, ey, clamped = G:MinimapLineState()
	check(ex and math.abs(ex - 64) < 1 and clamped, "far target clamps to the minimap edge: " .. tostring(ex))
	G.db.profile.arrow.minimapLine = false
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	check(not LodestarMinimapLine.shown, "line hidden when disabled")
	G.db.profile.arrow.minimapLine = true
	G.db.profile.arrow.style = "classic" G:UpdateArrowFrame()
	G.db.profile.arrow.style = "blizzard" G:UpdateArrowFrame()
	G.db.profile.arrow.style = "lodestar" G:UpdateArrowFrame()
	stub.questLog[3901] = nil
end)
try("sync on load", function()
	stub.level = 3
	stub.questLog = {}
	stub.flagged = { [363] = true, [364] = true }
	-- saved position behind the quest log -> jumps forward on load
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = 2
	G:LoadGuide("Horde/Undead 1-5: Deathknell")
	check(G.stepIndex == 4, "load synced forward from saved step 2 to 4, at " .. tostring(G.stepIndex))
	-- saved position ahead of the quest log -> kept (the player may have skipped on purpose)
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = 12
	G:LoadGuide("Horde/Undead 1-5: Deathknell")
	check(G.stepIndex >= 12, "saved progress ahead of the log is kept, at " .. tostring(G.stepIndex))
	local start, _, open = G:SuggestStartIndex(G.current)
	check(start == 4 and open == 0, "suggest start 4 with no open earlier steps: " .. tostring(start) .. "/" .. tostring(open))
	stub.slash("/lode guide sync")
	check(G.stepIndex == 4, "/lode guide sync jumps back to 4, at " .. tostring(G.stepIndex))
	-- open earlier step: quest 3901 accepted (step 4 done) but 376 never taken while 3902 (needs 376) is flagged
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = false, objectives = {} }
	stub.flagged[3902] = true
	start, _, open = G:SuggestStartIndex(G.current)
	check(open >= 1, "earlier open steps counted: " .. tostring(open))
	G:RefreshStepFrame()
	stub.flagged = {}
	stub.questLog = {}
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = nil
	G:LoadGuide("Horde/Undead 1-5: Deathknell", 1)
end)
try("forever overlay", function()
	check(G.ForeverData and G.VanillaData.quests[99142] and G.VanillaData.quests[99142].t == "Tomb Weed", "Forever quest merged into the data")
	check(G.VanillaData.quests[99142].forever == true and G.VanillaData.quests[356].xp ~= nil, "overlay adds xp to a Vanilla quest and flags Forever ones")
	check(G.VanillaData.npcs[246152] and G.VanillaData.npcs[246152].n == "Shari Stilwell", "Forever-only NPC merged")
	stub.questLog[99142] = { title = "Tomb Weed", complete = true, objectives = { { text = "Tomb Weed: 5/5", finished = true } } }
	local mapID, _, _, how = G:DataQuestPosition(99142, true)
	check(mapID == 18 and how and how:find("Holland", 1, true), "turn-in for a Forever quest resolves to its harvested ender: " .. tostring(how))
	stub.questLog[99142].complete = false
	stub.questLog[99142].objectives[1] = { text = "Tomb Weed: 2/5", finished = false }
	local m2, x2, y2, how2 = G:DataQuestPosition(99142, false)
	check(m2 == 1420 and math.abs(x2 - 0.75) < 0.01 and math.abs(y2 - 0.592) < 0.01 and how2 == "Objective area", "objective for a Forever quest uses harvested spots: " .. tostring(m2))
	stub.slash("/lode quest 99142")
	stub.questLog[99142] = nil
end)
try("delete popup", function()
	stub.deleteDialog.editBox.text = ""
	StaticPopup_Show("DELETE_GOOD_ITEM")
	stub.advance(0.1)
	check(stub.deleteDialog.editBox.text == "DELETE", "DELETE typed into the confirmation box: " .. tostring(stub.deleteDialog.editBox.text))
	stub.deleteDialog.editBox.text = ""
	Lodestar:GetModule("UI").db.profile.popups.fillDelete = false
	StaticPopup_Show("DELETE_GOOD_ITEM")
	stub.advance(0.1)
	check(stub.deleteDialog.editBox.text == "", "option off leaves the box alone")
	Lodestar:GetModule("UI").db.profile.popups.fillDelete = true
	stub.shownPopup = nil
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
try("quest tips", function()
	local UNIT, ITEM, OBJECT = Enum.TooltipDataType.Unit, Enum.TooltipDataType.Item, Enum.TooltipDataType.Object
	check(stub.tooltipCalls[OBJECT] and #stub.tooltipCalls[OBJECT] >= 1, "object tooltip post-call registered")
	local lines = {}
	GameTooltip.AddLine = function(_, text) tinsert(lines, text) end
	local function tip(kind, tooltipData)
		wipe(lines)
		for _, fn in ipairs(stub.tooltipCalls[kind]) do fn(GameTooltip, tooltipData) end
		return table.concat(lines, "\n")
	end
	local skeleton, sarvis, duskbat = { guid = "Creature-0-1-2-3-1890-000ABC" }, { guid = "Creature-0-1-2-3-1569-000ABC" }, { guid = "Creature-0-1-2-3-1512-000ABC" }
	local savedLog, savedFlagged, savedLevel = stub.questLog, stub.flagged, stub.level
	local H = G:HarvestDB()
	wipe(H.npcs)
	local T = G.db.profile.questTips
	stub.level = 3
	stub.flagged = { [363] = true, [364] = true }
	stub.questLog = { [3901] = { title = "Rattling the Rattlecages", complete = false, objectives = { { text = "Rattlecage Skeleton slain: 3/8", finished = false } } } }
	stub.fire("QUEST_LOG_UPDATE")
	-- objective mob: quest title + the client's objective text with progress
	local text = tip(UNIT, skeleton)
	check(text:find("|cffffd700Rattling the Rattlecages|r  Rattlecage Skeleton slain: 3/8", 1, true) ~= nil, "objective mob shows the quest and progress: " .. text)
	-- cache: served as-is for 2 s, rebuilt after that and on quest log events
	stub.questLog[3901].objectives[1].text = "Rattlecage Skeleton slain: 4/8"
	check(tip(UNIT, skeleton):find("3/8", 1, true) ~= nil, "cached lines served within 2 s")
	stub.advance(2.5)
	check(tip(UNIT, skeleton):find("4/8", 1, true) ~= nil, "cache expired after 2 s")
	stub.questLog[3901].objectives[1].text = "Rattlecage Skeleton slain: 5/8"
	stub.fire("QUEST_LOG_UPDATE")
	check(tip(UNIT, skeleton):find("5/8", 1, true) ~= nil, "quest log event drops the cache")
	-- objective index: the data says objective 1, the client lists the mob second -> matched by name
	stub.questLog[3901].objectives = { { text = "Something else: 1/1", finished = true }, { text = "Rattlecage Skeleton slain: 6/8", finished = false } }
	stub.fire("QUEST_LOG_UPDATE")
	check(tip(UNIT, skeleton):find("|r  Rattlecage Skeleton slain: 6/8", 1, true) ~= nil, "objective matched by name when the index disagrees")
	-- finished objective -> green line
	stub.questLog[3901].objectives = { { text = "Rattlecage Skeleton slain: 8/8", finished = true } }
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, skeleton)
	check(text:find("|cff7fff7fRattling the Rattlecages  Rattlecage Skeleton slain: 8/8|r", 1, true) ~= nil, "finished objective is green: " .. text)
	-- Blizzard already prints the quest on this unit (QuestTitle line) -> not repeated
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, { guid = skeleton.guid, lines = { { type = Enum.TooltipDataLineType.QuestTitle, leftText = "Rattling the Rattlecages" }, { type = Enum.TooltipDataLineType.QuestObjective, leftText = "Rattlecage Skeleton slain: 8/8" } } })
	check(not text:find("Rattling", 1, true), "quest Blizzard already lists is not repeated: " .. text)
	-- quest ender: "Turn in later" while unfinished, "Turn in" once complete
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("|cff9d9d9dTurn in later: Rattling the Rattlecages|r", 1, true) ~= nil, "ender of an unfinished quest: " .. text)
	stub.questLog[3901].complete = true
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("|cff7fff7fTurn in: Rattling the Rattlecages|r", 1, true) ~= nil, "ender of a complete quest: " .. text)
	check(not text:find("Starts: Rattling", 1, true), "a quest in the log is not offered again")
	-- quest giver: level 3, 364 flagged, 3901 not in the log -> Sarvis starts it (and the warrior's class quest)
	stub.questLog = {}
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("|cffffd700Starts: Rattling the Rattlecages (lvl 3)|r", 1, true) ~= nil, "quest giver lists the quests you can take: " .. text)
	check(text:find("Starts: Simple Scroll", 1, true) ~= nil and not text:find("Encrypted Scroll", 1, true), "class mask applied to the offered quests")
	check(not text:find("Turn in", 1, true), "empty log: only Starts lines")
	-- harvest: a quest the data does not know is offered as (new); roles from the NPC kinds
	H.npcs[1569] = { name = "Shadow Priest Sarvis", gives = { [77778] = true, [3901] = true }, kind = { vendor = true, repair = true, quest = true } }
	H.quests[77778] = { t = "A Forever Quest", lvl = 4 }
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("|cffffd700Starts: A Forever Quest (lvl 4) (new)|r", 1, true) ~= nil, "harvest-only quest offered as (new): " .. text)
	check(select(2, text:gsub("Rattling the Rattlecages", "")) == 1, "harvested quest also in the data listed once")
	check(text:find("Vendor · Repair", 1, true) ~= nil, "role line from the harvest kinds")
	T.showLevel = false
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("Starts: Rattling the Rattlecages|r", 1, true) ~= nil and not text:find("(lvl ", 1, true), "showLevel off drops the level: " .. text)
	T.showLevel = true
	H.npcs[1569] = nil H.quests[77778] = nil
	-- items: Duskbat Wing (3264) is an objective of The Damned (376); Duskbats drop it
	stub.questLog = { [376] = { title = "The Damned", complete = false, objectives = { { text = "Duskbat Wing: 2/6", finished = false }, { text = "Scavenger Paw: 0/6", finished = false } } } }
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(ITEM, { id = 3264 })
	check(text:find("|cffffd700The Damned|r — 2/6", 1, true) ~= nil, "quest item shows its quest and count: " .. text)
	text = tip(UNIT, duskbat)
	check(text:find("|cffffd700The Damned|r  Duskbat Wing: 2/6", 1, true) ~= nil and not text:find("Scavenger Paw", 1, true), "drop source shows the item objective only: " .. text)
	text = tip(ITEM, { id = 4851 })
	check(text:find("|cffffd700Starts a quest: Attack on Camp Narache (lvl 4)|r", 1, true) ~= nil, "quest-starting item: " .. text)
	stub.questLog[376].complete = true stub.questLog[376].objectives[1] = { text = "Duskbat Wing: 6/6", finished = true }
	stub.fire("QUEST_LOG_UPDATE")
	check(tip(ITEM, { id = 3264 }):find("|cff7fff7fThe Damned — 6/6|r", 1, true) ~= nil, "collected quest item stays marked, in green")
	check(tip(UNIT, duskbat) == "", "objective mob of a complete quest shows nothing")
	-- objects: Marla's Grave (178090) is objective 2 of Marla's Last Wish (6395); the barrel (269) starts a quest
	stub.questLog = { [6395] = { title = "Marla's Last Wish", complete = false, objectives = { { text = "Samuel's Remains: 1/1", finished = true }, { text = "Bring the remains to Marla's Grave: 0/1", finished = false } } } }
	stub.flagged[310] = true
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(OBJECT, { guid = "GameObject-0-1-2-3-178090-000ABC" })
	check(text:find("|cffffd700Marla's Last Wish|r  Bring the remains to Marla's Grave: 0/1", 1, true) ~= nil, "object objective by index: " .. text)
	stub.questLog[6395].objectives = { { text = "Visit the grave: 0/1", finished = false } }
	stub.fire("QUEST_LOG_UPDATE")
	check(tip(OBJECT, { guid = "GameObject-0-1-2-3-178090-000ABC" }):find("|r  Visit the grave: 0/1", 1, true) ~= nil, "index out of range falls back to the first unfinished objective")
	text = tip(OBJECT, { guid = "GameObject-0-1-2-3-269-000ABC" })
	check(text:find("|cffffd700Starts: Guarded Thunderbrew Barrel (lvl 1)|r", 1, true) ~= nil, "quest-starting object: " .. text)
	check(tip(OBJECT, duskbat) == "" and tip(UNIT, { guid = "GameObject-0-1-2-3-178090-000ABC" }) == "", "unit and object handlers only take their own GUID type")
	check(tip(UNIT, { guid = "Player-1-000001" }) == "", "players ignored")
	-- toggles and lifecycle
	T.units = false
	check(tip(UNIT, { guid = "GameObject-0-1-2-3-269-000ABC" }) == "" and tip(UNIT, sarvis) == "", "units toggle off suppresses unit lines")
	T.units = true
	T.items = false
	check(tip(ITEM, { id = 4851 }) == "", "items toggle off suppresses item lines")
	T.items = true
	T.objects = false
	check(tip(OBJECT, { guid = "GameObject-0-1-2-3-269-000ABC" }) == "", "objects toggle off suppresses object lines")
	T.objects = true
	G:DisableQuestTips()
	check(tip(UNIT, sarvis) == "", "disabled: no lines")
	G:EnableQuestTips()
	check(tip(UNIT, sarvis) ~= "", "re-enabled: lines again")
	check(#stub.tooltipCalls[UNIT] == 2 and #stub.tooltipCalls[OBJECT] == 1, "post-calls registered once across enable/disable")
	-- ours run after Lodestar_UI's (registered a tick later although Guide enables first): the last unit post-call is the one that adds quest lines
	wipe(lines)
	stub.tooltipCalls[UNIT][#stub.tooltipCalls[UNIT]](GameTooltip, sarvis)
	check(#lines > 0, "quest lines come from the last registered unit post-call (after the UI module's)")
	-- ItemRefTooltip gets item lines; other tooltips are left alone
	local other = stub.newFrame("GameTooltip", "SomeOtherTooltip")
	other.AddLine = GameTooltip.AddLine
	wipe(lines)
	for _, fn in ipairs(stub.tooltipCalls[ITEM]) do fn(other, { id = 4851 }) end
	check(#lines == 0, "unrelated tooltips are not decorated")
	ItemRefTooltip.AddLine = GameTooltip.AddLine
	wipe(lines)
	for _, fn in ipairs(stub.tooltipCalls[ITEM]) do fn(ItemRefTooltip, { id = 4851 }) end
	check(#lines == 1, "ItemRefTooltip (chat links) gets item lines")
	ItemRefTooltip.AddLine = nil
	GameTooltip.AddLine = nil
	stub.questLog, stub.flagged, stub.level = savedLog, savedFlagged, savedLevel
	stub.fire("QUEST_LOG_UPDATE")
end)

-- Lodestar_Character
try("character", function()
	local C = Lodestar:GetModule("Character")
	check(C and C:IsEnabled() and statuses["Lodestar_Character"] == true, "Character module registered and enabled")
	local S = C.Stats
	local st = C:GetInjectionState()
	check(st.injected == true and st.fallback == false, "categories injected into PAPERDOLL_STATCATEGORIES")
	-- fixed character state for the numbers below
	stub.level, stub.xp, stub.xpMax, stub.rested = 12, 4000, 10000, 500
	stub.manaMax, stub.shield, stub.holyResist, stub.swimSpeed, stub.legacyRenown, stub.pvpRank, stub.meleeHaste = 1000, true, 15, 3.5, 12, 3, 0
	local instant = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function(id) -- main hand sword, off-hand dagger, ranged bow
		local sub = ({ [2001] = Enum.ItemWeaponSubclass.Sword1H, [2002] = Enum.ItemWeaponSubclass.Dagger, [2003] = Enum.ItemWeaponSubclass.Bows })[id]
		return id, "Weapon", "Sub", "INVTYPE_WEAPON", 134, Enum.ItemClass.Weapon, sub
	end
	-- placement and names
	local cats = C:InjectedCategories()
	local names = {}
	for i, cat in ipairs(cats) do names[i] = cat.categoryName end
	check(table.concat(names, ",") == "Melee,Ranged,Spell,Regeneration,Defense detail,Weapon skills,Gear,Progress", "eight categories in order: " .. table.concat(names, ","))
	check(PAPERDOLL_STATCATEGORIES[2].categoryName == "Modifiers" and PAPERDOLL_STATCATEGORIES[3].lodestar and PAPERDOLL_STATCATEGORIES[#PAPERDOLL_STATCATEGORIES].unit == "pet", "inserted after Blizzard's player categories, before the pet one")
	local meleeStats = {}
	for i, s in ipairs(cats[1].stats) do meleeStats[i] = s.stat end
	check(table.concat(meleeStats, ",") == "LODESTAR_MELEE_HIT,LODESTAR_MELEE_CRIT,LODESTAR_MELEE_HASTE,LODESTAR_ATTACK_SPEED,LODESTAR_MELEE_DPS", "melee rows: " .. table.concat(meleeStats, ","))
	check(cats[1].stats[1].hideAt == 0 and cats[1].stats[4].hideAt == nil, "hideZero applies to hit but never to attack speed")
	check(PAPERDOLL_STATINFO.LODESTAR_MELEE_HIT and PAPERDOLL_STATINFO.LODESTAR_MELEE_HIT.lodestar, "PAPERDOLL_STATINFO entries registered")
	-- every row's update runs on a Blizzard-style stat frame and produces text
	local frame = stub.newFrame("Frame")
	frame.Label, frame.Value = frame:CreateFontString(), frame:CreateFontString()
	local texts, numerics = {}, {}
	for stat, row in pairs(S.rowByStat) do
		frame.Label.text, frame.Value.text, frame.tooltip, frame.tooltip2 = nil, nil, nil, nil
		local ok, v = pcall(row.update, frame, "player")
		check(ok, "row " .. stat .. " runs: " .. tostring(v))
		if ok and v ~= nil then
			check(type(frame.Value.text) == "string" and frame.Value.text ~= "" and frame.Label.text ~= nil, "row " .. stat .. " sets label and value")
			check(type(frame.tooltip) == "string", "row " .. stat .. " sets a tooltip")
			texts[stat], numerics[stat] = frame.Value.text, v
		end
	end
	check(texts.LODESTAR_MELEE_HIT == "5.0%", "melee hit = rating bonus + modifier: " .. tostring(texts.LODESTAR_MELEE_HIT))
	check(texts.LODESTAR_RANGED_HIT == "3.0%" and texts.LODESTAR_SPELL_HIT == "4.0%", "ranged/spell hit split")
	check(texts.LODESTAR_MELEE_CRIT == "5.5%" and texts.LODESTAR_RANGED_CRIT == "4.3%" and texts.LODESTAR_SPELL_CRIT == "6.1%", "crit split")
	check(texts.LODESTAR_ATTACK_SPEED == "2.60 / 1.80", "attack speed main / off: " .. tostring(texts.LODESTAR_ATTACK_SPEED))
	check(texts.LODESTAR_MELEE_DPS == "19.2 / 13.9", "dps = (min+max)/2/speed: " .. tostring(texts.LODESTAR_MELEE_DPS))
	check(texts.LODESTAR_RANGED_SPEED == "2.90" and texts.LODESTAR_RANGED_DPS == "13.8", "ranged speed and dps")
	check(texts.LODESTAR_SPELL_FROST == "120" and texts.LODESTAR_SPELL_FIRE == nil, "only the school above the minimum gets a row")
	check(texts.LODESTAR_MP5 == "42 / 11" and texts.LODESTAR_HP5 == "30 / 6", "mp5 / hp5 = per-second x5: " .. tostring(texts.LODESTAR_MP5) .. " " .. tostring(texts.LODESTAR_HP5))
	-- defense 65 at level 12: boss skill 75, diff 10 -> miss 4.6, crit 5.4; crush uses defense capped at level*5 -> diff 15 -> 15%
	check(texts.LODESTAR_ENEMY_MISS == "4.6%" and texts.LODESTAR_ENEMY_CRIT == "5.4%" and texts.LODESTAR_CRUSH == "15.0%", "enemy miss/crit/crush vs +3 from the defense formulas: " .. tostring(texts.LODESTAR_ENEMY_MISS) .. " " .. tostring(texts.LODESTAR_ENEMY_CRIT) .. " " .. tostring(texts.LODESTAR_CRUSH))
	check(texts.LODESTAR_BLOCK_VALUE == "42" and texts.LODESTAR_DODGE_AGI == "3.2%" and numerics.LODESTAR_PARRY_STR == 0, "block value, dodge from agility, parry from strength")
	check(texts.LODESTAR_ARMOR_REDUCTION == "41.3%", "armor reduction via C_PaperDollInfo.GetArmorEffectiveness: " .. tostring(texts.LODESTAR_ARMOR_REDUCTION))
	check(texts.LODESTAR_HOLY_RESIST == "15", "holy resistance shown when non-zero")
	check(texts.LODESTAR_WEAPON_SKILL_MH == "87/100 |cff20ff20+5|r", "main-hand weapon skill: " .. tostring(texts.LODESTAR_WEAPON_SKILL_MH))
	check(texts.LODESTAR_WEAPON_SKILL_OH == texts.LODESTAR_WEAPON_SKILL_MH and texts.LODESTAR_WEAPON_SKILL_RANGED == texts.LODESTAR_WEAPON_SKILL_MH, "off-hand and ranged weapon skills")
	check(texts.LODESTAR_ITEM_LEVEL == "23", "average item level (equipped)")
	check(texts.LODESTAR_DURABILITY == "62%", "durability = lowest slot: " .. tostring(texts.LODESTAR_DURABILITY))
	check(texts.LODESTAR_SWIM_SPEED == "50%", "swim speed shown when it differs from run speed")
	check(texts.LODESTAR_XP == "40.0%" and texts.LODESTAR_RESTED == "500 (5%)", "xp and rested: " .. tostring(texts.LODESTAR_XP) .. " " .. tostring(texts.LODESTAR_RESTED))
	check(texts.LODESTAR_TALENTS == "3" and texts.LODESTAR_LEGACY == "12 (5 free)" and texts.LODESTAR_PVP_RANK == "PVP_RANK_7_0", "talents, legacy and pvp rank rows")
	-- off-hand with the same skill as the main hand collapses into one row
	C_Item.GetItemInfoInstant = function(id) return id, "Weapon", "Sub", "INVTYPE_WEAPON", 134, Enum.ItemClass.Weapon, Enum.ItemWeaponSubclass.Sword1H end
	check(S.rowByStat.LODESTAR_WEAPON_SKILL_OH.update(frame, "player") == nil, "off-hand row hidden when it shares the main-hand skill")
	-- not applicable -> nil -> hidden through the registered updateFunc
	stub.holyResist = 0
	check(PAPERDOLL_STATINFO.LODESTAR_HOLY_RESIST.updateFunc(frame, "player") == 0, "nil from a row becomes the entry's hideAt")
	check(PAPERDOLL_STATINFO.LODESTAR_MELEE_HIT.updateFunc(frame, "pet") == 0, "pet unit is never ours")
	-- Blizzard's pane walk: hideZero hides the zero haste row, off shows it
	CharacterFrame.shown = true
	local function paneRows()
		PaperDollFrame_UpdateStats()
		local byStat = {}
		for _, r in ipairs(stub.paperDollRows) do byStat[r.stat] = r end
		return byStat
	end
	local rows = paneRows()
	check(rows.LODESTAR_MELEE_HIT and rows.LODESTAR_MELEE_HIT.value == "5.0%" and rows.LODESTAR_MELEE_HASTE == nil, "pane shows melee hit and drops the zero haste row")
	check(rows.LODESTAR_MELEE_HIT.tooltip2 and rows.LODESTAR_MELEE_HIT.tooltip2:find("Level 12: 0%.0%%") and rows.LODESTAR_MELEE_HIT.tooltip2:find("Level 15 %(boss%): 2%.7%%"), "miss table vs +3 in the tooltip: " .. tostring(rows.LODESTAR_MELEE_HIT.tooltip2))
	check(rows.HITCHANCE ~= nil, "Blizzard's Hit row untouched by default")
	C.db.profile.hideZero = false
	C:RefreshInjection()
	rows = paneRows()
	check(rows.LODESTAR_MELEE_HASTE and rows.LODESTAR_MELEE_HASTE.value == "0.0%", "hideZero off shows the zero haste row")
	check(rows.LODESTAR_SPELL_FIRE == nil and rows.LODESTAR_HOLY_RESIST == nil, "rows with a fixed hideAt stay hidden regardless")
	C.db.profile.hideZero = true
	-- category toggle removes the category
	C.db.profile.categories.gear = false
	C:RefreshInjection()
	local found = false
	for _, cat in ipairs(C:InjectedCategories()) do if cat.key == "gear" then found = true end end
	check(#C:InjectedCategories() == 7 and not found, "gear category removed when toggled off")
	C.db.profile.categories.gear = true
	C:RefreshInjection()
	check(#C:InjectedCategories() == 8, "gear category back when toggled on")
	-- replacing Blizzard's max-only rows wraps their showFunc and restores it
	C.db.profile.replaceBlizzardMaxRows = true
	C:RefreshInjection()
	rows = paneRows()
	check(rows.HITCHANCE == nil and rows.CRITCHANCE == nil and rows.HEALTH ~= nil, "Blizzard's Hit/Crit rows hidden while replaced")
	C.db.profile.replaceBlizzardMaxRows = false
	C:RefreshInjection()
	rows = paneRows()
	check(rows.HITCHANCE ~= nil and PAPERDOLL_STATCATEGORIES[2].stats[1].showFunc == nil, "Blizzard's rows restored, showFunc back to nil")
	-- refresh throttle: only while the character frame is shown, coalesced
	CharacterFrame.shown = false
	local before = stub.paperDollUpdates
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.advance(1)
	check(stub.paperDollUpdates == before, "no stats update while the character frame is hidden")
	CharacterFrame.shown = true
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("UPDATE_INVENTORY_DURABILITY")
	stub.fire("UNIT_DEFENSE", "player")
	check(stub.paperDollUpdates == before, "update is deferred, not immediate")
	stub.advance(1)
	check(stub.paperDollUpdates == before + 1, "three events coalesced into one PaperDollFrame_UpdateStats, got +" .. (stub.paperDollUpdates - before))
	stub.fire("UNIT_DEFENSE", "target")
	stub.advance(1)
	check(stub.paperDollUpdates == before + 1, "other units' UNIT_ events ignored")
	-- fallback panel when the camelot tables are missing
	CharacterFrame:Hide()
	local savedCats = PAPERDOLL_STATCATEGORIES
	PAPERDOLL_STATCATEGORIES = nil
	C:DisableInjection()
	C:EnableInjection()
	st = C:GetInjectionState()
	check(st.fallback == true and st.injected == false, "fallback panel path taken without PAPERDOLL_STATCATEGORIES")
	check(LodestarCharacterStatsFrame and not LodestarCharacterStatsFrame.shown, "fallback panel created, hidden while the character frame is")
	CharacterFrame:Show()
	check(LodestarCharacterStatsFrame.shown and (LodestarCharacterStatsFrame.shownRows or 0) > 0, "fallback panel shows and fills with the character frame's OnShow")
	local shown = C:RefreshFallbackPanel()
	check(shown >= 20, "fallback panel lists the rows, got " .. tostring(shown))
	local labels = {}
	for _, r in ipairs(LodestarCharacterStatsFrame.rows) do if r.shown then labels[r.Label.text] = r.Value.text end end
	check(labels["Melee hit:"] == "5.0%" and labels["Durability:"] == "62%", "fallback rows carry the same label/value")
	CharacterFrame.shown = false
	CharacterFrame:Hide()
	check(not LodestarCharacterStatsFrame.shown, "fallback panel hides with the character frame")
	PAPERDOLL_STATCATEGORIES = savedCats
	C:DisableInjection()
	C:EnableInjection()
	st = C:GetInjectionState()
	check(st.injected == true and st.fallback == false and not LodestarCharacterStatsFrame.shown, "injection back once the tables return")
	-- module disable removes everything, enable restores
	Lodestar:SetModuleEnabled("Character", false)
	check(#C:InjectedCategories() == 0 and PAPERDOLL_STATINFO.LODESTAR_MELEE_HIT == nil and statuses["Lodestar_Character"] == false, "disable removed categories and stat infos")
	Lodestar:SetModuleEnabled("Character", true)
	check(#C:InjectedCategories() == 8 and PAPERDOLL_STATINFO.LODESTAR_MELEE_HIT ~= nil, "re-enable injected again")
	-- options page
	local opts = Lodestar:BuildOptions()
	for _, opt in pairs(opts.args.Character.args) do
		if opt.get then
			local v = opt.get({})
			if opt.set and opt.type == "toggle" then opt.set({}, v) end
		elseif opt.type == "execute" then opt.func()
		end
	end
	C_Item.GetItemInfoInstant = instant
	stub.level = 3
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

-- Smoke test: load the whole suite under the WoW stub, simulate login, poke every feature.
-- Usage (from the repo root): lua5.1 tools/smoke/run.lua
local ROOT = arg and arg[0] and arg[0]:match("^(.*)tools[/\\]smoke[/\\]run%.lua$") or "./"
if ROOT == "" then ROOT = "./" end
package.path = ROOT .. "tools/smoke/?.lua;" .. package.path
local stub = require("wow_stub")

-- Blizzard's stats tables have to stay exactly as the client left them. An addon that writes into
-- PAPERDOLL_STATCATEGORIES / PAPERDOLL_STATINFO taints every path that reads them, and on Forever that
-- makes simply opening the character sheet throw ("TextStatusBar.lua:110: attempt to compare a secret
-- number value (execution tainted by 'Lodestar_Character')"). Snapshot both before a single addon file
-- is loaded; the Character block compares against this after login and after using the panel.
local function snapshot(value, seen)
	if type(value) ~= "table" then return tostring(value) end
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. snapshot(value[k], seen) end
	seen[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end
local function blizzardStatTables()
	return snapshot(rawget(_G, "PAPERDOLL_STATCATEGORIES")) .. "|" .. snapshot(rawget(_G, "PAPERDOLL_STATINFO"))
end
local pristineStatTables = blizzardStatTables()

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

-- The harvest delta sync (Lodestar_Guide/Share.lua) rides the same guild channel as presence and the
-- Guild blocks below count messages on it. Confirm it is on by default, then park it until its own
-- block turns it back on.
check(Lodestar:GetModule("Guide").db.profile.harvest.share == true, "harvest sharing on by default")
Lodestar:GetModule("Guide").db.profile.harvest.share = false
Lodestar:GetModule("Guide"):StopHarvestSync()

-- Slash commands
for _, line in ipairs({ "/lode", "/lode version", "/lode modules", "/lode xp", "/lode probe", "/lode gold", "/lode levels",
	"/lode loc", "/lode way 45.2 63.1 Kobold cave", "/way 12,5 88,0", "/way", "/way clear", "/lode keep 1234", "/lode keep",
	"/lode ah", "/lode ah 1234", "/lode lfg Deadmines tank", "/lode guild", "/lode guild", "/lode modules Economy off", "/lode modules Economy on", "/lode debug", "/lode debug", "/lode nonsense" }) do
	try("slash " .. line, function() stub.slash(line) end)
end
check(stub.openedCategory ~= nil, "/lode opened settings")
check(LodestarProbes and LodestarProbes.checks, "probe wrote LodestarProbes")
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
	-- The client fires Activating BEFORE enforcement, while the queries still answer "not restricted",
	-- so the activating edge has to be taken from the payload, not from a live re-read.
	stub.commRestricted = false
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Activating)
	stub.commRestricted = true
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
	-- Opened next frame: a slash handler runs inside ParseText, which clears the box immediately after.
	stub.advance(0.1)
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
	-- Lifting is reported after the fact, so the re-read is authoritative -- one frame later.
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
	stub.advance(0.1)
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
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
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

-- Bags and the self-calibrating repair estimate.
-- The estimate is the interesting part: GetRepairAllCost only answers at a repair vendor, so the
-- rate has to be learned there and applied everywhere else. Until one repair has been seen the
-- answer must be nil rather than a guess, because the player will plan around whatever we print.
try("bags and repair estimate", function()
	local E = Lodestar:GetModule("Economy")
	wipe(E.db.global.repair)

	stub.bags[0] = {
		[1] = { hyperlink = "|Hitem:1234::::::::1:::::|h[Broken Fang]|h", quality = 0, stackCount = 3, itemID = 1234 },
		[2] = { hyperlink = "|Hitem:5555::::::::1:::::|h[Nice Sword]|h", quality = 2, stackCount = 1, itemID = 5555 },
		[3] = { hyperlink = "|Hitem:7777::::::::1:::::|h[Quest Thing]|h", quality = 1, stackCount = 1, itemID = 7777, hasNoValue = true },
	}
	local b = E:ScanBags()
	-- The stub prices every item at 25 copper: 3 + 1 sellable stacks, the no-value one ignored.
	check(b.slots == 16 and b.used == 3 and b.free == 13, "bag slots counted: " .. b.used .. " used, " .. b.free .. " free")
	check(b.value == 25 * 3 + 25, "vendor value counts stacks and skips no-value items: " .. b.value)
	check(b.junkCount == 1 and b.junkValue == 75, "greys counted separately: " .. b.junkCount .. " / " .. b.junkValue)
	check(b.cheapest and b.cheapest.itemID == nil and b.cheapest.value == 25, "cheapest sellable stack is the single sword: " .. tostring(b.cheapest and b.cheapest.value))

	-- Nothing learned yet: no estimate, and the report says why rather than inventing one.
	check(E:EstimatedRepairCost() == nil, "no repair estimate before the first vendor repair")
	local missing, lowest = E:MissingDurability()
	check(missing == 48 and math.floor(lowest) == 62, "durability points missing: " .. tostring(missing) .. " lowest " .. tostring(lowest))

	local lines = {}
	local realSay = Lodestar.Say
	Lodestar.Say = function(_, fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
	Lodestar:HandleSlash("bags")
	local report = table.concat(lines, "\n")
	check(report:find("learned at your first vendor repair", 1, true) ~= nil, "report says the rate is not known yet: " .. report)
	check(report:find("13 of 16 slots free", 1, true) ~= nil, "report counts slots: " .. report)

	-- A repair at a vendor teaches the rate: 1234 copper over 48 missing points.
	stub.repairCost = 1234
	stub.fire("MERCHANT_SHOW")
	stub.fire("MERCHANT_CLOSED")
	check(E.db.global.repair.perPoint and math.abs(E.db.global.repair.perPoint - 1234 / 48) < 0.001,
		"rate learned from the vendor's quote: " .. tostring(E.db.global.repair.perPoint))
	check(E:EstimatedRepairCost() == 1234, "the estimate reproduces the quote it learned from: " .. tostring(E:EstimatedRepairCost()))

	-- Half the damage, half the cost.
	stub.durability[1] = { 81, 100 }
	stub.durability[5] = { 95, 100 }
	check(E:EstimatedRepairCost() == math.floor(24 * (1234 / 48)), "estimate scales with damage: " .. tostring(E:EstimatedRepairCost()))

	-- Fully repaired gear costs nothing, and that is a real answer rather than a missing one.
	stub.durability[1] = { 100, 100 }
	stub.durability[5] = { 100, 100 }
	check(E:EstimatedRepairCost() == 0, "no damage, no cost")

	-- A repair too small to measure is not allowed to drag the rate around: the server rounds, so a
	-- 2-point repair is mostly rounding error.
	stub.durability[1] = { 99, 100 }
	stub.repairCost = 500
	local before = E.db.global.repair.perPoint
	stub.fire("MERCHANT_SHOW")
	stub.fire("MERCHANT_CLOSED")
	check(E.db.global.repair.perPoint == before, "a one-point repair does not move the rate: " .. tostring(E.db.global.repair.perPoint))

	-- Several real repairs average out.
	stub.durability[1] = { 50, 100 }
	stub.repairCost = 2000
	stub.fire("MERCHANT_SHOW")
	stub.fire("MERCHANT_CLOSED")
	check(math.abs(E.db.global.repair.perPoint - ((1234 / 48) + (2000 / 50)) / 2) < 0.001,
		"rates average across repairs: " .. tostring(E.db.global.repair.perPoint))

	lines = {}
	Lodestar:HandleSlash("bags")
	check(table.concat(lines, "\n"):find("repairs: about", 1, true) ~= nil, "report gives the estimate once it knows the rate: " .. table.concat(lines, "\n"))
	Lodestar.Say = realSay

	-- Once the rate is known, the Leveling durability warning carries the cost across the module
	-- boundary. Economy is optional, so the warning has to read fine without it too.
	do
		local Lv = Lodestar:GetModule("Leveling")
		local said = {}
		local realMsg = Lodestar.Msg
		Lodestar.Msg = function(_, fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
		stub.durability[1] = { 8, 100 }
		stub.advance(600)   -- past the five-minute rate limit left over from the status-strip block
		Lv:RefreshStrip()
		local nagText = table.concat(said, " | ")
		check(nagText:find("Durability at 8%", 1, true) and nagText:find("to repair", 1, true),
			"durability warning carries the repair estimate: " .. nagText)
		Lodestar:SetModuleEnabled("Economy", false)
		said = {}
		stub.advance(600)
		Lv:RefreshStrip()
		nagText = table.concat(said, " | ")
		check(nagText:find("Durability at 8%", 1, true) and nagText:find("to repair", 1, true) == nil,
			"and reads fine with Economy disabled: " .. nagText)
		Lodestar:SetModuleEnabled("Economy", true)
		Lodestar.Msg = realMsg
	end

	-- The minimap tooltip line.
	local tipLines = {}
	local tip = { AddDoubleLine = function(_, l, r) tipLines[l] = r end, AddLine = function() end }
	for _, fn in ipairs(Lodestar.tooltipProviders) do pcall(fn, tip) end
	-- 14, not 13: the vendor visits above auto-sold the grey stack, which is the whole point of
	-- reading the bags live rather than caching a count.
	check(tipLines["Bags"] and tipLines["Bags"]:find("14 free", 1, true), "minimap tooltip carries the bag line: " .. tostring(tipLines["Bags"]))
	check(tipLines["Repairs"] and tipLines["Repairs"]:find("about", 1, true), "minimap tooltip carries the repair estimate: " .. tostring(tipLines["Repairs"]))

	-- ... and drops out cleanly when the player turns it off.
	E.db.profile.bags.minimapLine = false
	tipLines = {}
	for _, fn in ipairs(Lodestar.tooltipProviders) do pcall(fn, tip) end
	check(tipLines["Bags"] == nil, "bag line hidden by its option")
	E.db.profile.bags.minimapLine = true

	-- Restore.
	stub.durability[1] = { 62, 100 }
	stub.durability[5] = { 90, 100 }
	stub.repairCost = 1234
	stub.bags[0][3] = nil
end)

-- Camp: buff timers, food and drink, and the warnings that ride on them.
-- The point of a timer warning is to arrive while there is still time to do something about it, so
-- the thresholds are checked at the boundaries rather than somewhere comfortably inside them.
-- Quest log hygiene: the twenty-slot cap and what has gone grey.
-- The rule that matters is that nothing is ever abandoned without being asked, and that only grey
-- quests are candidates -- "drop a" must never be able to throw away a chain in progress.
try("quest log", function()
	local Lv = Lodestar:GetModule("Leveling")
	local savedLog = stub.questLog
	stub.questLog = {}
	stub.trivial = {}
	stub.abandoned = {}
	stub.maxQuests = 20
	for i = 1, 18 do
		local id = 7100 + i
		stub.questLog[id] = { title = "Errand " .. i, complete = (i <= 2), objectives = {} }
	end
	stub.trivial[7101] = true
	stub.trivial[7102] = true
	stub.trivial[7105] = true

	local st = Lv:QuestLogStatus()
	check(st.count == 18 and st.max == 20 and st.free == 2, "log counted: " .. st.count .. "/" .. st.max)
	check(#st.trivial == 3 and st.complete == 2, "trivial and complete counted: " .. #st.trivial .. " / " .. st.complete)

	-- Nearly full: one line, naming what has gone grey.
	local said = {}
	local realMsg = Lodestar.Msg
	Lodestar.Msg = function(_, fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
	stub.advance(700)
	Lv:CheckQuestLog()
	check(#said == 1 and said[1]:find("18/20", 1, true) and said[1]:find("3 trivial", 1, true),
		"a nearly full log names the trivial ones: " .. table.concat(said, " | "))
	said = {}
	Lv:CheckQuestLog()
	check(#said == 0, "and does not repeat inside the rate limit")

	-- Room again: silence, and the rate limit resets so the next squeeze is reported.
	for i = 10, 18 do stub.questLog[7100 + i] = nil end
	said = {}
	Lv:CheckQuestLog()
	check(#said == 0, "a log with room says nothing")

	-- Dropping: only trivial quests match, and only with a confirmation.
	local lines = {}
	local realSay = Lodestar.Say
	Lodestar.Say = function(_, fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
	stub.shownPopup = nil
	Lv:DropQuest("Errand 3")
	check(#stub.abandoned == 0 and stub.shownPopup == nil, "a quest that is not grey is not a candidate")
	check(table.concat(lines, " "):find("No trivial quest matches", 1, true) ~= nil, "and says so: " .. table.concat(lines, " "))

	lines = {}
	Lv:DropQuest("Errand")
	check(stub.shownPopup == nil and table.concat(lines, " "):find("Be more specific", 1, true) ~= nil,
		"an ambiguous name asks for a better one: " .. table.concat(lines, " "))

	lines = {}
	Lv:DropQuest("Errand 5")
	check(stub.shownPopup == "LODESTAR_ABANDON_QUEST" and #stub.abandoned == 0,
		"a single grey match asks before doing anything: " .. tostring(stub.shownPopup))
	check(stub.shownPopupArg == "Errand 5", "the confirmation names the quest: " .. tostring(stub.shownPopupArg))

	-- Saying no changes nothing.
	StaticPopupDialogs["LODESTAR_ABANDON_QUEST"].OnCancel()
	Lv:ConfirmDropQuest()
	check(#stub.abandoned == 0 and stub.questLog[7105] ~= nil, "declining leaves the quest alone")

	-- Saying yes abandons that one and only that one.
	Lv:DropQuest("Errand 5")
	StaticPopupDialogs["LODESTAR_ABANDON_QUEST"].OnAccept()
	check(#stub.abandoned == 1 and stub.abandoned[1] == 7105, "confirming abandons the matched quest: " .. tostring(stub.abandoned[1]))
	check(stub.questLog[7101] ~= nil and stub.questLog[7102] ~= nil, "and leaves the other grey ones alone")

	Lodestar.Say = realSay
	Lodestar.Msg = realMsg
	stub.questLog = savedLog
	stub.trivial = {}
	stub.abandoned = {}
end)

try("camp", function()
	local Lv = Lodestar:GetModule("Leveling")
	local said = {}
	local realMsg = Lodestar.Msg
	Lodestar.Msg = function(_, fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

	Lv.db.profile.xp.strip.buffs = "Well Fed"
	Lv.db.profile.camp.warnMinutes = 5
	Lv.db.profile.camp.foodLow = 5

	-- A buff with plenty of time left says nothing and shows its remaining time on the strip.
	local now = GetTime()
	stub.auras = { { name = "Well Fed", expirationTime = now + 1500, duration = 1800 } }
	stub.bags[0][3] = { itemID = 4540, stackCount = 12, quality = 1 }
	stub.itemClasses = { [4540] = { 0, 5 } }
	Lv:RefreshStrip()
	check(#said == 0, "a buff with 25 minutes left says nothing: " .. table.concat(said, " | "))
	check(math.floor(Lv:BuffRemaining("Well Fed") / 60) == 25, "remaining time read from expirationTime: " .. tostring(Lv:BuffRemaining("Well Fed")))
	local text = LodestarXPFrame.strip.text or ""
	check(text:find("Well Fed 25m", 1, true) ~= nil, "strip shows how long the buff has left: " .. text)
	check(text:find("food |cffffffff12|r", 1, true) ~= nil, "strip counts food and drink in the bags: " .. text)

	-- Inside the warning window: one line, and only one however many refreshes run.
	stub.auras = { { name = "Well Fed", expirationTime = now + 240, duration = 1800 } }
	said = {}
	Lv:RefreshStrip()
	Lv:RefreshStrip()
	check(#said == 1 and said[1]:find("4 minutes left", 1, true) ~= nil, "one warning when the buff is inside the window: " .. table.concat(said, " | "))

	-- The last minute gets its own, louder line even though the first already fired.
	stub.auras = { { name = "Well Fed", expirationTime = now + 30, duration = 1800 } }
	said = {}
	Lv:RefreshStrip()
	check(#said == 1 and said[1]:find("30 seconds", 1, true) ~= nil, "a second warning in the last minute: " .. table.concat(said, " | "))

	-- A buff with no duration is not "about to expire" -- expirationTime 0 means endless, and
	-- treating it as a number is how a permanent buff warns forever.
	stub.auras = { { name = "Well Fed", expirationTime = 0 } }
	said = {}
	Lv:RefreshStrip()
	check(#said == 0, "an endless buff never warns: " .. table.concat(said, " | "))
	check(Lv:BuffRemaining("Well Fed") == nil, "no remaining time for an endless buff")
	check((LodestarXPFrame.strip.text or ""):find("|cff7fff7fWell Fed|r", 1, true) ~= nil, "endless buff shown without a timer")

	-- Food running low warns; running out warns differently.
	stub.bags[0][3] = { itemID = 4540, stackCount = 4, quality = 1 }
	said = {}
	Lv:RefreshStrip()
	check(#said == 1 and said[1]:find("Food and drink: 4 left", 1, true) ~= nil, "low food warns: " .. table.concat(said, " | "))
	stub.bags[0][3] = nil
	said = {}
	Lv:RefreshStrip()
	check(#said == 1 and said[1]:find("No food or drink", 1, true) ~= nil,
		"running out gets its own line even though 'running low' fired a moment ago: " .. table.concat(said, " | "))

	-- Items that are not food are not counted, whatever else is in the bag. Zero still shows --
	-- "food 0" in red is the warning, not an empty space where the count used to be.
	stub.itemClasses = {}
	stub.bags[0][3] = { itemID = 4540, stackCount = 12, quality = 1 }
	Lv:RefreshStrip()
	check(Lv:CampProvisions() == 0, "a non-consumable in the bag is not counted as food: " .. tostring(Lv:CampProvisions()))
	check((LodestarXPFrame.strip.text or ""):find("food |cffff4040" .. "0|r", 1, true) ~= nil, "zero food shows red: " .. (LodestarXPFrame.strip.text or ""))

	-- Warnings and the strip both go quiet when camp tracking is off.
	stub.itemClasses = { [4540] = { 0, 5 } }
	stub.bags[0][3] = { itemID = 4540, stackCount = 1, quality = 1 }
	Lv.db.profile.camp.enabled = false
	said = {}
	Lv:RefreshStrip()
	check(#said == 0 and (LodestarXPFrame.strip.text or ""):find("food ", 1, true) == nil, "camp off is silent")
	Lv.db.profile.camp.enabled = true

	Lodestar.Msg = realMsg
	stub.bags[0][3] = nil
	stub.itemClasses = {}
	stub.auras = { "Well Fed" }
	Lv:RefreshStrip()
end)

-- Professions: rank, cap and the nag that only fires at the cap.
try("professions", function()
	local Lv = Lodestar:GetModule("Leveling")
	local said = {}
	local realMsg = Lodestar.Msg
	Lodestar.Msg = function(_, fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

	stub.professions = { { name = "Skinning", rank = 43, maxRank = 75 }, { name = "Herbalism", rank = 68, maxRank = 75 } }
	stub.professions[5] = { name = "Cooking", rank = 75, maxRank = 75 }
	Lv:RefreshProfessions()
	local list = Lv:Professions()
	check(#list == 3, "all three slots scanned: " .. #list)
	check(list[1].name == "Skinning" and list[1].rank == 43 and list[1].toCap == 32, "rank and distance to the cap")
	check(list[3].capped and list[3].secondary, "a secondary profession at its cap is flagged")
	check(#said == 1 and said[1]:find("Cooking is capped at 75", 1, true) ~= nil, "only the capped one nags: " .. table.concat(said, " | "))
	check(said[1]:find("Journeyman", 1, true) ~= nil, "the nag names the tier that raises the cap: " .. said[1])

	-- Same cap, second refresh: the nag is rate-limited, not repeated per event.
	said = {}
	Lv:RefreshProfessions()
	check(#said == 0, "the cap nag does not repeat: " .. table.concat(said, " | "))

	-- The strip shows what is at or near the cap and stays quiet about the rest.
	local parts = Lv:ProfessionStripParts()
	check(#parts == 2, "strip shows the two professions at or near the cap, not Skinning: " .. #parts)
	check(table.concat(parts, " "):find("Cooking 75/75", 1, true) ~= nil, "capped profession on the strip")
	check(table.concat(parts, " "):find("Skinning", 1, true) == nil, "43/75 is not news")

	-- Points gained are remembered per character across refreshes.
	stub.professions[1] = { name = "Skinning", rank = 50, maxRank = 75 }
	Lv:RefreshProfessions()
	check(Lv.db.char.professions.Skinning.gained == 7, "skill-ups accumulate: " .. tostring(Lv.db.char.professions.Skinning.gained))

	-- A cap this client does not use gets no invented next tier.
	stub.professions = { { name = "Blacksmithing", rank = 112, maxRank = 112 } }
	said = {}
	Lv:RefreshProfessions()
	check(#said == 1 and said[1]:find("Journeyman", 1, true) == nil and said[1]:find("Expert", 1, true) == nil,
		"an unknown cap names no tier: " .. table.concat(said, " | "))

	-- Off means off.
	Lv.db.profile.professions.enabled = false
	Lv:RefreshProfessions()
	check(#Lv:Professions() == 0 and #Lv:ProfessionStripParts() == 0, "professions off clears the list and the strip")
	Lv.db.profile.professions.enabled = true

	-- The reports themselves: format strings with the wrong argument count throw at print time and
	-- nowhere else, so both are run in every shape they can be printed in.
	Lodestar.Msg = realMsg
	local lines = {}
	local realSay = Lodestar.Say
	Lodestar.Say = function(_, fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

	stub.professions = { { name = "Skinning", rank = 43, maxRank = 75 }, { name = "Herbalism", rank = 75, maxRank = 75 } }
	Lodestar:HandleSlash("prof")
	local report = table.concat(lines, "\n")
	check(report:find("Skinning 43/75", 1, true) and report:find("32 to the cap", 1, true), "/lode prof shows the gap to the cap: " .. report)
	check(report:find("Journeyman raises it to 150", 1, true) ~= nil, "/lode prof names the rank that lifts the cap: " .. report)

	lines = {}
	stub.professions = {}
	Lodestar:HandleSlash("prof")
	check(table.concat(lines, "\n"):find("No professions", 1, true) ~= nil, "/lode prof with none learned: " .. table.concat(lines, "\n"))

	lines = {}
	stub.auras = { { name = "Well Fed", expirationTime = GetTime() + 900 } }
	Lodestar:HandleSlash("camp")
	report = table.concat(lines, "\n")
	check(report:find("Well Fed", 1, true) and report:find("15m left", 1, true), "/lode camp shows buff time left: " .. report)
	check(report:find("food and drink", 1, true) ~= nil, "/lode camp reports the food count: " .. report)

	-- A watched buff that is missing is the case worth printing, so it has to survive the report.
	lines = {}
	stub.auras = {}
	Lodestar:HandleSlash("camp")
	check(table.concat(lines, "\n"):find("missing", 1, true) ~= nil, "/lode camp calls out a missing buff: " .. table.concat(lines, "\n"))

	Lodestar.Say = realSay
	stub.auras = { "Well Fed" }
	stub.professions = {}
	Lv:RefreshProfessions()
	Lv:RefreshStrip()
end)

-- Turn-ins to ding
-- Reward XP of quests ready to turn in, read by questID (never via the quest-log selection, which
-- Blizzard's detail pane drives Abandon and Track off), with "(ding!)" once the sum covers the level.
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
	local touched = false
	local realSet = C_QuestLog.SetSelectedQuest
	C_QuestLog.SetSelectedQuest = function(id) touched = true stub.selectedQuest = id end
	stub.fire("QUEST_LOG_UPDATE")
	stub.fire("QUEST_LOG_UPDATE")
	check(select(2, Lv:GetTurnInXP()) == 0, "scan waits for the 1 s throttle")
	stub.advance(1)
	C_QuestLog.SetSelectedQuest = realSet
	local xp, count = Lv:GetTurnInXP()
	check(xp == 1240 and count == 2, "two ready quests summed: " .. tostring(xp) .. " xp / " .. tostring(count))
	check(not touched and stub.selectedQuest == 503, "quest-log selection untouched, got " .. tostring(stub.selectedQuest))
	-- same set of ready quests: served from the cache
	local selections = 0
	C_QuestLog.SetSelectedQuest = function(id) selections = selections + 1 stub.selectedQuest = id end
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	check(selections == 0 and select(1, Lv:GetTurnInXP()) == 1240, "unchanged ready set served from the cache")
	stub.questLog[504] = { title = "Done C", complete = true, objectives = {}, xp = 100 }
	stub.fire("QUEST_LOG_UPDATE") stub.advance(1)
	check(selections == 0 and select(1, Lv:GetTurnInXP()) == 1340, "new ready quest rescans without selecting, got " .. selections .. " selections / " .. tostring(Lv:GetTurnInXP()))
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
	check(LodestarProbes.blocked and LodestarProbes.blocked[1].func == "SomeProtectedFunction", "forbidden call recorded")
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
	stub.advance(1.5)
	check(G.stepIndex == 4, "abandon regressed to the accept step, at " .. tostring(G.stepIndex))
	-- QUEST_REMOVED also fires for a turn-in, and may arrive before QUEST_TURNED_IN: waiting a second
	-- before deciding is what stops a normal turn-in from rewinding the guide to the accept step.
	G:SetStep(16, true)
	stub.questLog[3901] = nil
	stub.fire("QUEST_REMOVED", 3901, false)
	stub.fire("QUEST_TURNED_IN", 3901, 100, 0)
	stub.advance(1.5)
	check(G.stepIndex >= 16, "turn-in delivered after QUEST_REMOVED is not treated as an abandon, at " .. tostring(G.stepIndex))
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
	G:PinSmartItem(nil)
	-- Reported from the beta: "I just reloaded and it's telling me to pick up quests I've already
	-- done." The completed-quest list arrives AFTER you enter the world, and until it does the client
	-- says every quest is uncompleted -- so every "you can pick this up" filter answers wrongly.
	stub.flagged[3901] = true
	stub.questLog = {}
	stub.completedNotLoaded = true
	G:ResetCompletedReady()
	check(not G:CompletedQuestsReady(), "completed list is not trusted before it has loaded")
	local early = G:CollectSmartItems(true)
	local offeredEarly = 0
	for _, it in ipairs(early) do if it.kind == "available" then offeredEarly = offeredEarly + 1 end end
	check(offeredEarly == 0, "nothing is offered for pick-up while the completed list is missing, got " .. offeredEarly)
	stub.completedNotLoaded = nil
	check(G:CompletedQuestsReady(), "... and it is trusted the moment the list arrives")
	local late = G:CollectSmartItems(true)
	local offeredLate, offeredDone = 0, 0
	for _, it in ipairs(late) do
		if it.kind == "available" then
			offeredLate = offeredLate + 1
			if it.questID == 3901 then offeredDone = offeredDone + 1 end
		end
	end
	check(offeredLate > 0, "pick-ups come back once the list has loaded")
	check(offeredDone == 0, "a quest this character already completed is never offered again")
	stub.flagged[3901] = nil
	-- A brand new character really has completed nothing, so an empty list must not withhold forever.
	stub.completedNotLoaded = true
	G:ResetCompletedReady()
	check(not G:CompletedQuestsReady(), "empty list is treated as not-yet-loaded at first")
	stub.advance(13)
	check(G:CompletedQuestsReady(), "... but is trusted after the grace period, so a fresh character is not stuck")
	stub.completedNotLoaded = nil
	G:ResetCompletedReady()
	-- The router: three things clustered together beat one slightly-closer errand on its own, and the
	-- chosen area stays chosen while you work it instead of flickering to whatever is nearest.
	G:ResetSmartPlan()
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.50, 0.50
	stub.questLog = {
		[3901] = { title = "Cluster A1", complete = false, objectives = { { text = "a", finished = false } }, wp = { map = 18, x = 0.560, y = 0.500 } },
		[3902] = { title = "Cluster A2", complete = false, objectives = { { text = "b", finished = false } }, wp = { map = 18, x = 0.563, y = 0.502 } },
		[3903] = { title = "Cluster A3", complete = true,  objectives = {},                                   wp = { map = 18, x = 0.566, y = 0.498 } },
		[3904] = { title = "Lone errand", complete = false, objectives = { { text = "c", finished = false } }, wp = { map = 18, x = 0.530, y = 0.500 } },
	}
	local planned = G:SmartPlan(true)
	check(planned and #planned.plan >= 3, "the plan groups the three neighbours into one area, got " .. tostring(planned and #planned.plan))
	local titles = {}
	for _, it in ipairs(planned.plan) do titles[it.title or "?"] = true end
	check(titles["Cluster A1"] and titles["Cluster A2"] and titles["Cluster A3"], "the dense area wins over the closer lone errand")
	check(not titles["Lone errand"], "the lone errand is left for afterwards")
	local worst = 0
	for i = 2, #planned.plan do
		local a, b = planned.plan[i - 1], planned.plan[i]
		local d = math.abs(a.x - b.x) + math.abs(a.y - b.y)
		if d > worst then worst = d end
	end
	check(worst > 0 and worst < 0.02, "plan is ordered as a short walk, worst hop " .. string.format("%.4f", worst))
	-- Stickiness: finishing one item must not hand the area over to the lone errand.
	stub.questLog[3903] = nil
	local again = G:SmartPlan(true)
	local stillThere = false
	for _, it in ipairs(again.plan) do if (it.title or ""):find("Cluster A") then stillThere = true end end
	check(stillThere and again.area and again.area.sticky, "the area stays chosen while it still has work")
	-- Reported from the beta: "the arrow tells me to go back and doesn't adjust even though I'm
	-- running towards the new place." Everything here is inside the old 500 yd release radius on
	-- purpose -- in a starting zone it always is, which is why the old rule never let go.
	G:ResetSmartPlan()
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.500, 0.500
	stub.questLog = {
		[3901] = { title = "Behind me A", complete = false, objectives = { { text = "a", finished = false } }, wp = { map = 18, x = 0.480, y = 0.500 } },
		[3902] = { title = "Behind me B", complete = false, objectives = { { text = "b", finished = false } }, wp = { map = 18, x = 0.478, y = 0.501 } },
		[3903] = { title = "Ahead C",     complete = false, objectives = { { text = "c", finished = false } }, wp = { map = 18, x = 0.540, y = 0.500 } },
		[3904] = { title = "Ahead D",     complete = false, objectives = { { text = "d", finished = false } }, wp = { map = 18, x = 0.542, y = 0.501 } },
	}
	local function leads(pl) return (pl.plan[1] and pl.plan[1].title) or "?" end
	local first = G:SmartPlan(true)
	check(leads(first):find("Behind me"), "starts on the nearer pair behind us: " .. leads(first))
	-- run east past them, staying well inside 500 yd of the area we are leaving
	for _, x in ipairs({ 0.505, 0.510, 0.515 }) do
		stub.playerMap.x = x
		G:SmartPlan(true)
	end
	local after = G:SmartPlan(true)
	check(leads(after):find("Ahead"), "running towards the new area hands the arrow over to it, got " .. leads(after))
	G:ResetSmartPlan()
	stub.questLog = {}
	stub.playerMap.x, stub.playerMap.y = 0.500, 0.500
	-- The window shows the plan as a numbered walk under an area header, not kind buckets.
	G:RefreshStepFrame()
	local seen, ordinals = {}, 0
	for _, r in ipairs(LodestarGuideFrame.actionRows or {}) do
		if r.shown then
			local main = (r.main and r.main.text) or ""
			local glyph = (r.glyph and r.glyph.text) or ""
			seen[#seen + 1] = main
            if glyph:find("%d%.") then ordinals = ordinals + 1 end
		end
	end
	local joined = table.concat(seen, " | ")
	check(joined:find("This area", 1, true) or joined:find("Next area", 1, true), "window heads the plan with its area: " .. joined)
	check(ordinals >= 2, "plan rows are numbered as a walk, got " .. ordinals)
	G:ResetSmartPlan()
	stub.questLog = {}
	stub.questLog[3901] = { title = "Rattling the Rattlecages", complete = false, objectives = { { text = "x: 0/8", finished = false } }, wp = { map = 18, x = 0.33, y = 0.66 } }
	stub.playerMap.x, stub.playerMap.y = 0.33, 0.66
	G:RefreshStepFrame()
	check(LodestarGuideFrame.title.text and LodestarGuideFrame.title.text:find("smart mode"), "window shows smart mode")
	-- level 10 picks the 5-12 guide; level 40 has nothing and must not load an outleveled guide
	stub.level = 10
	check(G:PickGuide() and G:PickGuide().name == "Horde/Undead 5-12: Tirisfal Glades", "level 10 picks the Tirisfal guide")
	stub.level = 40
	check(G:PickGuide() == nil, "outleveled guides are not auto-picked")
	-- Skyborne starts on Zephras Isle, and the generated route for it is what a level 2 Skyborne
	-- must get. Before that route existed the only guides passing the race filter were the
	-- faction-wide 12-20 ones, and a new character was handed a level 12 zone.
	local realRace = UnitRace
	UnitRace = function() return "Skyborne", "Skyborne", 99 end
	stub.level = 2
	local pick = G:PickGuide()
	check(pick and pick.name == "Skyborne 1-12: Zephras Isle", "a level 2 Skyborne gets the Zephras route, got " .. tostring(pick and pick.name))
	stub.level = 11
	pick = G:PickGuide()
	check(pick and pick.name == "Skyborne 1-12: Zephras Isle", "and still has it at 11, got " .. tostring(pick and pick.name))

	-- A race with no starting route at all still must not be handed a zone twelve levels away, and
	-- must still get the level-grace pick once it is nearly there. Both halves of that were the
	-- original bug, so both stay covered by a race nothing has been authored for.
	UnitRace = function() return "Mechagnome", "Mechagnome", 98 end
	stub.level = 2
	check(G:PickGuide() == nil, "a race with no starting route falls to smart mode, not a 12-20 guide")
	stub.level = 11
	local near = G:PickGuide()
	check(near and near.minLevel == 12, "a route starting within the grace is still picked at 11, got " .. tostring(near and near.name))
	UnitRace = realRace
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
	check(LodestarProbes.guideDiag and LodestarProbes.guideDiag.quests[3901], "diag saved per-quest details")
	stub.slash("/lode guide next")
	stub.slash("/lode guide prev")
end)
try("harvest", function()
	local H = G:HarvestDB()
	check(H and H.npcs, "LodestarScans initialised")
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
	local S = G:ScanDB()
	stub.slash("/lode scan quests 360 366")
	stub.advance(3)
	check(S.scan.found and S.scan.found >= 1 and H.quests[364] and H.quests[364].scanned, "quest scan found 364: " .. tostring(S.scan.found))
	check(S.scan.next and S.scan.next > 366, "scan ran to the end of the range")
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

-- Wider passive capture: who really gave a quest, objective areas, vendor stock, trainers, taxi edges
-- and the zone text that makes all of it checkable by eye.
try("harvest capture", function()
	local H = G:HarvestDB()
	local savedMap, savedX, savedY = stub.playerMap.map, stub.playerMap.x, stub.playerMap.y
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.308, 0.662
	-- These blocks teleport the player around map 18 to make objective samples spread out; the trail
	-- recorder would count every stop as walked ground and throw off the trails block below.
	G.db.profile.trails.record = false
	stub.fire("GOSSIP_SHOW")                      -- npc 6's window is open: a live interaction
	check(H.npcs[6] and H.npcs[6].zone == "Elwynn Forest" and H.npcs[6].subzone == "Northshire Valley", "zone and subzone recorded with the exact position")
	-- an item-started quest: Blizzard hands the item id with QUEST_DETAIL, and the NPC we were just
	-- talking to must not be credited for it
	local realGetQuestID = GetQuestID
	GetQuestID = function() return 8801 end
	stub.fire("QUEST_DETAIL", 6948)
	stub.fire("QUEST_ACCEPTED", 8801)
	GetQuestID = realGetQuestID
	local q = H.quests[8801]
	check(q and q.src == "item" and q.item == 6948, "item-started quest tagged src=item: " .. tostring(q and q.src))
	check(q and q.giver == nil, "item-started quest did not credit the last NPC talked to")
	check(q and q.acceptAt and q.acceptAt[1] == 18 and q.acceptAt[4] == "Elwynn Forest", "item-started quest recorded where the player stood, with the zone")
	check(q and q.races and q.races.Scourge and q.classes and q.classes.WARRIOR, "the contributor's race and class ride along, so the merge can spot class/race quests")
	-- a party share is credited to the share, not to whoever is on screen
	stub.fire("GOSSIP_SHOW")
	stub.fire("QUEST_ACCEPT_CONFIRM", "Bob", "Escort")
	stub.fire("QUEST_ACCEPTED", 8802)
	check(H.quests[8802] and H.quests[8802].src == "share" and H.quests[8802].giver == nil, "party-shared quest tagged src=share: " .. tostring(H.quests[8802] and H.quests[8802].src))
	-- an offer from an open NPC window still credits that NPC
	stub.fire("GOSSIP_SHOW")
	stub.fire("QUEST_DETAIL")
	stub.fire("QUEST_ACCEPTED", 7)
	check(H.quests[7].giver == 6 and H.quests[7].src == "npc", "a live NPC window still credits the NPC: " .. tostring(H.quests[7].src))
	-- ...but a closed one does not, however recently it was open
	stub.fire("QUEST_FINISHED")
	stub.fire("QUEST_ACCEPTED", 8803)
	check(H.quests[8803] and H.quests[8803].giver == nil and H.quests[8803].src == "unknown", "no live frame: nobody is credited")
	-- quest metadata straight out of the log: title, level, suggested group size, money wanted up front
	local realInfo, metaLog = C_QuestLog.GetInfo, stub.questLog
	C_QuestLog.GetInfo = function(i)
		local info = realInfo(i)
		if info and info.questID == 8811 then info.level, info.suggestedGroup = 24, 5 end
		return info
	end
	stub.questRequiredMoney[8811] = 6000
	stub.questLog = { [8811] = { title = "Group Job", complete = false, objectives = {} } }
	stub.fire("QUEST_ACCEPTED", 8811)
	C_QuestLog.GetInfo, stub.questLog = realInfo, metaLog
	local gq = H.quests[8811]
	check(gq and gq.t == "Group Job" and gq.lvl == 24 and gq.group == 5, "title, level and suggested group size read from the log: " .. tostring(gq and gq.group))
	check(gq and gq.req == 6000, "money the quest wants up front, via C_QuestLog.GetRequiredMoney (GetQuestLogRequiredMoney does not exist on this client)")
	-- objective ticks: spread samples, deduped within ~2 map-percent, capped at 6
	local savedLog = stub.questLog
	stub.questLog = { [8810] = { title = "Spread", complete = false, objectives = { { text = "Thing: 0/9", finished = false } } } }
	stub.fire("QUEST_LOG_UPDATE") stub.advance(0.5)
	local function tick(n, x, y)
		stub.playerMap.x, stub.playerMap.y = x, y
		stub.questLog[8810].objectives[1].text = ("Thing: %d/9"):format(n)
		stub.fire("QUEST_LOG_UPDATE")
		stub.advance(0.5)
	end
	stub.fire("PLAYER_TARGET_CHANGED")
	tick(1, 0.10, 0.10)
	check(H.npcs[6].objGuess and H.npcs[6].objGuess[8810], "a counter that moved while a mob was targeted is kept as weak evidence for the link")
	tick(2, 0.101, 0.101)                         -- 0.1 percent away: the same spot
	for i = 3, 9 do tick(i, 0.10 + (i - 2) * 0.05, 0.10) end
	local prog = H.quests[8810] and H.quests[8810].prog and H.quests[8810].prog[1]
	check(prog and #prog == 6, "objective samples spread out and stop at 6, got " .. tostring(prog and #prog))
	check(prog and prog[1][4] == "Elwynn Forest" and prog[1][5] == "Northshire Valley", "objective samples carry the zone text")
	-- the tick that finishes an objective is recorded too
	stub.playerMap.x, stub.playerMap.y = 0.80, 0.80
	stub.questLog[8810].objectives[1] = { text = "Thing: 9/9", finished = true }
	stub.fire("QUEST_LOG_UPDATE") stub.advance(0.5)
	check(H.quests[8810].fin and H.quests[8810].fin[1] and H.quests[8810].fin[1][1] == 18, "the finishing tick records the finish spot")
	stub.questLog = savedLog
	stub.fire("QUEST_LOG_UPDATE") stub.advance(0.5)
	stub.playerMap.x, stub.playerMap.y = 0.308, 0.662
	-- vendors: the item ids are what makes .buy steps authorable
	stub.merchantItems = { 1234, 2320, 5555 }
	stub.fire("MERCHANT_SHOW")
	stub.advance(2)
	check(H.npcs[6].kind.vendor and H.npcs[6].sells and H.npcs[6].sells[1234] and H.npcs[6].sells[2320] and H.npcs[6].sells[5555], "merchant stock recorded as item ids")
	stub.fire("MERCHANT_CLOSED")
	-- trainers: the trade-skill flag next to the class tag
	stub.tradeskillTrainer = true
	stub.fire("TRAINER_SHOW")
	check(H.npcs[6].kind.trainer and H.npcs[6].kind.tradeskill, "trade-skill trainer flagged as such")
	stub.fire("TRAINER_CLOSED")
	stub.tradeskillTrainer = false
	H.npcs[6].kind.trainer, H.npcs[6].kind.tradeskill = nil, nil
	-- taxi: node <-> flight master, and edges that accumulate whatever order the client lists nodes in
	local realNodes = C_TaxiMap.GetAllTaxiNodes
	stub.fire("TAXIMAP_OPENED")
	check(H.taxi[10].links and H.taxi[10].links[11], "first visit: the edge to node 11")
	check(H.taxi[10].npc == 6 and H.npcs[6].taxiNode == 10, "the flight master is linked to the node he stands on")
	check(H.taxi[10].zone == "Elwynn Forest", "the node we stand on carries the zone name")
	-- second visit: the current node is listed LAST and a new destination is listed first
	C_TaxiMap.GetAllTaxiNodes = function() return {
		{ nodeID = 13, name = "Undercity", position = { GetXY = function() return 0.4, 0.4 end }, state = 1 },
		{ nodeID = 11, name = "The Sepulcher, Silverpine Forest", position = { GetXY = function() return 0.5, 0.6 end }, state = 2 },
		{ nodeID = 10, name = "Brill, Tirisfal Glades", position = { GetXY = function() return 0.6, 0.5 end }, state = 0 },
	} end
	stub.fire("TAXIMAP_OPENED")
	C_TaxiMap.GetAllTaxiNodes = realNodes
	check(H.taxi[10].links[11] and H.taxi[10].links[13], "edges accumulate: 13 added with the current node listed last, 11 kept")
	check(H.taxi[11].state == "reachable", "a node once seen reachable is not downgraded")
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = savedMap, savedX, savedY
end)

-- /lode share: where the file is, what is in it, and who contributed
-- The client's own next-objective waypoint, harvested for every quest in the log.
-- Forever exposes no quest POIs, so before this the only way a quest got an objective position was
-- a player standing on the spot at the moment a counter moved. This gets a rough one the instant
-- the quest is accepted, which is most of what the arrow needs.
try("quest waypoints", function()
	local H = G:HarvestDB()
	H.quests[8801] = nil
	stub.questLog[8801] = { title = "Waypointed", complete = false,
		objectives = { { text = "x: 0/5", finished = false } }, wp = { map = 18, x = 0.4127, y = 0.6663 } }
	G:HarvestWaypoints()
	local q = H.quests[8801]
	check(q and q.wp and q.wp[1] == 18, "waypoint recorded with its map: " .. tostring(q and q.wp and q.wp[1]))
	-- Stored in percent, like every other position in the harvest, rounded to a tenth.
	check(q.wp[2] == 41.3 and q.wp[3] == 66.6, "fractions converted to percent: " .. tostring(q.wp[2]) .. "," .. tostring(q.wp[3]))

	-- It is the last resort, so a quest with nothing else gets an arrow from it.
	local map, x, y, how = G:HarvestQuestPosition(8801, false)
	check(map == 18 and how == "waypoint" and math.abs(x - 0.413) < 0.001, "position falls back to the waypoint: " .. tostring(how))

	-- A player who actually stood on the objective outranks it.
	q.prog = { [1] = { { 18, 20.0, 30.0, "Zone", "Sub" } } }
	map, x, y, how = G:HarvestQuestPosition(8801, false)
	check(how == "progress" and math.abs(x - 0.2) < 0.001, "a real sighting still wins: " .. tostring(how))
	q.prog = nil

	-- 0,0 is what the client returns for "no waypoint", not a position in the corner of the map.
	H.quests[8802] = nil
	stub.questLog[8802] = { title = "Nowhere", complete = false, objectives = {}, wp = { map = 18, x = 0, y = 0 } }
	G:HarvestWaypoints()
	check(H.quests[8802] == nil or H.quests[8802].wp == nil, "an empty waypoint is not recorded as the map corner")

	-- The sweep is throttled: a quest log that updates every second must not rewrite the harvest
	-- every second.
	stub.questLog[8801].wp = { map = 18, x = 0.9, y = 0.9 }
	stub.fire("QUEST_LOG_UPDATE")
	check(H.quests[8801].wp[2] == 41.3, "a second sweep inside the throttle is skipped")
	stub.advance(11)
	stub.fire("QUEST_LOG_UPDATE")
	check(H.quests[8801].wp[2] == 90, "and runs once the throttle has passed: " .. tostring(H.quests[8801].wp[2]))

	stub.questLog[8801] = nil
	stub.questLog[8802] = nil
	H.quests[8801] = nil
	H.quests[8802] = nil
end)

-- Travel hints: hearth and flight, but only when the detour actually saves something.
-- The failure mode worth guarding is a hint that sends the player to an inn further from the target
-- than they already are, so every check here is about the saving rather than about the wording.
-- Corpse run: while a ghost, the body is the only thing worth pointing at.
try("corpse arrow", function()
	local wasMode = G.db.profile.arrow.mode
	G.db.profile.arrow.mode = "AUTO"
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.308, 0.662

	-- Alive: whatever the guide or the quest log says.
	stub.ghost = false
	G:RetargetArrow()
	local alive = G:GetArrowTarget()
	check(not alive or alive.kind ~= "corpse", "no corpse target while alive")

	-- A ghost with a body on this map: the body, ahead of everything else including a pin.
	stub.ghost = true
	stub.corpse = { map = 18, x = 0.44, y = 0.51 }
	G:PinPosition(18, 0.9, 0.9, "Pinned thing")
	G:RetargetArrow()
	local t = G:GetArrowTarget()
	check(t and t.kind == "corpse" and t.mapID == 18 and math.abs(t.x - 0.44) < 0.001,
		"a ghost is pointed at the corpse, ahead of a pin: " .. tostring(t and t.kind))
	check(t.title == "Your corpse", "and it is labelled as such: " .. tostring(t.title))

	-- The client answers 0,0 for a corpse that is not on this map. That is not a body in the
	-- top-left corner, and pointing there is worse than leaving the arrow where it was.
	stub.corpse = { map = 99, x = 0.44, y = 0.51 }
	G:RetargetArrow()
	t = G:GetArrowTarget()
	check(not t or t.kind ~= "corpse", "0,0 from another map is not treated as a position")

	-- Back alive: normal targeting resumes.
	stub.ghost = false
	stub.corpse = nil
	G:ClearPinnedPosition()
	G:RetargetArrow()
	t = G:GetArrowTarget()
	check(not t or t.kind ~= "corpse", "corpse target released on resurrection")
	G.db.profile.arrow.mode = wasMode
end)

try("travel hints", function()
	local hearthWas = G.db.char.hearth
	G.db.profile.travel.hints = true
	stub.hearthCooldown = nil                       -- ready

	-- The hearth is bound where the player stands; record it the way the client tells us.
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.30, 0.66
	stub.bindLocation = "Deathknell"
	stub.fire("HEARTHSTONE_BOUND")
	local h = G.db.char.hearth
	check(h and h.map == 18 and h.name == "Deathknell", "hearth position recorded on bind: " .. tostring(h and h.name))

	-- A target far from the player but right next to the inn: hearthing is the answer.
	local nearHearth = { mapID = 18, x = 0.305, y = 0.664 }
	local hint = G:TravelHint(nearHearth, 4000)
	check(hint and hint:find("Hearth", 1, true) and hint:find("Deathknell", 1, true), "hearth suggested for a far target next to the inn: " .. tostring(hint))

	-- The same target while the hearthstone is on cooldown: no suggestion, because it is not an
	-- option the player has.
	G:TravelHint(nil, nil)                          -- drop the 5 s cache
	stub.advance(6)
	stub.hearthCooldown = { GetTime(), 1800 }
	check(G:TravelHint(nearHearth, 4000) == nil, "nothing suggested while the hearthstone is on cooldown")
	stub.hearthCooldown = nil
	stub.advance(6)

	-- A target the player is already close to: running is fine, say nothing. This is the one that
	-- matters -- a hint here would send someone to an inn and back.
	check(G:TravelHint({ mapID = 18, x = 0.30, y = 0.661 }, 120) == nil, "no hint for a target within running distance")

	-- A far target that the inn is no closer to: also nothing.
	stub.advance(6)
	check(G:TravelHint({ mapID = 18, x = 0.90, y = 0.90 }, 4000) == nil, "no hint when the inn saves nothing")

	-- Off by option.
	stub.advance(6)
	G.db.profile.travel.hints = false
	G:DisableTravel()
	G.db.profile.travel.hints = true
	G:EnableTravel()

	G.db.char.hearth = hearthWas
	stub.playerMap.map, stub.playerMap.x, stub.playerMap.y = 18, 0.308, 0.662
end)

try("harvest share", function()
	local sum = G:HarvestSummary()
	check(sum.quests > 0 and sum.npcs > 0 and sum.taxi >= 3 and sum.positions > 0, "summary counts the world data")
	local me = G:HarvestDB().meta.contributors["Venz-ClassicBetaPvP2"]
	check(sum.contributors == 1 and me, "the logged-in character is recorded as a contributor, got " .. sum.contributors)
	check(me and me.class == "WARRIOR" and me.race == "Scourge" and me.faction == "Horde" and me.level and me.first and me.last and (me.sessions or 0) >= 1, "contributor row filled in")
	check(G:HarvestDB().meta.v == 1 and G:HarvestDB().meta.build == "69893", "meta carries the format version and the client build")
	local before = #stub.chat
	stub.slash("/lode share")
	local text = table.concat(stub.chat, "\n", before + 1, #stub.chat)
	check(text:find("WTF\\Account\\<ACCOUNT>\\SavedVariables\\Lodestar_Guide.lua", 1, true) ~= nil, "share prints the file path: " .. text)
	check(text:find("does not tell addons", 1, true) ~= nil, "share says the account folder name is not knowable from an addon")
	check(text:find(sum.quests .. "|r quests", 1, true) ~= nil and text:find(sum.npcs .. "|r NPCs", 1, true) ~= nil, "share prints the counts: " .. text)
	check(text:find("/reload", 1, true) ~= nil, "share reminds you to /reload first")
	local lines = {}
	local tt = { AddDoubleLine = function(_, l, r) lines[l] = r end, AddLine = function() end }
	for _, fn in ipairs(Lodestar.tooltipProviders) do fn(tt) end
	check(lines["Harvested world data"] and lines["Harvested world data"]:find(sum.quests .. " quests", 1, true), "minimap tooltip line: " .. tostring(lines["Harvested world data"]))
	check(G.options.harvestDesc.name():find(sum.npcs .. "|r NPCs", 1, true) ~= nil, "settings page description carries the counts")
	stub.slash("/lode harvest")
end)

-- Live delta sync: dormant on a restricted realm, one small message at a time, nothing relayed
try("harvest sync", function()
	local H = G:HarvestDB()
	G.db.profile.harvest.share = true
	G:StartHarvestSync()
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Activating)
	stub.commRestricted = true
	check(not G:HarvestSyncStats().running, "the delta ticker is off while comms are restricted")
	local before = #stub.sent
	H.npcs[4242] = { name = "Delta Test", seen = 1, map = 18, x = 12.5, y = 34.5, exact = true }
	G:QueueHarvestDelta("npc", 4242, H.npcs[4242])
	check(G:HarvestSyncStats().queued == 1, "the fact is queued while comms are restricted")
	check(G:FlushHarvestDelta() == false and #stub.sent == before, "nothing is sent while restricted")
	stub.advance(30)
	check(#stub.sent == before, "and nothing leaks out of a timer either")
	-- comms come back: the core fans out to Guide:OnCommAvailabilityChanged, no reload needed
	stub.commRestricted = false
	stub.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
	stub.advance(0.1)
	check(G:HarvestSyncStats().running, "the delta ticker started when availability flipped")
	check(G:FlushHarvestDelta() == true, "the queued delta goes out once comms are available")
	local msg = stub.sent[#stub.sent]
	check(msg.dist == "GUILD" and msg.msg:match("%^St%^S(%a)") == "H", "delta sent to the guild as a H message: " .. tostring(msg.msg))
	check(#msg.msg < 255, "one delta fits in a single addon message, " .. #msg.msg .. " bytes")
	check(G:HarvestSyncStats().queued == 0, "the queue drained")
	-- rate limit: a second delta inside the interval is refused
	H.npcs[4243] = { name = "Delta Two", seen = 1, map = 18, x = 20, y = 20, exact = true }
	G:QueueHarvestDelta("npc", 4243, H.npcs[4243])
	before = #stub.sent
	check(G:FlushHarvestDelta() == false and #stub.sent == before, "a second delta inside 15 s is rate-limited")
	stub.advance(16)
	check(#stub.sent > before, "and goes out on the next tick")
	-- incoming: everything is untrusted
	local function deliver(m) Lodestar:OnCommReceived("Lodestar", Lodestar:Serialize(m), "GUILD", "Stranger") end
	local dropsBefore = G:HarvestSyncStats().dropped
	deliver({ t = "H", n = {
		{ -5, 18, 10, 10, "Negative id" },
		{ 991, 18, 900, 10, "Coordinate out of range" },
		{ 992, 0, 10, 10, "Map id zero" },
		{ 993, 18, 40.5, 60.5, "Good Stranger" },
	} })
	check(H.npcs[-5] == nil and H.npcs[991] == nil and H.npcs[992] == nil, "malformed delta rows dropped in silence")
	check(G:HarvestSyncStats().dropped == dropsBefore + 3, "three rows dropped, got " .. (G:HarvestSyncStats().dropped - dropsBefore))
	check(H.npcs[993] and H.npcs[993].map == 18 and H.npcs[993].x == 40.5 and H.npcs[993].name == "Good Stranger" and H.npcs[993].via == "comm", "a good row merges, marked second-hand")
	deliver({ t = "H", n = { { 992, 18, 10, 10, string.rep("x", 200) } } })
	check(H.npcs[992] and H.npcs[992].name == nil, "an over-long name is dropped, the position is not")
	-- a fact we found ourselves is never overwritten by a delta
	deliver({ t = "H", n = { { 4242, 55, 1, 1, "Impostor" } } })
	check(H.npcs[4242].map == 18 and H.npcs[4242].x == 12.5 and H.npcs[4242].via == nil, "an exact position we found ourselves wins")
	-- and nothing second-hand is ever forwarded
	local queued = G:HarvestSyncStats().queued
	G:QueueHarvestDelta("npc", 993, H.npcs[993])
	check(G:HarvestSyncStats().queued == queued, "a fact learned over the channel is never relayed")
	-- quest and flight-point rows
	deliver({ t = "H", q = { { 8850, 991, 0 }, { 8851, 0, 0 } }, f = { { 77, 18, 30, 30, "Delta Point" } } })
	check(H.quests[8850] and H.quests[8850].giver == 991 and H.quests[8850].via == "comm", "quest delta merged as second-hand")
	check(H.quests[8851] == nil, "a quest row naming neither giver nor ender is dropped")
	check(H.taxi[77] and H.taxi[77].map == 18 and H.taxi[77].via == "comm", "flight point delta merged")
	-- the toggle
	stub.slash("/lode harvest sync off")
	check(G.db.profile.harvest.share == false and not G:HarvestSyncStats().running, "/lode harvest sync off stops it")
	before = #stub.sent
	G:QueueHarvestDelta("npc", 4244, { seen = 1, map = 18, x = 5, y = 5, exact = true, name = "Nope" })
	check(G:HarvestSyncStats().queued == queued, "nothing is even queued while sync is off")
	stub.advance(20)
	check(#stub.sent == before, "nothing sent while sync is off")
	stub.slash("/lode harvest sync on")
	check(G.db.profile.harvest.share == true and G:HarvestSyncStats().running, "/lode harvest sync on starts it again")
	stub.slash("/lode harvest sync nonsense")
	-- park it again so the blocks below can count guild traffic
	G.db.profile.harvest.share = false
	G:StopHarvestSync()
end)

-- Destructive commands: the census cursor and the harvest are wiped by different commands, and the
-- harvest wipe keeps a backup (the author lost a harvest to `/lode scan wipe` once).
try("harvest wipes", function()
	local H, S = G:HarvestDB(), G:ScanDB()
	S.scan.from, S.scan.to, S.scan.next, S.scan.found = 1, 900, 400, 12
	local npcs, quests = 0, 0
	for _ in pairs(H.npcs) do npcs = npcs + 1 end
	for _ in pairs(H.quests) do quests = quests + 1 end
	check(npcs > 0 and quests > 0, "there is a harvest to protect")
	stub.slash("/lode scan wipe")
	check(S.scan.found == 12, "scan wipe without confirm changes nothing")
	check((stub.chat[#stub.chat] or ""):find("/lode harvest wipe", 1, true) ~= nil, "scan wipe points at the other command for the harvest itself")
	stub.slash("/lode scan wipe confirm")
	check(next(S.scan) == nil, "scan wipe confirm resets the census cursor")
	local after = 0
	for _ in pairs(H.npcs) do after = after + 1 end
	check(after == npcs and next(H.quests) ~= nil and next(H.taxi) ~= nil, "scan wipe confirm left every harvested NPC, quest and flight node alone: " .. after .. " vs " .. npcs)
	check((stub.chat[#stub.chat] or ""):find("NOT touched", 1, true) ~= nil, "and says so")
	-- the harvest itself needs two confirmations
	stub.slash("/lode harvest wipe")
	check(next(H.npcs) ~= nil, "harvest wipe without confirm changes nothing")
	stub.slash("/lode harvest wipe confirm")
	check(next(H.npcs) ~= nil, "harvest wipe confirm on its own still changes nothing")
	check((stub.chat[#stub.chat] or ""):find("yes-really", 1, true) ~= nil, "the second phrase is spelled out")
	stub.slash("/lode harvest wipe yes-really")
	check(next(H.npcs) == nil and next(H.quests) == nil and next(H.taxi) == nil and next(H.objects) == nil, "the second phrase clears the world data")
	-- the backup lives in the local-only DB, so a shared Lodestar_Guide.lua never carries it
	check(H.backup == nil, "the backup is not kept in the shareable table")
	local slot = G:ScanDB().backup
	check(slot and next(slot.npcs) ~= nil and slot.at, "a backup was stashed in the local DB")
	check((stub.chat[#stub.chat - 1] or ""):find(npcs .. " NPCs", 1, true) ~= nil, "counts printed on the wipe: " .. tostring(stub.chat[#stub.chat - 1]))
	check(G:ScanDB().trails ~= nil, "a harvest wipe does not touch the trails")
	-- ...and it comes back
	stub.slash("/lode harvest restore")
	after = 0
	for _ in pairs(H.npcs) do after = after + 1 end
	check(after == npcs, "restore brought every NPC back: " .. after .. " vs " .. npcs)
	after = 0
	for _ in pairs(H.quests) do after = after + 1 end
	check(after == quests and next(H.taxi) ~= nil, "restore brought the quests and flight nodes back: " .. after .. " vs " .. quests)
	check((stub.chat[#stub.chat - 1] or ""):find(npcs .. " NPCs", 1, true) ~= nil, "counts printed on the restore")
	-- a second wipe must not replace the backup with the nothing it finds
	stub.slash("/lode harvest wipe yes-really")
	local kept = G:ScanDB().backup
	check(next(kept.npcs) ~= nil, "the backup holds the data the first wipe took")
	stub.slash("/lode harvest wipe yes-really")
	check(G:ScanDB().backup == kept and next(kept.npcs) ~= nil, "wiping an already empty harvest keeps the backup the first wipe made")
	stub.slash("/lode harvest restore")
	after = 0
	for _ in pairs(H.npcs) do after = after + 1 end
	check(after == npcs, "and the data is still there to restore: " .. after .. " vs " .. npcs)
	stub.slash("/lode harvest nonsense")
end)

-- The one-time split: world data moves out of LodestarScanDB, the census cursor and trails stay put
try("harvest migration", function()
	local share, account = _G.LodestarHarvest, _G.LodestarScans
	_G.LodestarHarvest = nil
	_G.LodestarScans = {
		v = 1, build = "69893",
		npcs = { [42] = { name = "Old Timer", seen = 3, map = 18, x = 10, y = 20, exact = true } },
		objects = { [7] = { name = "Old Chest", seen = 1, map = 18, x = 1, y = 2 } },
		quests = { [99] = { t = "Old Quest", giver = 42 } },
		taxi = { [3] = { name = "Old Node", map = 18, x = 5, y = 5, state = "reachable" } },
		levels = { [5] = 1000 },
		trails = { [18] = { nx = 500, ny = 500, n = 3, l = 2, rows = {} } },
		scan = { from = 1, to = 100, next = 101, found = 7, finishedAt = 123 },
	}
	G:HarvestBindDB()
	local W, A = G:HarvestDB(), G:ScanDB()
	check(W.npcs[42] and W.npcs[42].name == "Old Timer" and W.objects[7] and W.quests[99] and W.taxi[3] and W.levels[5] == 1000, "world data moved into LodestarHarvest")
	check(A.npcs == nil and A.objects == nil and A.quests == nil and A.taxi == nil and A.levels == nil, "world data removed from LodestarScans")
	check(A.scan.found == 7 and A.scan.next == 101 and A.trails[18] and A.trails[18].n == 3, "the census cursor and the trails stayed behind")
	check(A.migrated, "a migration marker was left")
	check(W.meta and W.meta.v == 1 and type(W.meta.contributors) == "table", "meta created on the shared db")
	local marker = A.migrated
	G:HarvestBindDB()
	check(A.migrated == marker and W.npcs[42] ~= nil, "loading again does not migrate again")
	_G.LodestarHarvest, _G.LodestarScans = share, account
	G:HarvestBindDB()
	check(G:HarvestDB() == share and G:ScanDB() == account, "saved variables rebound for the rest of the run")
	G.db.profile.trails.record = true
end)

try("trails", function()
	-- Until Guide.lua / the TOC wire them up, load the trail files and enable the recorder here.
	if not G.TrailPath then loadLua("Lodestar_Guide/Trails.lua") end
	if not G.TrailSeed then loadLua("Lodestar_Guide/Data/Trails_Seed.lua") end
	G:EnableTrails()
	local T = G:ScanDB().trails
	check(type(T) == "table", "LodestarScans.trails created")
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
	-- a drop: one cell of map movement but a cliff's worth of height. Linking it would tell A* the
	-- cliff face is walkable in both directions, which is how the arrow sends you off a bluff.
	links = T[18].l
	stub.playerMap.x, stub.playerMap.y, stub.playerZ = 0.600, 0.600, 0
	stub.advance(1)
	stub.playerMap.x, stub.playerZ = 0.602, -40
	stub.advance(1)
	check(T[18].l == links, "a 40 yd drop between samples did not create a link")
	-- ... while a bunny-hop over the same ground still links: a jump is a couple of yards, not a fall
	stub.falling = true
	stub.playerMap.x, stub.playerZ = 0.604, -38
	stub.advance(1)
	check(T[18].l > links, "hopping along a road still links, got +" .. (T[18].l - links))
	stub.falling, stub.playerZ = false, 0
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
	check(LodestarGuideFrame.headline.text and LodestarGuideFrame.headline.text:find("(optional)", 1, true), "window tags the optional step: " .. tostring(LodestarGuideFrame.headline.text))
	G:SetCompletionist(false)
	G:SetStep(1, true) G:EvaluateStep()
	check(G.stepIndex == 6, "speed run skips the optional step again (buy, profession done; item step gated), at " .. tostring(G.stepIndex))
	-- upcoming rows leave out steps that do not apply (optional in speed-run mode, item-gated without the item)
	local function upcomingTexts()
		local texts = {}
		for _, row in ipairs(LodestarGuideFrame.upcomingRows) do
			if row.shown and row.main.text and row.main.text ~= "" then tinsert(texts, (row.main.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
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
	check(G:HarvestDB().npcs[6].kind.tradeskill == true, "the tradeskill flag was harvested instead")
	-- ... and that flag is what the Leveling module's cap nag reaches for across the module
	-- boundary. Guide is an optional dependency of Leveling, so this is the path that breaks first
	-- if either side is loaded without the other.
	local near = G:NearestTradeskillTrainer(300)
	check(near and near.npcID == 6 and near.dist == 0, "nearest tradeskill trainer found from the harvest: " .. tostring(near and near.npcID))
	check(G:NearestTradeskillTrainer(-1) == nil, "range is honoured")
	do
		local Lv = Lodestar:GetModule("Leveling")
		local said = {}
		local realMsg = Lodestar.Msg
		Lodestar.Msg = function(_, fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
		stub.professions = { { name = "Mining", rank = 150, maxRank = 150 } }
		Lv:RefreshProfessions()
		check(#said == 1 and said[1]:find("Expert raises it to 225", 1, true), "cap nag names the next rank: " .. table.concat(said, " | "))
		check(said[1]:find("yd away", 1, true) ~= nil, "cap nag points at the harvested tradeskill trainer: " .. said[1])
		Lodestar.Msg = realMsg
		stub.professions = {}
		Lv:RefreshProfessions()
	end
	G:HarvestDB().npcs[6].trains = nil G:HarvestDB().npcs[6].kind.trainer = nil
	G:HarvestDB().npcs[6].kind.tradeskill = nil
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
	-- Pin the far point outright: smart mode now routes by area, so it would rightly prefer a nearer
	-- cluster over one distant turn-in, and this case is about the line's clamping maths only.
	G:PinPosition(18, 0.5, 0.662, "Far target")
	LodestarArrow.scripts.OnUpdate(LodestarArrow, 0.1)
	ex, ey, clamped = G:MinimapLineState()
	check(ex and math.abs(ex - 64) < 1 and clamped, "far target clamps to the minimap edge: " .. tostring(ex))
	G:ClearPinnedPosition()
	-- Position persistence: the window and the arrow must come back exactly where they were left.
	-- Dragging leaves an anchor whose relativePoint differs from its point; restoring the offsets
	-- against the point alone is what made every frame wander on each login.
	LodestarGuideFrame:ClearAllPoints()
	LodestarGuideFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 640, 360)
	LodestarGuideFrame:GetScript("OnDragStop")(LodestarGuideFrame)
	local gp = G.db.profile.steps.pos
	check(gp.point == "CENTER" and gp.rel == "BOTTOMLEFT" and gp.x == 640 and gp.y == 360,
		"guide window saves its whole anchor: " .. tostring(gp.point) .. "/" .. tostring(gp.rel))
	LodestarGuideFrame:ClearAllPoints()
	G:UpdateStepFrame()   -- stands in for a relog: rebuild the frame from the profile
	local rp, _, rrel, rx, ry = LodestarGuideFrame:GetPoint(1)
	check(rp == "CENTER" and rrel == "BOTTOMLEFT" and rx == 640 and ry == 360,
		"guide window restores to the same spot, got " .. tostring(rp) .. "/" .. tostring(rrel) .. " " .. tostring(rx) .. "," .. tostring(ry))
	LodestarArrow:ClearAllPoints()
	LodestarArrow:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", -120, 240)
	LodestarArrow:GetScript("OnDragStop")(LodestarArrow)
	LodestarArrow:ClearAllPoints()
	G:UpdateArrowFrame()
	local ap, _, arel, ax, ay = LodestarArrow:GetPoint(1)
	check(ap == "TOPLEFT" and arel == "BOTTOMRIGHT" and ax == -120 and ay == 240,
		"arrow restores to the same spot, got " .. tostring(ap) .. "/" .. tostring(arel))
	G.db.profile.steps.pos = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -40, y = -200 }
	G.db.profile.arrow.pos = { point = "CENTER", rel = "CENTER", x = 0, y = 180 }
	G:UpdateStepFrame() G:UpdateArrowFrame()
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
	-- Installing the addon half way through a character: no saved progress, a log that is already
	-- part done, and a quest still being carried. It must resume at real work, not step 1, and not
	-- past the quest in hand.
	stub.flagged = { [363] = true, [364] = true, [376] = true }
	stub.questLog = { [3901] = { title = "Rattling the Rattlecages", complete = false, objectives = { { text = "0/8", finished = false } } } }
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = nil
	G.current = nil
	G:LoadGuide("Horde/Undead 1-5: Deathknell")
	check(G.stepIndex > 1, "a half-done log does not restart at step 1, at " .. tostring(G.stepIndex))
	local resumed, actionable, doneSet = G:ReconcileToLog(G.current)
	check(type(actionable) == "table" and #actionable > 0, "reconcile finds actionable steps, got " .. tostring(actionable and #actionable))
	check(type(doneSet) == "table" and next(doneSet) ~= nil, "reconcile marks finished steps as done")
	local held, resumedIsHeld = {}, false
	for _, c in ipairs(actionable) do if c.held then held[c.idx] = true end end
	check(next(held) ~= nil, "the quest still in the log shows up as held work")
	resumedIsHeld = held[resumed] == true
	-- Held work outranks unstarted work; among held steps the closest wins, so assert the rule
	-- rather than one particular index.
	check(resumedIsHeld, "resume lands on a step for the quest still in hand, got " .. tostring(resumed))
	check(doneSet[resumed] == nil, "resume never lands on a step that is already finished")
	stub.questLog = {}
	stub.flagged = {}
	stub.questLog = {}
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = nil
	G:LoadGuide("Horde/Undead 1-5: Deathknell", 1)
end)
-- The guide window: action rows, location bar, coming-up lines, smart list, width and resize.
try("guide window", function()
	local W = LodestarGuideFrame
	local function plain(s) if type(s) ~= "string" then return "" end return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	local function actionRows()
		local out = {}
		for _, r in ipairs(W.actionRows) do
			if r.shown then
				tinsert(out, { glyph = plain(r.glyph.text), chip = plain(r.chip.text), main = plain(r.main.text),
					right = plain(r.right.text), detail = plain(r.detail.text), header = r.isHeader, frame = r })
			end
		end
		return out
	end
	local function upcomingTexts()
		local out = {}
		for _, r in ipairs(W.upcomingRows) do
			if r.shown and r.main.text ~= "" then tinsert(out, plain(r.main.text)) end
		end
		return out
	end

	-- A guide with one of every row shape the window has to draw.
	check(G:RegisterGuide([[
#guide Test: window
#levels 1-60
step
  .goto Tirisfal Glades,30.8,66.2
  .turnin 363 >>Hand it to Shadow Priest Sarvis in the chapel
  .accept 364
step
  .goto Tirisfal Glades,32.3,63.6
  .complete 364,1 >>Graveyard north-east of the chapel
step
  .goto Tirisfal Glades,30.8,66.2
  .buy 2320,2
step
  .optional >>Only worth it in completionist mode
  .accept 3901
step
  .goto Tirisfal Glades,31.0,65.0
step
  .text >>Last step
]], "smoke") ~= nil, "window test guide registered")

	stub.level = 3
	stub.questLog = {}
	stub.flagged = {}
	stub.itemCounts = {}
	stub.questDifficulty = {}
	G.db.char.progress["Test: window"] = nil
	G.db.char.lastTrainedLevel = 99      -- nothing to train: keep the banner free for the other hints
	G.db.profile.steps.upcoming = 3
	G:SetStepFrameWidth(360)
	G:LoadGuide("Test: window", 1)
	check(G.stepIndex == 1, "window test guide starts at step 1, at " .. tostring(G.stepIndex))
	-- stand 566 yd south-east of the chapel, with Sarvis harvested there (zone + subzone)
	stub.playerMap.x, stub.playerMap.y = 0.35, 0.70
	G:HarvestDB().npcs[1569] = { name = "Shadow Priest Sarvis", map = 18, x = 30.8, y = 66.2,
		zone = "Tirisfal Glades", subzone = "Deathknell", kind = {} }
	G:InvalidateStepFrameCache()
	stub.flagged[363] = true             -- Rude Awakening handed in; The Mindless Ones not taken yet
	G:RefreshStepFrame()

	-- Title, location bar, headline
	check(W.title.text:find("Test: window", 1, true) and W.title.text:find("1/6", 1, true), "title: name and progress: " .. tostring(W.title.text))
	local loc = plain(W.location.text)
	check(loc:find("Deathknell · Tirisfal Glades", 1, true) and loc:find("566 yd", 1, true) and loc:find("NW", 1, true),
		"location bar: harvested subzone, zone, distance and direction: " .. loc)
	check(W.headline.text == "Turn in and pick up at Shadow Priest Sarvis", "hub headline names the NPC: " .. tostring(W.headline.text))

	-- Action rows: one per action, verb chip, quest name, level, state glyph
	local rows = actionRows()
	check(#rows == 2, "one action row per action, got " .. #rows)
	check(rows[1].chip == "Turn in" and rows[1].main:find("Rude Awakening", 1, true) and rows[1].main:find("(lvl 1)", 1, true),
		"turn-in row: verb chip, quest name and level: " .. rows[1].chip .. " / " .. rows[1].main)
	check(rows[2].chip == "Accept" and rows[2].main:find("The Mindless Ones", 1, true) and rows[2].main:find("(lvl 2)", 1, true),
		"accept row names what we are picking up: " .. rows[2].chip .. " / " .. rows[2].main)
	check(rows[1].glyph == "[+]" and rows[2].glyph == "[ ]", "completed action shows the done glyph: " .. rows[1].glyph .. " / " .. rows[2].glyph)
	check(rows[1].detail:find("Shadow Priest Sarvis", 1, true), "the guide author's note becomes the row's detail line: " .. rows[1].detail)
	check(W.actionRows[2].main.text:find("|cffffff00", 1, true), "a level 2 quest is yellow for a level 3 character: " .. W.actionRows[2].main.text)
	stub.questDifficulty[364] = Enum.RelativeContentDifficulty.Trivial
	G:RefreshStepFrame()
	check(W.actionRows[2].main.text:find("|cff808080", 1, true), "the client's own difficulty answer wins when it has one: " .. W.actionRows[2].main.text)
	stub.questDifficulty[364] = nil
	G:RefreshStepFrame()

	-- Coming up: location + verbs + quest names
	local up = upcomingTexts()
	check(#up == 3, "three coming-up rows, got " .. #up)
	check(up[1]:find("^2%. Tirisfal Glades — do The Mindless Ones$") ~= nil, "coming-up line 1 names the place and the quest: " .. up[1])
	check(up[2]:find("^3%. Deathknell — Buy ") ~= nil and up[3]:find("^5%. run to Deathknell$") ~= nil, "coming-up lines cover buy and goto-only steps: " .. up[2] .. " | " .. up[3])
	G.db.profile.steps.upcoming = 10
	G:RefreshStepFrame()
	check(#upcomingTexts() == 4, "the upcoming option now goes up to 10 (4 applicable steps left here; the optional one is skipped): " .. #upcomingTexts())
	G.db.profile.steps.upcoming = 3

	-- Clicking a row retargets the arrow at that action, the headline hands it back to the step
	G.db.profile.arrow.mode = "AUTO"
	G:RetargetArrow()
	check(G:GetArrowTarget() and G:GetArrowTarget().kind == "guide", "arrow starts on the step")
	rows[1].frame.scripts.OnEnter(rows[1].frame)
	rows[1].frame.scripts.OnLeave(rows[1].frame)
	rows[1].frame.scripts.OnClick(rows[1].frame)
	local t = G:GetArrowTarget()
	check(t and t.kind == "pinned" and t.mapID == 18 and math.abs(t.x - 0.308) < 0.002 and math.abs(t.y - 0.662) < 0.002,
		"clicking the turn-in row points the arrow at the quest's ender: " .. tostring(t and t.kind) .. " " .. tostring(t and t.x))
	check(stub.waypoint == nil, "the pin does not touch the player's own /way waypoint")
	-- a /way pin set by the player survives a row click and the release
	stub.slash("/way 30 60 mine")
	rows[1].frame.scripts.OnClick(rows[1].frame)
	W.headlineButton.scripts.OnClick(W.headlineButton)
	check(stub.waypoint ~= nil, "the player's own waypoint is still there afterwards")
	stub.slash("/way clear")
	check(G:GetArrowTarget() and G:GetArrowTarget().kind == "guide", "clicking the headline hands the arrow back to the step")

	-- Objective progress on a .complete row
	stub.questLog[364] = { title = "The Mindless Ones", complete = false,
		objectives = { { text = "Mindless Zombie slain: 3/8", finished = false, numFulfilled = 3, numRequired = 8 } } }
	G:SetStep(2, true)
	G:RefreshStepFrame()
	rows = actionRows()
	check(#rows == 1 and rows[1].chip == "Do" and rows[1].main:find("The Mindless Ones", 1, true), "kill step draws one Do row: " .. tostring(rows[1] and rows[1].chip))
	check(rows[1].detail == "Mindless Zombie slain: 3/8", "live objective progress on the row: " .. rows[1].detail)
	check(W.headline.text == "Kill Mindless Zombies", "kill headline names the mob: " .. tostring(W.headline.text))

	-- Buy row: item name and have/need
	stub.itemCounts[2320] = 1
	G:SetStep(3, true)
	G:RefreshStepFrame()
	rows = actionRows()
	check(rows[1].chip == "Buy" and rows[1].main:find("Item2320", 1, true) and rows[1].right == "1/2", "buy row: item name and have/need: " .. rows[1].main .. " " .. rows[1].right)
	stub.itemCounts[2320] = nil

	-- Optional tag and its reason
	G:SetStep(4, true)
	G:RefreshStepFrame()
	check(W.headline.text:find("(optional)", 1, true), "optional tag on the headline: " .. tostring(W.headline.text))
	check(plain(W.banner.text):find("Only worth it in completionist mode", 1, true), "the optional reason is shown: " .. plain(W.banner.text))

	-- Goto-only step
	G:SetStep(5, true)
	G:RefreshStepFrame()
	rows = actionRows()
	check(W.headline.text == "Run to Deathknell", "goto-only headline: " .. tostring(W.headline.text))
	check(#rows == 1 and rows[1].chip == "Reach", "goto-only step still gets a row: " .. tostring(rows[1] and rows[1].chip))

	-- Sync hint
	G:SetStep(1, true)
	stub.questLog[364] = nil
	stub.flagged[364] = true
	stub.advance(6)
	G:RefreshStepFrame()
	check(plain(W.banner.text):find("You look further along", 1, true), "sync hint still renders: " .. plain(W.banner.text))

	-- Trainer banner
	stub.playerMap.x, stub.playerMap.y = 0.308, 0.662
	stub.level = 4
	G.db.char.lastTrainedLevel = nil
	G:TrainerSuggestion(true)
	G:InvalidateStepFrameCache()
	G:RefreshStepFrame()
	check(plain(W.banner.text):find("Dannal Stern", 1, true) and plain(W.banner.text):find("New spells", 1, true), "trainer banner still renders: " .. plain(W.banner.text))
	stub.level = 3
	G.db.char.lastTrainedLevel = 99

	-- Finished state
	G:SetStep(6, true)
	G:FinishGuide()
	G:RefreshStepFrame()
	check(plain(W.banner.text):find("Guide finished", 1, true), "finished state: " .. plain(W.banner.text))
	check(W.title.text:find("done", 1, true), "title marks the guide done: " .. tostring(W.title.text))
	G.finished = nil

	-- Width: option, clamping, menu presets and the resize grip
	check(G:SetStepFrameWidth(520) == 520 and W.uiWidth == 520, "width option widens the window: " .. tostring(W.uiWidth))
	local wideScale = W.uiScale
	check(G:SetStepFrameWidth(260) == 260 and W.uiWidth == 260 and W.uiScale < wideScale, "260 re-lays out with smaller rows: " .. tostring(W.uiScale) .. " vs " .. tostring(wideScale))
	check(#actionRows() >= 1, "rows still render at the minimum width")
	check(G:SetStepFrameWidth(700) == 520 and G:SetStepFrameWidth(100) == 260, "width is clamped to 260-520")
	G:SetStepFrameWidth(400)
	W.grip.scripts.OnMouseDown(W.grip)
	W.grip.scripts.OnMouseUp(W.grip)
	check(G.db.profile.steps.width == 260 and W.uiWidth == 260, "the grip saves the dragged width (the stub frame measures 200 px, clamped to the minimum): " .. tostring(G.db.profile.steps.width))
	W.grip.scripts.OnEnter(W.grip)
	W.grip.scripts.OnLeave(W.grip)
	G:SetStepFrameWidth(360)

	-- Smart mode: grouped list, levels on pick-ups, distances, clicking pins
	stub.questLog = {}
	stub.flagged = { [363] = true }
	stub.slash("/lode guide smart")
	G:PinSmartItem(nil)
	G:CollectSmartItems(true)
	G:RefreshStepFrame()
	check(W.title.text:find("smart mode", 1, true), "window shows smart mode: " .. tostring(W.title.text))
	local headers, pickup, distance = {}, nil, nil
	for _, r in ipairs(actionRows()) do
		if r.header then headers[r.main] = true
		else
			if r.main:find("%(lvl %d+%)") and not pickup then pickup = r.main end
			if r.right:find("yd", 1, true) and not distance then distance = r.right end
		end
	end
	check(headers["Pick up"], "smart list groups the rest under kind headers: " .. tostring(next(headers)))
	check(pickup ~= nil, "pick-up rows say what level the quest is: " .. tostring(pickup))
	check(distance ~= nil, "smart rows carry a distance: " .. tostring(distance))
	local firstItem
	for _, r in ipairs(W.actionRows) do if r.shown and not r.isHeader and not firstItem then firstItem = r end end
	firstItem.scripts.OnClick(firstItem)
	check(G:GetPinnedSmartItem() ~= nil, "clicking a smart row pins it")

	-- Back to where the rest of the run expects things
	G:PinSmartItem(nil)
	G.db.profile.arrow.mode = "AUTO"
	if stub.waypoint then C_Map.ClearUserWaypoint() end
	stub.playerMap.x, stub.playerMap.y = 0.308, 0.662
	stub.level = 3
	stub.questLog = {}
	stub.flagged = {}
	stub.questDifficulty = {}
	G.db.char.lastTrainedLevel = nil
	G.db.char.progress["Horde/Undead 1-5: Deathknell"] = nil
	G:LoadGuide("Horde/Undead 1-5: Deathknell", 1)
	G:InvalidateStepFrameCache()
end)
try("forever overlay", function()
	check(G.ForeverData and G.VanillaData.quests[99142] and G.VanillaData.quests[99142].t == "Tomb Weed", "Forever quest merged into the data")
	check(G.VanillaData.quests[99142].forever == true and G.VanillaData.quests[356].xp ~= nil, "overlay adds xp to a Vanilla quest and flags Forever ones")
	check(G.VanillaData.npcs[246152] and G.VanillaData.npcs[246152].n == "Shari Stilwell", "Forever-only NPC merged")
	-- All The Things overlay: fills the world in under the harvest. Precedence matters -- ATT only
	-- fills gaps, and anything a player recorded first-hand still wins.
	check(G.ATTData and next(G.ATTData.quests) ~= nil, "ATT overlay loaded")
	check(G.VanillaData.attMerged == true, "ATT merged into the data")
	local att908 = G.VanillaData.quests[908]
	check(att908 and att908.start and att908.att == true, "a quest only ATT places gets its giver from ATT")
	check(att908.acceptAt and att908.acceptAt.m, "... and a position with a uiMapID")
	-- 3901 is harvested first-hand (Forever overlay); the harvest flag must survive the ATT pass
	check(G.VanillaData.quests[99142] and G.VanillaData.quests[99142].forever == true,
		"a harvested quest keeps its first-hand marking after the ATT merge")
	local prereq = 0
	for _, q in pairs(G.ATTData.quests) do if q.pre then prereq = prereq + 1 end end
	check(prereq > 500, "ATT contributes the quest prerequisite graph (as `pre`, the field canTake reads), got " .. prereq)
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
	-- An overlay quest the data knows (title and level) but attributes to no giver: DataAvailableFrom
	-- cannot offer it, so the tooltip has to fall back to the harvest, with the level from the data.
	H.npcs[1569].gives = { [77779] = true }
	G.VanillaData.quests[77779] = { t = "A Second Home", lvl = 11 }
	H.quests[77779] = { t = "A Second Home" }
	stub.fire("QUEST_LOG_UPDATE")
	text = tip(UNIT, sarvis)
	check(text:find("Starts: A Second Home (lvl 11) (new)", 1, true) ~= nil, "quest the data knows but starts nowhere is still offered, level from the data: " .. text)
	G.VanillaData.quests[77779] = nil
	H.quests[77779] = nil
	H.npcs[1569].gives = { [77778] = true, [3901] = true }
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
-- The module draws its own panel; it must never write into Blizzard's stats tables (see Panel.lua).
try("character", function()
	local C = Lodestar:GetModule("Character")
	check(C and C:IsEnabled() and statuses["Lodestar_Character"] == true, "Character module registered and enabled")
	local S = C.Stats
	check(blizzardStatTables() == pristineStatTables, "PAPERDOLL_STATCATEGORIES / PAPERDOLL_STATINFO untouched after login")
	check(rawget(_G, "LodestarCharacterStatsFrame") == nil and C:GetPanel() == nil, "no panel until the character sheet is opened")
	-- fixed character state for the numbers below
	stub.level, stub.xp, stub.xpMax, stub.rested = 12, 4000, 10000, 500
	stub.manaMax, stub.shield, stub.holyResist, stub.swimSpeed, stub.legacyRenown, stub.pvpRank, stub.meleeHaste = 1000, true, 15, 3.5, 12, 3, 0
	local instant = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function(id) -- main hand sword, off-hand dagger, ranged bow
		local sub = ({ [2001] = Enum.ItemWeaponSubclass.Sword1H, [2002] = Enum.ItemWeaponSubclass.Dagger, [2003] = Enum.ItemWeaponSubclass.Bows })[id]
		return id, "Weapon", "Sub", "INVTYPE_WEAPON", 134, Enum.ItemClass.Weapon, sub
	end
	-- every row's update runs against a panel row (Label / Value / tooltip) and produces text
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
	check(texts.LODESTAR_TALENTS == "5" and texts.LODESTAR_LEGACY == "12 (5 free)" and texts.LODESTAR_PVP_RANK == "PVP_RANK_7_0", "talents, legacy and pvp rank rows: " .. tostring(texts.LODESTAR_TALENTS))

	-- The panel: created on demand, shown and hidden with the character sheet.
	CharacterFrame:Show()
	local panel = rawget(_G, "LodestarCharacterStatsFrame")
	check(panel ~= nil and panel == C:GetPanel() and panel.shown, "panel created on demand and shown with the character frame")
	local function panelRows()
		local out, n = {}, 0
		for _, r in ipairs(panel.rows) do
			if r.shown then out[r.Label.text] = r.Value.text n = n + 1 end
		end
		return out, n
	end
	local function panelHeaders()
		local out = {}
		for _, h in ipairs(panel.headers) do if h.shown then out[#out + 1] = h.text end end
		return table.concat(out, ",")
	end
	local st = C:GetPanelState()
	local rows, shownRows = panelRows()
	check(st.rows >= 20 and st.rows == shownRows and st.rows == panel.shownRows, "panel filled with its rows, got " .. tostring(st.rows) .. "/" .. tostring(shownRows))
	check(panelHeaders() == "Melee,Ranged,Spell,Regeneration,Defense detail,Weapon skills,Gear,Progress", "eight category headers in order: " .. panelHeaders())
	check(st.columns == 2, "the full list is laid out in two columns, got " .. tostring(st.columns))
	check(rows["Melee hit:"] == "5.0%" and rows["Ranged hit:"] == "3.0%" and rows["Spell hit:"] == "4.0%", "hit rows: " .. tostring(rows["Melee hit:"]) .. " " .. tostring(rows["Ranged hit:"]) .. " " .. tostring(rows["Spell hit:"]))
	check(rows["Attack speed:"] == "2.60 / 1.80" and rows["Melee DPS:"] == "19.2 / 13.9", "attack speed and dps rows: " .. tostring(rows["Attack speed:"]))
	check(rows["Swords:"] == "87/100 |cff20ff20+5|r" and rows["Daggers:"] ~= nil and rows["Bows:"] ~= nil, "weapon skill rows, one per equipped weapon: " .. tostring(rows["Swords:"]))
	check(rows["Durability:"] == "62%" and rows["Item level (equipped):"] == "23", "gear rows: " .. tostring(rows["Durability:"]))
	check(rows["Experience:"] == "40.0%" and rows["Rested XP:"] == "500 (5%)", "progress rows: " .. tostring(rows["Experience:"]))
	-- Unspent talents come from the trait-tree currency Forever's own talent frame reads; the
	-- undocumented Classic global is only a fallback, and it disagrees (3) with the trait path (5).
	local Stats = Lodestar:GetModule("Character").Stats
	check(Stats.UnspentTalents() == 5, "unspent talents read from the trait currency, got " .. tostring(Stats.UnspentTalents()))
	stub.noTraitConfig = true
	check(Stats.UnspentTalents() == 3, "falls back to the legacy global when there is no trait config")
	stub.noTraitConfig = nil
	-- tooltips come off the row itself, the same three slots Stats.lua fills
	local meleeHit
	for _, r in ipairs(panel.rows) do if r.shown and r.Label.text == "Melee hit:" then meleeHit = r end end
	check(meleeHit and type(meleeHit.tooltip) == "string" and meleeHit.tooltip:find("Melee hit", 1, true) ~= nil, "row tooltip header: " .. tostring(meleeHit and meleeHit.tooltip))
	check(meleeHit.tooltip2:find("Level 12: 0%.0%%") and meleeHit.tooltip2:find("Level 15 %(boss%): 2%.7%%"), "miss table vs +0..+3 in the row tooltip: " .. tostring(meleeHit.tooltip2))
	meleeHit:GetScript("OnEnter")(meleeHit)
	check(GameTooltip:GetOwner() == meleeHit and GameTooltip.text == meleeHit.tooltip, "hovering a row opens GameTooltip with its lines")
	meleeHit:GetScript("OnLeave")(meleeHit)
	-- hide-zero: melee haste is 0 on this character
	check(rows["Melee haste:"] == nil, "hideZero drops the zero haste row")
	C.db.profile.hideZero = false
	C:RefreshPanel()
	rows = panelRows()
	check(rows["Melee haste:"] == "0.0%", "hideZero off shows the zero haste row")
	check(rows["Fire damage:"] == nil and rows["Holy resistance:"] ~= nil, "rows with a fixed hideAt stay hidden regardless")
	C.db.profile.hideZero = true
	C:RefreshPanel()
	check(panelRows()["Melee haste:"] == nil, "hideZero back on hides it again")
	-- category toggles
	C.db.profile.categories.gear = false
	C:RefreshPanel()
	rows = panelRows()
	check(rows["Durability:"] == nil and rows["Item level (equipped):"] == nil, "gear rows gone when the category is off")
	check(panelHeaders():find("Gear") == nil, "gear header gone too: " .. panelHeaders())
	C.db.profile.categories.gear = true
	C:RefreshPanel()
	check(panelRows()["Durability:"] == "62%", "gear rows back when the category is on")
	for key in pairs(C.db.profile.categories) do C.db.profile.categories[key] = (key == "melee") end
	C:RefreshPanel()
	check(st.columns == 1 and st.rows == 4 and panelHeaders() == "Melee", "one small category: four rows in a single column, got " .. tostring(st.rows) .. "/" .. tostring(st.columns))
	for key in pairs(C.db.profile.categories) do C.db.profile.categories[key] = false end
	C:RefreshPanel()
	check(st.rows == 0 and panel.empty.shown, "nothing enabled: the empty note")
	for key in pairs(C.db.profile.categories) do C.db.profile.categories[key] = true end
	C:RefreshPanel()
	check(st.rows >= 20 and not panel.empty.shown, "everything back on")
	-- refresh throttle: our own events, coalesced, only while the panel is up
	local before = st.refreshes
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("UPDATE_INVENTORY_DURABILITY")
	stub.fire("UNIT_DEFENSE", "player")
	check(st.refreshes == before, "refresh is deferred, not immediate")
	stub.advance(1)
	check(st.refreshes == before + 1, "three events coalesced into one refresh, got +" .. (st.refreshes - before))
	stub.fire("UNIT_DEFENSE", "target")
	stub.advance(1)
	check(st.refreshes == before + 1, "other units' UNIT_ events ignored")
	stub.fire("COMBAT_RATING_UPDATE")
	stub.fire("UNIT_STATS", "player")
	stub.fire("SKILL_LINES_CHANGED")
	stub.fire("PLAYER_EQUIPMENT_CHANGED")
	stub.advance(1)
	check(st.refreshes == before + 2, "stat / rating / skill / equipment events drive the panel too")
	C:RequestStatsUpdate(true)
	check(st.refreshes == before + 3, "an explicit refresh runs straight away")
	-- closing the sheet closes the panel and stops the events
	CharacterFrame:Hide()
	check(not panel.shown, "panel hides with the character frame")
	local afterHide = st.refreshes
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("UNIT_STATS", "player")
	stub.advance(1)
	check(st.refreshes == afterHide, "no refresh while the character frame is closed")
	check(blizzardStatTables() == pristineStatTables, "Blizzard's stats tables still untouched after opening and closing the panel")
	-- /lode character toggles it
	stub.slash("/lode character")
	check(C.db.profile.show == false, "/lode character turns the panel off")
	CharacterFrame:Show()
	check(not panel.shown, "panel stays closed while it is turned off")
	stub.slash("/lode character")
	check(C.db.profile.show == true and panel.shown, "/lode character turns it back on")
	-- right-click menu, drag and position
	stub.menuShown = false
	panel:GetScript("OnMouseUp")(panel, "RightButton")
	check(stub.menuShown, "right-click builds the context menu")
	C:ShowPanelMenu()
	panel:GetScript("OnDragStart")(panel)
	panel:GetScript("OnDragStop")(panel)
	check(type(C.db.profile.pos) == "table" and C.db.profile.pos.point and C.db.profile.pos.rel,
		"dragging saves the position AND its relative point in the profile")
	-- The bug this guards: a dragged frame's relativePoint is usually not its point, and restoring
	-- the offsets against the wrong corner is what moved every window on every login.
	panel:ClearAllPoints()
	panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 412, 388)
	panel:GetScript("OnDragStop")(panel)
	check(C.db.profile.pos.point == "CENTER" and C.db.profile.pos.rel == "BOTTOMLEFT"
		and C.db.profile.pos.x == 412 and C.db.profile.pos.y == 388, "the whole anchor is round-tripped")
	C:RefreshPanel()
	C.db.profile.pos = nil
	C:ResetPanelPosition()
	check(C.db.profile.pos == nil, "docking clears the saved position")
	-- module disable / enable
	Lodestar:SetModuleEnabled("Character", false)
	check(statuses["Lodestar_Character"] == false and not panel.shown, "disable hides the panel")
	check(blizzardStatTables() == pristineStatTables, "disable leaves Blizzard's tables alone")
	Lodestar:SetModuleEnabled("Character", true)
	check(statuses["Lodestar_Character"] == true and panel.shown, "re-enable brings it back with the sheet open")
	CharacterFrame:Hide()
	-- off-hand with the same skill as the main hand collapses into one row
	C_Item.GetItemInfoInstant = function(id) return id, "Weapon", "Sub", "INVTYPE_WEAPON", 134, Enum.ItemClass.Weapon, Enum.ItemWeaponSubclass.Sword1H end
	check(S.rowByStat.LODESTAR_WEAPON_SKILL_OH.update(frame, "player") == nil, "off-hand row hidden when it shares the main-hand skill")
	-- a row that throws is dropped, the panel survives
	local broken = { stat = "LODESTAR_BROKEN", update = function() error("boom") end }
	check(C:RunRow(broken, frame) == nil, "a row that errors comes back as nil instead of blowing up the panel")
	-- options page
	local opts = Lodestar:BuildOptions()
	for _, opt in pairs(opts.args.Character.args) do
		if opt.get then
			local v = opt.get({})
			if opt.set and opt.type == "toggle" then opt.set({}, v) end
		elseif opt.type == "execute" then opt.func()
		end
	end
	check(blizzardStatTables() == pristineStatTables, "Blizzard's stats tables untouched after every option was exercised")
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

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

local addons = { "Lodestar", "Lodestar_Leveling", "Lodestar_Economy", "Lodestar_UI", "Lodestar_Guild" }
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
	local ok, err = pcall(fn)
	if not ok then tinsert(failures, what .. ": " .. tostring(err)) end
end

local Lodestar = _G.Lodestar
check(Lodestar and Lodestar.db, "core initialised")
check(#Lodestar.moduleList == 4, "four modules registered, got " .. tostring(#Lodestar.moduleList))
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

-- Leveling: XP events and quest automation
try("xp update", function()
	stub.xp = 4500 stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("QUEST_TURNED_IN", 7, 900, 100)
	stub.xp = 5400 stub.fire("PLAYER_XP_UPDATE", "player")
	local rolling, average, ttl = Lodestar:GetModule("Leveling"):GetXPRates()
	check(rolling > 0 and average > 0 and ttl, "xp rates computed")
end)
try("level up", function()
	stub.level, stub.xp, stub.xpMax = 13, 100, 12000
	stub.fire("PLAYER_LEVEL_UP", 13)
	stub.fire("PLAYER_XP_UPDATE", "player")
end)
try("gossip", function() stub.fire("GOSSIP_SHOW") check(stub.gossipActive == 5, "gossip picked completed quest first") end)
try("greeting", function() stub.fire("QUEST_GREETING") check(stub.selectedActive, "greeting selected active quest") end)
try("detail", function() stub.fire("QUEST_DETAIL") check((stub.accepted or 0) >= 1, "quest accepted") end)
try("progress", function() stub.fire("QUEST_PROGRESS") check(stub.completed, "quest completed") end)
try("complete 0", function() stub.choices = 0 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == 0, "reward 0 taken") end)
try("complete 1", function() stub.choices = 1 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == 1, "single reward taken") end)
try("complete 2", function() stub.rewardTaken = nil stub.choices = 2 stub.fire("QUEST_COMPLETE") check(stub.rewardTaken == nil, "multi-choice left alone") end)
try("paused", function() stub.shift = true stub.accepted = 0 stub.fire("QUEST_DETAIL") check(stub.accepted == 0, "shift pauses automation") stub.shift = false end)
try("escort", function() stub.fire("QUEST_ACCEPT_CONFIRM", "Bob", "Escort") check(stub.confirmed, "escort confirmed") end)

-- Economy: merchant
try("merchant", function()
	stub.slash("/lode keep 1234") -- undo the protection toggled above
	MerchantFrame.shown = true
	stub.fire("MERCHANT_SHOW")
	stub.advance(2)
	check(stub.repaired == "self", "auto-repaired")
	check(stub.sold == 1, "sold exactly the one junk stack, got " .. tostring(stub.sold))
	stub.fire("MERCHANT_CLOSED")
	MerchantFrame.shown = false
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

-- UI: chat filter, loot, coordinates
try("url filter", function()
	local fn = stub.filters.CHAT_MSG_SAY[1]
	local _, msg = fn(nil, "CHAT_MSG_SAY", "see https://example.com/x?y=1 now", "Bob")
	check(msg and msg:find("|Hlodeurl:https://example.com/x?y=1|h", 1, true), "url linkified: " .. tostring(msg))
	SetItemRef("lodeurl:https://example.com")
	check(LodestarCopyFrame and LodestarCopyFrame.shown, "copy box opened from link")
end)
try("loot", function() stub.fire("LOOT_READY", true) check(stub.looted == 2, "fast loot took both slots") end)
try("coords", function() WorldMapFrame.shown = true stub.advance(0.5) check(LodestarCoordsFrame ~= nil, "minimap coords frame exists") end)
try("timestamps", function() check(stub.cvars.showTimestamps == "%H:%M ", "timestamp cvar applied: " .. tostring(stub.cvars.showTimestamps)) end)

-- Guild: incoming presence and board
try("presence in", function()
	local ser = Lodestar:Serialize({ t = "P", v = "0.1.0", l = 20, z = "Westfall", s = "Moonbrook", x = 55, m = 52, c = "WARRIOR", n = "Deadmines" })
	Lodestar:OnCommReceived("Lodestar", ser, "GUILD", "Guildie-ClassicBetaPvP2")
	local G = Lodestar:GetModule("Guild")
	check(G.presence["Guildie"] and G.presence["Guildie"].l == 20, "presence stored under short name")
	local rows = G:CollectRows()
	check(#rows == 1 and rows[1].lodestar and rows[1].note == "Deadmines", "board row merged roster + presence")
	local ser2 = Lodestar:Serialize({ t = "V", v = "9.9.9" })
	Lodestar:OnCommReceived("Lodestar", ser2, "GUILD", "Someone")
	check(Lodestar.versionNoticeShown, "newer version notice shown")
	local q = Lodestar:Serialize({ t = "Q", v = "0.1.0" })
	Lodestar:OnCommReceived("Lodestar", q, "GUILD", "Someone")
	stub.advance(5)
end)

-- Module toggling and profile change
try("toggle module", function()
	Lodestar:SetModuleEnabled("UI", false)
	check(not Lodestar:GetModule("UI"):IsEnabled(), "UI disabled live")
	Lodestar:SetModuleEnabled("UI", true)
	check(Lodestar:GetModule("UI"):IsEnabled(), "UI re-enabled live")
	Lodestar:OnProfileChanged()
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
try("minimap menu", function() Lodestar:ShowModuleMenu() check(stub.menuShown, "context menu built") end)
try("logout", function() stub.fire("PLAYER_LOGOUT") end)

-- Report
print(("smoke: %d checks, %d failures"):format(checks, #failures))
for _, f in ipairs(failures) do print("  FAIL " .. f) end
local unknown = {}
for k, n in pairs(stub.unknownGlobals) do tinsert(unknown, k .. "(" .. n .. ")") end
table.sort(unknown)
if #unknown > 0 then print("unknown globals touched: " .. table.concat(unknown, " ")) end
if #failures > 0 then os.exit(1) end

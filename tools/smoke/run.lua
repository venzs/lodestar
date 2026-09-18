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
	local picked = G:PickGuide()
	check(picked and picked.name == "Horde/Undead 1-5: Deathknell", "auto-pick chose the undead guide: " .. tostring(picked and picked.name))
	check(G.current and G.current.name == picked.name, "guide auto-loaded at login")
	check(G.stepIndex == 1, "starts at step 1")
end)
try("engine advance", function()
	-- accept 3901 -> step 1 done
	stub.questLog[3901] = { title = "Rude Awakening", complete = false, objectives = {} }
	stub.fire("QUEST_ACCEPTED", 3901)
	stub.advance(1)
	check(G.stepIndex == 2, "advanced to step 2 after accept, at " .. tostring(G.stepIndex))
	-- turn in 3901 and accept 3903 -> step 2 done
	stub.questLog[3901] = nil stub.flagged[3901] = true
	stub.fire("QUEST_TURNED_IN", 3901, 250, 0)
	stub.questLog[3903] = { title = "Rattling the Rattlecages", complete = false, objectives = { { text = "Rattlecage Skeleton slain: 0/8", finished = false } } }
	stub.fire("QUEST_ACCEPTED", 3903)
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
	stub.questLog[3903].wp = { map = 18, x = 0.33, y = 0.66 }
	G:RetargetArrow()
	t = G:GetArrowTarget()
	check(t and t.kind == "quest" and t.questID == 3903, "arrow targets nearest quest waypoint")
	check(stub.superTrackedQuest == 3903, "super-tracked the quest")
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
	stub.fire("PLAYER_TARGET_CHANGED")
	stub.diedGUID = "Creature-0-1-2-3-6-000ABC"
	stub.fire("COMBAT_LOG_EVENT_UNFILTERED")
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
	check(text:find("mobs: Kobold Vermin x1", 1, true), "export text has mob levels: " .. tostring(text:match("mobs:[^\n]*")))
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

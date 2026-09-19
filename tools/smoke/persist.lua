-- Cross-session persistence test: does what the player changed survive a logout?
--
-- tools/smoke/run.lua exercises everything inside ONE session, which is why it never caught the
-- bug that cost the most real time: frames coming back at their default position after every
-- relog, and a harvest that read back empty. Both live in the gap between two sessions, and that
-- gap has three moving parts the in-process test skips entirely:
--
--   1. AceDB's PLAYER_LOGOUT pass strips every value that still equals its default.
--   2. The client serialises the saved-variable globals to Lua source and reloads them next login.
--   3. It loads that source AFTER running the addon's files and BEFORE firing its ADDON_LOADED --
--      so anything an addon captured at file scope is a reference to a table the client is about
--      to replace.
--
-- So this runs two real sessions in two separate Lua states. Session one logs in, moves things,
-- harvests, changes settings and logs out; its saved variables are written to disk in the client's
-- own format. Session two loads that file at exactly the point the client would and checks that
-- everything came back. A value that does not survive fails here instead of in the game.
--
-- Usage (from the repo root):  lua5.1 tools/smoke/persist.lua
local ROOT = arg and arg[0] and arg[0]:match("^(.*)tools[/\\]smoke[/\\]persist%.lua$") or "./"
if ROOT == "" then ROOT = "./" end

local MODE = arg and arg[1]
local SVDIR = (arg and arg[2]) or (os.getenv("TMPDIR") or "/tmp") .. "/lodestar-persist"

-- Saved variables by owning addon, exactly as the TOCs declare them.
local SAVED = {
	Lodestar = { "LodestarCore", "LodestarProbes" },
	Lodestar_Guide = { "LodestarScans", "LodestarHarvest" },
}

--- The names those slots used before Core/Saved.lua moved them off the "DB" suffix. A player
--- upgrading has a file full of these and nothing under the new names.
local LEGACY = {
	LodestarCore = "LodestarDB",
	LodestarProbes = "LodestarProbeDB",
	LodestarScans = "LodestarScanDB",
	LodestarHarvest = "LodestarShareDB",
}

-- ---------------------------------------------------------------------------------------------
-- Driver: no mode means "run both halves", each in its own process so neither can see the other's
-- globals. Two states is the whole point -- a single state would keep every table alive by
-- reference and prove nothing about what actually round-trips through the file.
-- ---------------------------------------------------------------------------------------------
if not MODE then
	os.execute("rm -rf " .. SVDIR .. " && mkdir -p " .. SVDIR)
	local lua = "lua5.1"
	local function run(mode)
		local cmd = ("%s %stools/smoke/persist.lua %s %s"):format(lua, ROOT, mode, SVDIR)
		local ok, how, code = os.execute(cmd)
		-- Lua 5.1 returns the raw exit status; 5.2+ returns ok, "exit", code.
		if ok == true or ok == 0 then return 0 end
		return (type(code) == "number" and code) or 1
	end
	if run("write") ~= 0 then print("persist: session one failed") os.exit(1) end
	if run("read") ~= 0 then print("persist: session two failed") os.exit(1) end
	-- And the upgrade path: the same data sitting under the names Lodestar used before
	-- Core/Saved.lua renamed them has to be adopted, not silently started over.
	if run("readlegacy") ~= 0 then print("persist: legacy adoption failed") os.exit(1) end
	os.exit(0)
end

package.path = ROOT .. "tools/smoke/?.lua;" .. package.path
local stub = require("wow_stub")

-- ---------------------------------------------------------------------------------------------
-- Loader -- the client's order, with the saved-variable file loaded in the client's window.
-- ---------------------------------------------------------------------------------------------
local function loadLua(path)
	local chunk, err = loadfile(ROOT .. path)
	if not chunk then error("load " .. path .. ": " .. tostring(err)) end
	local addonName = path:match("^([^/\\]+)")
	local ok, perr = pcall(chunk, addonName, {})
	if not ok then error("run " .. path .. ": " .. tostring(perr)) end
end

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

--- Run the addon's saved-variable file the way the client does: plain global assignments in the
--- global environment, after the addon's own files and before its ADDON_LOADED.
local function loadSavedVariables(addon)
	if MODE ~= "read" and MODE ~= "readlegacy" then return end
	local dir = MODE == "readlegacy" and (SVDIR .. "/legacy") or SVDIR
	local f = io.open(dir .. "/" .. addon .. ".lua", "r")
	if not f then return end
	local src = f:read("*a")
	f:close()
	local chunk, err = loadstring(src, "@" .. addon .. ".lua")
	if not chunk then error("saved variables for " .. addon .. " do not parse: " .. tostring(err)) end
	chunk()
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
	loadSavedVariables(addon)
	stub.fire("ADDON_LOADED", addon)
end

local addons = { "Lodestar", "Lodestar_Leveling", "Lodestar_Economy", "Lodestar_UI", "Lodestar_Guild",
	"Lodestar_Guide", "Lodestar_Guides_Horde", "Lodestar_Guides_Alliance", "Lodestar_Character" }
for _, a in ipairs(addons) do loadToc(a) end
if not _G.Lodestar:GetModule("Guide").TrainerData then loadLua("Lodestar_Guide/Data/Trainers.lua") end

stub.loggedIn = true
stub.fire("PLAYER_LOGIN")
stub.fire("PLAYER_ENTERING_WORLD", true, false)
stub.advance(15)

local Lodestar = _G.Lodestar
local G = Lodestar:GetModule("Guide")
G:StopHarvestSync()

-- ---------------------------------------------------------------------------------------------
-- Serialiser -- the client's own format, so session two parses exactly what the game would write.
-- ---------------------------------------------------------------------------------------------
local function keyRepr(k)
	if type(k) == "number" then return "[" .. tostring(k) .. "]" end
	return "[" .. string.format("%q", tostring(k)) .. "]"
end

local function serialize(out, value, indent)
	local t = type(value)
	if t == "table" then
		out[#out + 1] = "{\n"
		local keys = {}
		for k in pairs(value) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then
				if type(a) == "number" then return a < b end
				return tostring(a) < tostring(b)
			end
			return type(a) == "number"
		end)
		for _, k in ipairs(keys) do
			local v = value[k]
			if type(v) ~= "function" and type(v) ~= "userdata" then
				out[#out + 1] = indent .. keyRepr(k) .. " = "
				serialize(out, v, indent .. "\t")
				out[#out + 1] = ",\n"
			end
		end
		out[#out + 1] = indent:sub(2) .. "}"
	elseif t == "string" then
		out[#out + 1] = string.format("%q", value)
	elseif t == "number" then
		-- The client writes numbers back at full precision; %.17g round-trips a double exactly.
		out[#out + 1] = (value == math.floor(value) and math.abs(value) < 2 ^ 53)
			and string.format("%d", value) or string.format("%.17g", value)
	else
		out[#out + 1] = tostring(value)
	end
end

local function writeSavedVariables()
	os.execute("mkdir -p " .. SVDIR .. " " .. SVDIR .. "/legacy")
	for addon, names in pairs(SAVED) do
		local out = { "\n" }
		for _, name in ipairs(names) do
			local v = _G[name]
			if v ~= nil then
				out[#out + 1] = name .. " = "
				serialize(out, v, "\t")
				out[#out + 1] = "\n"
			end
		end
		local body = table.concat(out)
		local f = assert(io.open(SVDIR .. "/" .. addon .. ".lua", "w"))
		f:write(body)
		f:close()
		-- The same bytes under the old names, for the adoption pass.
		local legacy = body
		for name, was in pairs(LEGACY) do
			legacy = legacy:gsub("\n" .. name .. " = ", "\n" .. was .. " = ")
		end
		local g = assert(io.open(SVDIR .. "/legacy/" .. addon .. ".lua", "w"))
		g:write(legacy)
		g:close()
	end
end

-- ---------------------------------------------------------------------------------------------
-- What the player did, and what must still be true next login.
-- ---------------------------------------------------------------------------------------------
local WANT = {
	stepPos   = { point = "CENTER",  rel = "BOTTOMLEFT",  x = 640,  y = 360 },
	arrowPos  = { point = "TOPLEFT", rel = "BOTTOMRIGHT", x = -120, y = 240 },
	upcoming  = 7,
	scale     = 1.4,
	arrowMode = "QUEST",
	questID   = 90210,
}

local checks, failures = 0, {}
local function check(cond, what)
	checks = checks + 1
	if not cond then failures[#failures + 1] = what end
end

local function dragTo(frame, pos)
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, _G.UIParent, pos.rel, pos.x, pos.y)
	local stop = frame:GetScript("OnDragStop")
	if stop then stop(frame) end
end

local function samePos(got, want, label)
	check(type(got) == "table", label .. ": nothing was saved")
	if type(got) ~= "table" then return end
	check(got.point == want.point and got.rel == want.rel and got.x == want.x and got.y == want.y,
		("%s: got %s/%s %s,%s want %s/%s %s,%s"):format(label, tostring(got.point), tostring(got.rel),
			tostring(got.x), tostring(got.y), want.point, want.rel, want.x, want.y))
end

if MODE == "write" then
	-- Move both frames the way a player does: drag, release. Dragging leaves an anchor whose
	-- relativePoint differs from its point, which is the case that used to be dropped.
	dragTo(_G.LodestarGuideFrame, WANT.stepPos)
	dragTo(_G.LodestarArrow, WANT.arrowPos)
	samePos(G.db.profile.steps.pos, WANT.stepPos, "step frame position in the profile")
	samePos(G.db.profile.arrow.pos, WANT.arrowPos, "arrow position in the profile")

	-- Settings the player changed, one of each shape AceDB treats differently: a number that
	-- differs from its default, a float, and a string.
	G.db.profile.steps.upcoming = WANT.upcoming
	G.db.profile.steps.scale = WANT.scale
	G.db.profile.arrow.mode = WANT.arrowMode

	-- Something harvested this session, written through the real path.
	stub.fire("QUEST_DETAIL")
	local H = G:HarvestDB()
	H.quests[WANT.questID] = { t = "A Test Of Persistence", lvl = 5 }
	check(next(H.npcs) ~= nil or next(H.quests) ~= nil, "session one harvested something to carry over")

	stub.fire("PLAYER_LOGOUT")
	writeSavedVariables()

	-- The whole point is that the file is what carries the data, so say what went into it.
	for addon in pairs(SAVED) do
		local f = io.open(SVDIR .. "/" .. addon .. ".lua", "r")
		local n = f and #f:read("*a") or 0
		if f then f:close() end
		check(n > 0, "wrote saved variables for " .. addon)
	end
	print(("persist/write: %d checks, %d failures"):format(checks, #failures))
elseif MODE == "read" or MODE == "readlegacy" then
	-- The client has handed us last session's file. Nothing below touches it directly: every
	-- check reads through the addon's own accessors, because that is what the player sees.
	if MODE == "read" then
		check(type(_G.LodestarCore) == "table", "the client's LodestarCore reached the addon")
		check(type(_G.LodestarHarvest) == "table", "the client's LodestarHarvest reached the addon")
	else
		-- Adoption has run by now, so the new names hold the data and the old ones are cleared --
		-- leaving them set would make the NEXT login adopt this stale copy over the real thing.
		check(type(_G.LodestarCore) == "table", "legacy LodestarDB was adopted into LodestarCore")
		check(type(_G.LodestarHarvest) == "table", "legacy LodestarShareDB was adopted into LodestarHarvest")
		check(_G.LodestarDB == nil and _G.LodestarShareDB == nil, "the legacy globals were cleared after adoption")
	end

	-- The session counter: session one wrote 1, so a client that hands saved variables back gives
	-- the second session 2. This is the test that says whether reading them back works at all --
	-- on the beta it is an open question, and the answer decides whether half the suite's
	-- persistence work does anything for a player today or only once Blizzard fixes the client.
	check(_G.LodestarProbes and _G.LodestarProbes.sessions == 2,
		"the session counter climbed to 2, got " .. tostring(_G.LodestarProbes and _G.LodestarProbes.sessions))
	check(_G.LodestarProbes and _G.LodestarProbes.sawPreviousSession == true,
		"and this session can tell it saw the previous one")

	samePos(G.db.profile.steps.pos, WANT.stepPos, "step frame position after a relog")
	samePos(G.db.profile.arrow.pos, WANT.arrowPos, "arrow position after a relog")

	-- And the frames themselves have to be built at that anchor, not just hold it in the profile.
	G:UpdateStepFrame()
	G:UpdateArrowFrame()
	local p, _, rel, x, y = _G.LodestarGuideFrame:GetPoint(1)
	samePos({ point = p, rel = rel, x = x, y = y }, WANT.stepPos, "step frame rebuilt where it was left")
	p, _, rel, x, y = _G.LodestarArrow:GetPoint(1)
	samePos({ point = p, rel = rel, x = x, y = y }, WANT.arrowPos, "arrow rebuilt where it was left")

	check(G.db.profile.steps.upcoming == WANT.upcoming,
		"upcoming steps setting survived: " .. tostring(G.db.profile.steps.upcoming))
	check(G.db.profile.steps.scale == WANT.scale,
		"window scale survived: " .. tostring(G.db.profile.steps.scale))
	check(G.db.profile.arrow.mode == WANT.arrowMode,
		"arrow mode survived: " .. tostring(G.db.profile.arrow.mode))

	local H = G:HarvestDB()
	check(type(H.quests) == "table" and H.quests[WANT.questID] ~= nil,
		"the harvested quest came back")
	check(H.quests[WANT.questID] and H.quests[WANT.questID].t == "A Test Of Persistence",
		"the harvested quest came back intact")
	check(type(H.meta) == "table" and type(H.meta.contributors) == "table"
		and next(H.meta.contributors) ~= nil, "the contributor record came back")

	print(("persist/%s: %d checks, %d failures"):format(MODE, checks, #failures))
else
	error("persist.lua: unknown mode " .. tostring(MODE))
end

for _, f in ipairs(failures) do print("  FAIL " .. f) end
if #failures > 0 then os.exit(1) end

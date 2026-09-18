-- Convert All The Things' Camelot (WoW: Forever) database to JSON on stdout.
--
--   lua5.1 tools/att/att_to_json.lua <db/Camelot/**.lua ...> > data/att/att-camelot.json
--
-- ATT's database is not data, it is Lua: each file binds a set of constructor functions off the
-- addon table and then builds one enormous nested call expression out of them --
--
--   q(92461,{coords={[2521]={{42.1,23.5}}},qgs={251361},sourceQuests={92460},g={
--     qo(1,{providers={{"n",250873}}})}})
--
-- so the honest way to read it is to run it with our own constructors bound in place of ATT's and
-- keep the tree they build, rather than to pattern-match the source. Every constructor here just
-- tags its table with what it was and what id it carried; the walk afterwards is what extracts the
-- handful of fields Lodestar wants (where a quest starts, who gives it, what it needs first).
--
-- ATT is MIT licensed (see Lodestar_Guide/Data/LICENSE-ATT.txt). Nothing here modifies their files.
local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end
if #files == 0 then io.stderr:write("usage: att_to_json.lua <file.lua> [file.lua ...]\n") os.exit(2) end

-- Constructors ---------------------------------------------------------------------------------

local function maker(kind)
	return function(id, t)
		if type(id) == "table" and t == nil then t, id = id, nil end
		t = type(t) == "table" and t or {}
		t.__kind, t.__id = kind, id
		return t
	end
end

-- Some constructors take (id, altID, t) -- CreateItemSource(sourceID, itemID, t).
local function maker3(kind)
	return function(a, b, t)
		if type(b) == "table" and t == nil then t, b = b, nil end
		t = type(t) == "table" and t or {}
		t.__kind, t.__id, t.__id2 = kind, a, b
		return t
	end
end

local THREE = { ItemSource = true }

-- A value that survives being indexed, called, concatenated or printed, however deep ATT goes.
-- The localization module builds UI strings out of these, and one unhandled concat was enough to
-- abort a whole file.
local ANYTHING = setmetatable({}, {
	__index = function(t) return t end,
	__call = function() return {} end,
	__concat = function() return "" end,
	__tostring = function() return "" end,
})

local handlers = {}
local app = setmetatable({}, {
	__index = function(_, key)
		if key == "AddEventHandler" then
			return function(_, fn) if type(fn) == "function" then handlers[#handlers + 1] = fn end end
		end
		local kind = tostring(key):match("^Create(.+)$")
		if kind then return (THREE[kind] and maker3 or maker)(kind) end
		-- Anything else ATT reaches for during load. It has to be both indexable and callable: the
		-- database pokes at nested tables off the addon object (`_.OnTooltipDB.RuneclothTurnIns`)
		-- as well as calling helpers, and a plain function stub dies on the first field access --
		-- which silently truncated the walk two thirds of the way through the file.
		return ANYTHING
	end,
})

-- ATT calls AddEventHandler as a plain function (_.AddEventHandler("name", fn)), so the metatable
-- entry above receives the name as its first argument rather than self. Both shapes are accepted.
local realAdd = function(a, b)
	local fn = type(b) == "function" and b or (type(a) == "function" and a or nil)
	if fn then handlers[#handlers + 1] = fn end
end
rawset(app, "AddEventHandler", realAdd)

-- Load -------------------------------------------------------------------------------------------

local env = setmetatable({}, { __index = _G })
local loaded, failed = 0, {}
for _, path in ipairs(files) do
	-- ATT's files carry a UTF-8 BOM, which Lua 5.1's parser rejects outright, so read and strip
	-- rather than loadfile.
	local fh = io.open(path, "rb")
	local src = fh and fh:read("*a") or nil
	if fh then fh:close() end
	if src then src = src:gsub("^\239\187\191", "") end
	local chunk, err
	if src then chunk, err = loadstring(src, "@" .. path) else err = "unreadable" end
	if not chunk then
		failed[#failed + 1] = path .. ": " .. tostring(err)
	else
		setfenv(chunk, env)
		local ok, cerr = pcall(chunk, "AllTheThings", app)
		if ok then loaded = loaded + 1 else failed[#failed + 1] = path .. ": " .. tostring(cerr) end
	end
end

local roots = {}
for _, fn in ipairs(handlers) do
	local categories = {}
	local ok = pcall(fn, categories)
	if ok then roots[#roots + 1] = categories end
end

-- Walk -------------------------------------------------------------------------------------------

local quests, npcs, objects = {}, {}, {}
local counts = { quests = 0, npcs = 0, objects = 0, coords = 0 }

local function addCoords(into, coords, inheritedMap)
	-- ATT writes either coords={[mapID]={{x,y},...}} or coord={x,y,mapID} (and coords as a plain
	-- list of {x,y,mapID}). All three appear in the Camelot database.
	if type(coords) ~= "table" then return end
	for key, value in pairs(coords) do
		if type(key) == "number" and type(value) == "table" then
			if type(value[1]) == "table" then
				-- [mapID] = { {x,y}, ... }
				for _, p in ipairs(value) do
					if tonumber(p[1]) and tonumber(p[2]) then
						into[#into + 1] = { m = key, x = tonumber(p[1]), y = tonumber(p[2]) }
						counts.coords = counts.coords + 1
					end
				end
			elseif tonumber(value[1]) and tonumber(value[2]) then
				-- { x, y, mapID }
				local m = tonumber(value[3]) or inheritedMap
				if m then
					into[#into + 1] = { m = m, x = tonumber(value[1]), y = tonumber(value[2]) }
					counts.coords = counts.coords + 1
				end
			end
		end
	end
end

local function addCoord(into, coord, inheritedMap)
	if type(coord) ~= "table" then return end
	local x, y, m = tonumber(coord[1]), tonumber(coord[2]), tonumber(coord[3]) or inheritedMap
	if x and y and m then
		into[#into + 1] = { m = m, x = x, y = y }
		counts.coords = counts.coords + 1
	end
end

local function idList(v)
	if type(v) ~= "table" then return nil end
	local out = {}
	for _, id in ipairs(v) do if tonumber(id) then out[#out + 1] = tonumber(id) end end
	return #out > 0 and out or nil
end

local seen = {}

local function walk(node, mapID, questID)
	if type(node) ~= "table" or seen[node] then return end
	seen[node] = true

	local kind, id = node.__kind, tonumber(node.__id)
	if kind == "Map" and id then mapID = id end

	if kind == "Quest" and id then
		local q = quests[id]
		if not q then q = { coords = {} } quests[id] = q counts.quests = counts.quests + 1 end
		addCoords(q.coords, node.coords, mapID)
		addCoord(q.coords, node.coord, mapID)
		q.qgs = q.qgs or idList(node.qgs)              -- quest giver NPCs
		q.qis = q.qis or idList(node.qis)              -- quest starter items
		q.prev = q.prev or idList(node.sourceQuests)   -- prerequisites: the chain order
		q.altPrev = q.altPrev or idList(node.altQuests)
		if tonumber(node.lvl) then q.lvl = tonumber(node.lvl) end
		if tonumber(node.awp) then q.awp = tonumber(node.awp) end
		if node.isDaily or node.isWeekly then q.repeatable = true end
		if mapID then q.map = q.map or mapID end
		questID = id
	elseif kind == "QuestObjective" and questID and id then
		local q = quests[questID]
		if q then
			q.obj = q.obj or {}
			local o = { i = id, npcs = {}, items = {}, objects = {}, coords = {} }
			for _, p in ipairs(type(node.providers) == "table" and node.providers or {}) do
				if type(p) == "table" and tonumber(p[2]) then
					local what, pid = p[1], tonumber(p[2])
					if what == "n" then o.npcs[#o.npcs + 1] = pid
					elseif what == "i" then o.items[#o.items + 1] = pid
					elseif what == "o" then o.objects[#o.objects + 1] = pid end
				end
			end
			addCoords(o.coords, node.coords, mapID)
			addCoord(o.coords, node.coord, mapID)
			if #o.npcs == 0 then o.npcs = nil end
			if #o.items == 0 then o.items = nil end
			if #o.objects == 0 then o.objects = nil end
			if #o.coords == 0 then o.coords = nil end
			q.obj[#q.obj + 1] = o
		end
	elseif kind == "NPC" and id and id > 0 then
		local e = npcs[id]
		if not e then e = { coords = {} } npcs[id] = e counts.npcs = counts.npcs + 1 end
		addCoords(e.coords, node.coords, mapID)
		addCoord(e.coords, node.coord, mapID)
		if mapID then e.map = e.map or mapID end
	elseif kind == "Object" and id then
		local e = objects[id]
		if not e then e = { coords = {} } objects[id] = e counts.objects = counts.objects + 1 end
		addCoords(e.coords, node.coords, mapID)
		addCoord(e.coords, node.coord, mapID)
	end

	-- Children, plus any other nested tables (ATT nests groups under g, but also under other keys).
	for key, child in pairs(node) do
		if type(child) == "table" and key ~= "coords" and key ~= "coord" and key ~= "providers" then
			if type(key) == "number" or key == "g" then
				walk(child, mapID, questID)
			elseif child.__kind then
				walk(child, mapID, questID)
			end
		end
	end
end

for _, root in ipairs(roots) do walk(root, nil, nil) end

-- Emit --------------------------------------------------------------------------------------------

local function esc(s)
	return '"' .. tostring(s):gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
		else return string.format("\\u%04x", c:byte()) end
	end) .. '"'
end

local function isArray(v)
	local n = 0
	for k in pairs(v) do if type(k) ~= "number" then return false end n = n + 1 end
	return n == #v
end

local out = {}
local function emit(v)
	local tv = type(v)
	if tv == "table" then
		if isArray(v) and #v > 0 then
			out[#out + 1] = "["
			for i, x in ipairs(v) do if i > 1 then out[#out + 1] = "," end emit(x) end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			local keys = {}
			for k in pairs(v) do if k ~= "__kind" and k ~= "__id" and k ~= "__id2" then keys[#keys + 1] = k end end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do
				if not first then out[#out + 1] = "," end
				first = false
				out[#out + 1] = esc(k) .. ":"
				emit(v[k])
			end
			out[#out + 1] = "}"
		end
	elseif tv == "string" then out[#out + 1] = esc(v)
	elseif tv == "number" then out[#out + 1] = (v % 1 == 0) and string.format("%d", v) or string.format("%.4g", v)
	elseif tv == "boolean" then out[#out + 1] = tostring(v)
	else out[#out + 1] = "null" end
end

emit({ meta = { source = "ATTWoWAddon/AllTheThings", license = "MIT", files = loaded, errors = failed, counts = counts },
	quests = quests, npcs = npcs, objects = objects })
io.write(table.concat(out), "\n")

if #failed > 0 then
	io.stderr:write("att_to_json: " .. #failed .. " file(s) failed:\n")
	for _, e in ipairs(failed) do io.stderr:write("  " .. e .. "\n") end
end
io.stderr:write(string.format("att_to_json: %d files, %d quests, %d npcs, %d objects, %d coords\n",
	loaded, counts.quests, counts.npcs, counts.objects, counts.coords))

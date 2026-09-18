-- Dump a Lodestar recording (raw entries with timestamps) from a SavedVariables file as JSON.
--
--   lua5.1 tools/router/sv2json.lua "WTF/Account/<acct>/SavedVariables/Lodestar.lua" [recording name] > recording.json
--
-- The recording lives at LodestarCore.namespaces.Guide.char["Name - Realm"].recording (active) or
-- .recordingPaused (stopped). The first argument may also be a plain Lua file that sets LodestarCore.
local path, wanted = arg[1], arg[2]
if not path then io.stderr:write("usage: sv2json.lua <SavedVariables/Lodestar.lua> [recording name]\n") os.exit(1) end
local chunk = assert(loadfile(path))
chunk()
local db = _G.LodestarCore
if not (db and db.namespaces and db.namespaces.Guide and db.namespaces.Guide.char) then
	io.stderr:write("no LodestarCore.namespaces.Guide.char in " .. path .. "\n") os.exit(1)
end

local function esc(s) return (tostring(s):gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end)) end
local function json(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 then
			local parts = {}
			for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. esc(k) .. '":' .. json(v[k] ~= nil and v[k] or v[tonumber(k)]) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then return '"' .. esc(v) .. '"'
	elseif t == "number" or t == "boolean" then return tostring(v)
	else return "null" end
end

local out = {}
for charKey, char in pairs(db.namespaces.Guide.char) do
	for _, field in ipairs({ "recording", "recordingPaused" }) do
		local r = char[field]
		if r and r.entries and (not wanted or r.name == wanted) then
			out[#out + 1] = { character = charKey, name = r.name, startedAt = r.startedAt, entries = r.entries }
		end
	end
end
if #out == 0 then io.stderr:write("no recording found\n") os.exit(1) end
io.write(json(#out == 1 and out[1] or out), "\n")

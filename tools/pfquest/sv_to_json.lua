-- Convert a WoW SavedVariables file (Lua assignments) to JSON on stdout.
-- Usage: lua5.1 tools/pfquest/sv_to_json.lua <file.lua> [GlobalName]
local path, name = arg[1], arg[2] or "LodestarScanDB"
local env = {}
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk()
local t = env[name]
local function esc(s) return '"' .. s:gsub('[%c"\\]', function(c) if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" else return string.format("\\u%04x", c:byte()) end end) .. '"' end
local function isArray(v) local n = 0 for k in pairs(v) do if type(k) ~= "number" then return false end n = n + 1 end return n == #v end
local out = {}
local function emit(v)
	local tv = type(v)
	if tv == "table" then
		if isArray(v) and #v > 0 then
			out[#out + 1] = "[" for i, x in ipairs(v) do if i > 1 then out[#out + 1] = "," end emit(x) end out[#out + 1] = "]"
		else
			out[#out + 1] = "{" local first = true
			local keys = {} for k in pairs(v) do keys[#keys + 1] = k end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do if not first then out[#out + 1] = "," end first = false out[#out + 1] = esc(tostring(k)) .. ":" emit(v[k]) end
			out[#out + 1] = "}"
		end
	elseif tv == "string" then out[#out + 1] = esc(v)
	elseif tv == "number" then out[#out + 1] = (v % 1 == 0) and string.format("%d", v) or tostring(v)
	elseif tv == "boolean" then out[#out + 1] = tostring(v)
	else out[#out + 1] = "null" end
end
emit(t)
io.write(table.concat(out), "\n")

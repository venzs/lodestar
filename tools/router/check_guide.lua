-- Parse a guide text file with the real Lodestar_Guide/Parser.lua (no game needed).
--   lua5.1 tools/router/check_guide.lua out.txt
-- Exit code 0 and a summary on success; the parser's "line N: ..." error otherwise.
local ROOT = arg[0]:match("^(.*)tools[/\\]router[/\\]check_guide%.lua$") or "./"
if ROOT == "" then ROOT = "./" end
local path = arg[1]
if not path then io.stderr:write("usage: check_guide.lua <guide.txt>\n") os.exit(2) end

-- minimal WoW globals the parser uses
_G.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.tinsert = table.insert
local GuideModule = {}
_G.Lodestar = { GetModule = function() return GuideModule end }
assert(loadfile(ROOT .. "Lodestar_Guide/Parser.lua"))()
local Parser = GuideModule.Parser

local f = assert(io.open(path, "r"))
local text = f:read("*a")
f:close()
local guide, err = Parser.Parse(text)
if not guide then
	io.stderr:write("PARSE ERROR: " .. tostring(err) .. "\n")
	os.exit(1)
end
local counts = {}
for _, s in ipairs(guide.steps) do
	for _, a in ipairs(s.actions) do counts[a.type] = (counts[a.type] or 0) + 1 end
	if s.arrival then counts.arrival = (counts.arrival or 0) + 1 end
end
local parts = {}
for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
table.sort(parts)
print(("OK: %s | %d steps | levels %s-%s | %s"):format(guide.name, #guide.steps, tostring(guide.minLevel), tostring(guide.maxLevel), table.concat(parts, " ")))
-- ordering sanity: every turnin/complete must follow an accept of the same quest
local accepted = {}
for i, s in ipairs(guide.steps) do
	for _, a in ipairs(s.actions) do
		if a.type == "accept" then accepted[a.questID] = true end
		if (a.type == "turnin" or a.type == "complete") and not accepted[a.questID] then
			io.stderr:write(("ORDER: step %d %s %d before its accept\n"):format(i, a.type, a.questID))
			os.exit(1)
		end
	end
end
print("order OK")

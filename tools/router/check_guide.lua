-- Parse a guide with the real Lodestar_Guide/Parser.lua (no game needed).
--   lua5.1 tools/router/check_guide.lua out.txt                                  router output (plain guide text)
--   lua5.1 tools/router/check_guide.lua Lodestar_Guides_Horde/Horde_Barrens.lua  a guide-pack file: every
--                                                                                 Guide:RegisterGuide([[...]]) block in it
-- Exit code 0 and a summary per guide on success; the parser's "line N: ..." error otherwise.
-- Ordering: a turn-in / complete without an earlier accept is an error for plain text, and a warning for
-- pack files (the quest may come from the previous guide of the #next chain; tools/router/lint_guides.py
-- walks those chains and checks ids and positions against the Vanilla data).
local ROOT = arg[0]:match("^(.*)tools[/\\]router[/\\]check_guide%.lua$") or "./"
if ROOT == "" then ROOT = "./" end
local path = arg[1]
if not path then io.stderr:write("usage: check_guide.lua <guide.txt | guidepack.lua>\n") os.exit(2) end

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

-- a pack file holds one or more RegisterGuide([[ ... ]]) blocks; plain text is one guide
local isPack = path:match("%.lua$") ~= nil
local texts = {}
if isPack then
	for body in text:gmatch("RegisterGuide%(%s*%[%[(.-)%]%]") do texts[#texts + 1] = body end
	if #texts == 0 then io.stderr:write("no Guide:RegisterGuide([[...]]) block in " .. path .. "\n") os.exit(1) end
else
	texts[1] = text
end

local failed = false
for _, guideText in ipairs(texts) do
	local guide, err = Parser.Parse(guideText)
	if not guide then
		io.stderr:write("PARSE ERROR: " .. tostring(err) .. "\n")
		os.exit(1)
	end
	local counts = {}
	for _, s in ipairs(guide.steps) do
		for _, a in ipairs(s.actions) do counts[a.type] = (counts[a.type] or 0) + 1 end
		if s.arrival then counts.arrival = (counts.arrival or 0) + 1 end
		if s.optional then counts.optional = (counts.optional or 0) + 1 end
	end
	local parts = {}
	for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
	table.sort(parts)
	print(("OK: %s | %d steps | levels %s-%s | %s"):format(guide.name, #guide.steps, tostring(guide.minLevel), tostring(guide.maxLevel), table.concat(parts, " ")))
	-- ordering sanity: every turnin/complete should follow an accept of the same quest
	local accepted, crossGuide = {}, 0
	for i, s in ipairs(guide.steps) do
		for _, a in ipairs(s.actions) do
			if a.type == "accept" then accepted[a.questID] = true end
			if (a.type == "turnin" or a.type == "complete") and not accepted[a.questID] then
				if isPack then
					crossGuide = crossGuide + 1
					io.stderr:write(("note: step %d %s %d has no accept in this guide (previous guide of the chain?)\n"):format(i, a.type, a.questID))
					accepted[a.questID] = true
				else
					io.stderr:write(("ORDER: step %d %s %d before its accept\n"):format(i, a.type, a.questID))
					failed = true
				end
			end
		end
	end
	if not failed then print(crossGuide > 0 and ("order OK (%d quests from a previous guide)"):format(crossGuide) or "order OK") end
end
if failed then os.exit(1) end

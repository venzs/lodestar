-- Lodestar_Guide: guide text format and parser (pure Lua, no game calls).
--
--   #guide Horde/Undead 1-6: Deathknell      required, unique name
--   #faction Horde                            Alliance | Horde | Both (default Both)
--   #race Undead,Orc                          optional filters, comma separated
--   #class Paladin,Warrior
--   #levels 1-6                               level range this guide covers
--   #next Horde/Undead 6-12: Tirisfal Glades  guide to load when this one ends
--   #author abhi
--   #note Draft recorded on beta, verify.
--
--   step [label shown instead of the generated text]
--     .goto 18,30.8,66.2[,radius]            map id or zone name; arrow target. Goto-only steps
--                                             complete on arrival (radius in yards, default 10).
--     .accept 3901[,364] [>>Accept Rude Awakening]
--     .turnin 3901 [>>text]
--     .complete 364[,objectiveIndex] [>>Kill 8 Mindless Zombies]
--     .xp 3            (or .level 3)          complete at level 3
--     .zone Tirisfal Glades                   complete when you are in the zone
--     .train [>>text]                          completes when a trainer window closes
--     .hs Deathknell [>>text]                  completes when the hearthstone is bound
--     .fly Brill [>>text]                      completes when a flight is taken
--     .vendor / .repair / .text >>Free text    informational; click Next to continue
--     .class Paladin     .race Undead          skip this step for other classes/races
--     .train Shan Stillwell [>>text]           optional trainer name, shown in the step text
--     .buy 2320,2 [>>text]                     completes when you carry that many of the item
--     .profession Skinning,Herbalism [>>text]  completes when the character knows those professions
--     .camp / .cook [>>text]                   Forever camp and cooking buffs; click Next to continue
--     .optional [>>reason]                     completionist-only step (skipped in speed-run mode)
--     .item 6948[,itemID]                      skip the step unless you carry the item(s)
--     .path 30.8,66.2;31.0,65.5;...           a trail of percent points for the map (step.path)
--   -- comment lines start with -- or ;
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local Parser = {}
Guide.Parser = Parser

local ACTION_TYPES = {
	accept = true, turnin = true, complete = true, xp = true, level = true, zone = true, train = true,
	hs = true, fly = true, vendor = true, repair = true, text = true, ["goto"] = true, class = true, race = true, link = true,
	buy = true, optional = true, path = true, profession = true, camp = true, cook = true, item = true,
}

local DEFAULT_TEXT = {
	camp = "Set up camp / use a campfire",
	cook = "Cook food for the XP buff",
}

local function splitList(s)
	local out = {}
	for part in (s or ""):gmatch("[^,]+") do
		part = strtrim(part)
		if part ~= "" then tinsert(out, part) end
	end
	return out
end

local function toSet(list)
	if not list or #list == 0 then return nil end
	local set = {}
	for _, v in ipairs(list) do set[v:lower()] = true end
	return set
end

--- Parse `directive` arguments and the optional `>>text` override.
local function splitArgsText(rest)
	local args, text = rest:match("^(.-)%s*>>%s*(.-)%s*$")
	if not args then args = rest end
	args = strtrim(args or "")
	if text == "" then text = nil end
	return args, text
end

local function parseGoto(args)
	-- "18,30.8,66.2" | "Tirisfal Glades,30.8,66.2,15"
	local parts = splitList(args)
	if #parts < 3 then return nil, "goto needs map,x,y" end
	local x, y = tonumber(parts[2]), tonumber(parts[3])
	if not x or not y then return nil, "goto coordinates must be numbers" end
	local map = tonumber(parts[1]) or parts[1]
	return { map = map, x = x, y = y, radius = tonumber(parts[4]) }
end

local function parsePath(args)
	-- "30.8,66.2;31.0,65.5;..." (percent coordinates on the step's map)
	local path = {}
	for pair in (args or ""):gmatch("[^;]+") do
		local x, y = pair:match("^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*$")
		x, y = tonumber(x), tonumber(y)
		if not x or not y then return nil, "path points must be x,y pairs separated by ;" end
		tinsert(path, { x = x, y = y })
	end
	if #path == 0 then return nil, "path needs at least one x,y point" end
	return path
end

local function parseIDs(args, what)
	local ids = {}
	for _, id in ipairs(splitList(args)) do
		local n = tonumber(id)
		if not n then return nil, what .. ": bad id " .. id end
		tinsert(ids, n)
	end
	if #ids == 0 then return nil, what .. " needs an id" end
	return ids
end

--- Parse guide text. Returns guide table or nil, error.
function Parser.Parse(text)
	if type(text) ~= "string" then return nil, "guide text must be a string" end
	local guide = { faction = "Both", steps = {}, source = text }
	local step
	local lineNo = 0

	local function fail(msg) return nil, ("line %d: %s"):format(lineNo, msg) end

	for rawLine in (text .. "\n"):gmatch("(.-)\r?\n") do
		lineNo = lineNo + 1
		local line = strtrim(rawLine)
		if line == "" or line:match("^%-%-") or line:match("^;") then
			-- comment / blank
		elseif line:match("^#") then
			local key, value = line:match("^#(%w+)%s*(.-)$")
			key = key and key:lower()
			if key == "guide" or key == "name" then
				guide.name = value
			elseif key == "faction" then
				guide.faction = value:sub(1, 1):upper() .. value:sub(2):lower()
			elseif key == "race" or key == "races" then
				guide.races = toSet(splitList(value))
			elseif key == "class" or key == "classes" then
				guide.classes = toSet(splitList(value))
			elseif key == "levels" or key == "level" then
				local a, b = value:match("(%d+)%s*%-%s*(%d+)")
				guide.minLevel, guide.maxLevel = tonumber(a) or tonumber(value), tonumber(b) or tonumber(value)
			elseif key == "next" then
				guide.next = value
			elseif key == "author" then
				guide.author = value
			elseif key == "version" then
				guide.version = value
			elseif key == "note" then
				guide.note = value
			end
		elseif line:lower():match("^step%f[%W]") or line:lower() == "step" then
			step = { actions = {}, label = strtrim(line:sub(5)) }
			if step.label == "" then step.label = nil end
			tinsert(guide.steps, step)
		elseif line:match("^%.") then
			if not step then return fail("directive before the first 'step'") end
			local directive, rest = line:match("^%.(%w+)%s*(.-)$")
			directive = directive and directive:lower()
			if not ACTION_TYPES[directive] then return fail("unknown directive ." .. tostring(directive)) end
			local args, label = splitArgsText(rest or "")
			if directive == "goto" then
				local g, err = parseGoto(args)
				if not g then return fail(err) end
				g.text = label
				step.go = g
			elseif directive == "class" then
				step.classes = toSet(splitList(args))
			elseif directive == "race" then
				step.races = toSet(splitList(args))
			elseif directive == "link" then
				step.link = args
			elseif directive == "optional" then
				step.optional = true
				step.optionalReason = label or (args ~= "" and args or nil)
			elseif directive == "path" then
				local p, err = parsePath(args)
				if not p then return fail(err) end
				step.path = p
			elseif directive == "item" then
				local ids, err = parseIDs(args, "item")
				if not ids then return fail(err) end
				step.requireItems = ids
			elseif directive == "buy" then
				local parts = splitList(args)
				local itemID = tonumber(parts[1])
				if not itemID then return fail("buy needs an item id") end
				local count = tonumber(parts[2])
				if parts[2] and not count then return fail("buy: bad count " .. parts[2]) end
				tinsert(step.actions, { type = "buy", itemID = itemID, count = count or 1, text = label })
			elseif directive == "profession" then
				local names = splitList(args)
				if #names == 0 then return fail("profession needs a name") end
				tinsert(step.actions, { type = "profession", names = names, text = label })
			elseif directive == "accept" then
				local ids = splitList(args)
				if #ids == 0 then return fail("accept needs a quest id") end
				for _, id in ipairs(ids) do
					local n = tonumber(id)
					if not n then return fail("accept: bad quest id " .. id) end
					tinsert(step.actions, { type = "accept", questID = n, text = label })
				end
			elseif directive == "turnin" then
				local ids = splitList(args)
				if #ids == 0 then return fail("turnin needs a quest id") end
				for _, id in ipairs(ids) do
					local n = tonumber(id)
					if not n then return fail("turnin: bad quest id " .. id) end
					tinsert(step.actions, { type = "turnin", questID = n, text = label })
				end
			elseif directive == "complete" then
				local parts = splitList(args)
				local qid = tonumber(parts[1])
				if not qid then return fail("complete needs a quest id") end
				tinsert(step.actions, { type = "complete", questID = qid, objective = tonumber(parts[2]), text = label })
			elseif directive == "xp" or directive == "level" then
				local lvl = tonumber(args:match("^(%d+)"))
				if not lvl then return fail("xp needs a level") end
				tinsert(step.actions, { type = "level", level = lvl, text = label })
			elseif directive == "zone" then
				if args == "" then return fail("zone needs a name") end
				tinsert(step.actions, { type = "zone", zone = args, text = label })
			elseif directive == "hs" or directive == "fly" or directive == "train" then
				tinsert(step.actions, { type = directive, name = args ~= "" and args or nil, text = label })
			else -- vendor, repair, text, camp, cook
				tinsert(step.actions, { type = directive, text = label or (args ~= "" and args or nil) })
			end
		else
			return fail("unrecognised line: " .. line)
		end
	end

	if not guide.name then return nil, "guide has no #guide name" end
	if #guide.steps == 0 then return nil, "guide has no steps" end
	for i, s in ipairs(guide.steps) do
		s.index = i
		-- A step with a goto and nothing else completes on arrival.
		s.arrival = s.go ~= nil and #s.actions == 0
	end
	return guide
end

local function joinNames(names)
	if #names <= 1 then return names[1] or "" end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- Human text for an action; questName(id), objectiveText(id, index) and itemName(id) are optional lookups.
function Parser.ActionText(action, questName, objectiveText, itemName)
	if action.text then return action.text end
	local t = action.type
	local qn = action.questID and (questName and questName(action.questID)) or (action.questID and ("quest #" .. action.questID))
	if t == "accept" then return "Accept " .. qn end
	if t == "turnin" then return "Turn in " .. qn end
	if t == "complete" then
		local obj = objectiveText and objectiveText(action.questID, action.objective)
		return obj or ("Complete " .. qn)
	end
	if t == "level" then return "Reach level " .. action.level end
	if t == "zone" then return "Go to " .. action.zone end
	if t == "train" then return "Train new skills" .. (action.name and (" at " .. action.name) or "") end
	if t == "hs" then return "Set your hearthstone" .. (action.name and (" at " .. action.name) or "") end
	if t == "fly" then return "Fly to " .. (action.name or "the next flight point") end
	if t == "vendor" then return "Sell junk and restock at a vendor" end
	if t == "repair" then return "Repair" end
	if t == "buy" then
		local name = (itemName and itemName(action.itemID)) or ("item #" .. action.itemID)
		return "Buy " .. ((action.count or 1) > 1 and (action.count .. "x ") or "") .. name
	end
	if t == "profession" then return "Train " .. joinNames(action.names or {}) end
	if DEFAULT_TEXT[t] then return DEFAULT_TEXT[t] end
	return action.text or "Continue"
end

--- Full display text for a step.
function Parser.StepText(step, questName, objectiveText, mapName, itemName)
	if step.label then return step.label end
	local parts = {}
	for _, a in ipairs(step.actions) do tinsert(parts, Parser.ActionText(a, questName, objectiveText, itemName)) end
	if #parts == 0 and step.go then
		local where = step.go.text or (mapName and mapName(step.go.map)) or tostring(step.go.map)
		return ("Go to %.1f, %.1f in %s"):format(step.go.x, step.go.y, where)
	end
	return table.concat(parts, " · ")
end

--- Does this step apply to the player? classFile/raceName are lower-case. `completionist` shows
--- .optional steps; hasItem(itemID) (optional) decides .item filters.
function Parser.StepApplies(step, classFile, raceName, completionist, hasItem)
	if step.classes and not step.classes[classFile] then return false end
	if step.races and not step.races[raceName] then return false end
	if step.optional and not completionist then return false end
	if step.requireItems and hasItem then
		for _, id in ipairs(step.requireItems) do
			if not hasItem(id) then return false end
		end
	end
	return true
end

--- Does the guide apply to the player?
function Parser.GuideApplies(guide, faction, classFile, raceName, level)
	if guide.faction ~= "Both" and faction and guide.faction ~= faction then return false end
	if guide.classes and classFile and not guide.classes[classFile] then return false end
	if guide.races and raceName and not guide.races[raceName] then return false end
	if level and guide.minLevel and guide.maxLevel and (level < guide.minLevel or level > guide.maxLevel) then return false end
	return true
end

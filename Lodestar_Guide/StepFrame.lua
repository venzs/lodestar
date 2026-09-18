-- Lodestar_Guide: the guide window — the addon's main interface.
--
-- Top to bottom:
--   title       guide name · 41/71 · Sync ‹ ›            (right-click anywhere opens the guide menu)
--   location    Brill · Tirisfal Glades       142 yd  NE
--   headline    what this step IS, in plain words ("Turn in and pick up at Shadow Priest Sarvis")
--   actions     one row per action, not one sentence:
--                   [+] Turn in  Rude Awakening (lvl 1)
--                   [ ] Accept   The Mindless Ones (lvl 2)
--                       Kill 8 Mindless Zombies in the graveyard          <- grey detail line
--   banner      class trainer suggestion / "you look further along" sync hint / guide finished
--   coming up   the next applicable steps, one readable line each
-- Smart mode keeps the same skeleton: the lead item is the headline, the rest of the list becomes
-- action rows grouped by kind (Turn in / Do / Pick up / Train / Hub) with a distance on each.
--
-- Nothing here is protected and nothing writes to a Blizzard-owned global or function; see the header
-- of Lodestar_Character/Panel.lua for what that costs on Forever. RefreshStepFrame runs on the guide
-- events and on a 2 s ticker, so everything expensive — harvested zone names, quest titles and levels,
-- per-action positions — is derived once per step and cached. Only the live parts (completion glyphs,
-- objective progress, distance and bearing) are recomputed on every pass, and every row is rendered
-- inside a pcall so one bad row cannot blank the window.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH = 360, 260, 520
local MAX_ACTION_ROWS = 14        -- action rows / smart list rows (including group headers)
local MAX_UPCOMING = 10           -- matches the maximum of the steps.upcoming option
local PAD = 10
local WIDTH_PRESETS = { 280, 320, 360, 400, 440, 480, 520 }
local TITLE_BUTTONS = 110         -- pixels the Sync / ‹ / › buttons take out of the title bar

local GREEN, GOLD, WHITE, BLUE, GREY, DIM = "|cff7fff7f", "|cffffd700", "|cffffffff", "|cff4fc3f7", "|cffaaaaaa", "|cff888888"
-- Plain ASCII on purpose: the glyph must not depend on the player's font having box-drawing or check marks.
local DONE_GLYPH, TODO_GLYPH = GREEN .. "[+]|r", DIM .. "[ ]|r"
local OPTIONAL_TAG = " " .. DIM .. "(optional)|r"

-- Verb chip per action type: label, colour. Turn-ins green, pick-ups gold, objectives white,
-- travel blue, chores grey.
local VERB = {
	turnin     = { "Turn in", GREEN },
	accept     = { "Accept",  GOLD },
	complete   = { "Do",      WHITE },
	level      = { "Reach",   WHITE },
	zone       = { "Reach",   BLUE },
	hs         = { "Hearth",  BLUE },
	fly        = { "Fly",     BLUE },
	train      = { "Train",   BLUE },
	buy        = { "Buy",     GREY },
	profession = { "Train",   GREY },
	vendor     = { "Vendor",  GREY },
	repair     = { "Repair",  GREY },
	camp       = { "Camp",    GREY },
	cook       = { "Cook",    GREY },
	text       = { "Do",      GREY },
}

-- Smart mode: the list kinds, in the order their groups are shown.
local KIND_LABEL = { turnin = "Turn in", objective = "Do", available = "Pick up", train = "Train", hub = "Hub" }
local KIND_COLOR = { turnin = GREEN, objective = WHITE, available = GOLD, train = BLUE, hub = GREY }
local KIND_ORDER = { "turnin", "objective", "available", "train", "hub" }

local COMPASS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }

local frame
local actionRows, upcomingRows = {}, {}
local stepCache = {}              -- derived-once-per-step values (see derive())
local placeCache = {}             -- [map:x:y] = { zone, sub } | false   harvested zone names
local pendingQuestLoads = {}
local focus                       -- the action row the player clicked, while the arrow follows it

-- Small helpers -----------------------------------------------------------------------------------

local function cfg() return Guide.db.profile.steps end

local function frameWidth()
	local w = tonumber(cfg().width) or DEFAULT_WIDTH
	return math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor(w + 0.5)))
end

--- Rough character budget for `px` pixels of text at the current font scale. Only used to trim long
--- names; the font strings also have word wrap off so the client ellipsises whatever still overflows.
local function fitChars(px, scale)
	return math.max(6, math.floor(px / (5.4 * (scale or 1))))
end

local function trim(text, maxChars)
	if type(text) ~= "string" then return "" end
	maxChars = math.max(8, math.floor(tonumber(maxChars) or 80))
	if #text <= maxChars then return text end
	return text:sub(1, maxChars - 3) .. "..."
end

--- A very small plural for headline text ("Kill Rot Hide Mongrel" reads wrong). Approximate on purpose.
local function plural(name)
	if type(name) ~= "string" or name == "" then return name end
	local last = name:sub(-1)
	if last == "s" or last == "x" or last == "z" or name:sub(-2) == "sh" or name:sub(-2) == "ch" then return name .. "es" end
	if last == "y" and not ("aeiou"):find(name:sub(-2, -2), 1, true) then return name:sub(1, -2) .. "ies" end
	return name .. "s"
end

--- "Train new skills at Shan Stillwell" under a "Train" chip reads better as "New skills at ...".
--- Only a leading copy of the chip's own verb is dropped, and never when the rest would start with "to".
local function stripVerb(text, verb)
	if type(text) ~= "string" or type(verb) ~= "string" then return text end
	if text:lower():sub(1, #verb + 1) ~= verb:lower() .. " " then return text end
	local rest = text:sub(#verb + 2)
	if rest == "" or rest:lower():sub(1, 3) == "to " then return text end
	return rest:sub(1, 1):upper() .. rest:sub(2)
end

local function savePosition()
	local point, _, _, x, y = frame:GetPoint(1)
	cfg().pos = { point = point or "TOPRIGHT", x = x or 0, y = y or 0 }
end

local function makeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 26, 20)
	b:SetText(text)
	return b
end

local function makeText(parent, template, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetJustifyV("TOP")
	local _, size = fs:GetFont()
	fs.baseSize = tonumber(size) or 10
	return fs
end

local function applyFont(fs, scale)
	if not (fs and fs.baseSize) then return end
	local file, _, flags = fs:GetFont()
	if not file then return end
	pcall(fs.SetFont, fs, file, math.max(8, math.floor(fs.baseSize * scale + 0.5)), flags)
end

-- Quest facts -------------------------------------------------------------------------------------

--- Quest title and whether the client/data actually knew it (an unknown title is not cached).
local function questTitle(questID)
	if not questID then return nil, true end
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if type(title) == "string" and title ~= "" then return title, true end
	if Guide.DataQuestInfo then
		local ok, dataTitle = pcall(Guide.DataQuestInfo, Guide, questID)
		if ok and type(dataTitle) == "string" and dataTitle ~= "" then return dataTitle, true end
	end
	if C_QuestLog.RequestLoadQuestByID and not pendingQuestLoads[questID] then
		pendingQuestLoads[questID] = true
		pcall(C_QuestLog.RequestLoadQuestByID, questID)
	end
	return "quest #" .. questID, false
end

local function questLevel(questID)
	if not questID then return nil end
	if Guide.DataQuestInfo then
		local ok, _, lvl = pcall(Guide.DataQuestInfo, Guide, questID)
		if ok and type(lvl) == "number" and lvl > 0 then return lvl end
	end
	if C_QuestLog.GetQuestDifficultyLevel then
		local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
		if ok and type(lvl) == "number" and lvl > 0 then return lvl end
	end
	return nil
end

local DIFF = { trivial = "|cff808080", easy = "|cff40c040", fair = "|cffffff00", hard = "|cffff8040", impossible = "|cffff2020" }

--- The level at or below which a quest is grey for a level `level` character (classic bands).
local function greyLevel(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - math.floor(level / 10) - 5 end
	if level <= 59 then return level - math.floor(level / 5) - 1 end
	return level - 9
end

--- Difficulty colour code for a quest. Uses the client's own answer when this build has it
--- (C_PlayerInfo.GetContentDifficultyQuestForPlayer), otherwise the classic level bands.
local function difficultyColor(questID, level)
	local rel = Enum and Enum.RelativeContentDifficulty
	if questID and rel and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
		local ok, d = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
		if ok and d ~= nil then
			if d == rel.Trivial then return DIFF.trivial end
			if d == rel.Easy then return DIFF.easy end
			if d == rel.Fair then return DIFF.fair end
			if d == rel.Difficult then return DIFF.hard end
			if d == rel.Impossible then return DIFF.impossible end
		end
	end
	if type(level) ~= "number" then return WHITE end
	local player = UnitLevel("player") or level
	local diff = level - player
	if diff >= 5 then return DIFF.impossible end
	if diff >= 3 then return DIFF.hard end
	if diff >= -2 then return DIFF.fair end
	if level > greyLevel(player) then return DIFF.easy end
	return DIFF.trivial
end

--- "Rude Awakening (lvl 2)", coloured by how hard it is for this character. `title` overrides the
--- lookup when the caller already has a name the client gave it (smart-mode list items).
local function questLabel(questID, level, maxChars, title)
	if not title or title == "" then title = (questTitle(questID)) end
	local text = trim(title, maxChars or 80)
	if level then text = text .. " (lvl " .. level .. ")" end
	return difficultyColor(questID, level) .. text .. "|r"
end

local function itemLabel(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if type(name) == "string" and name ~= "" then return name, true end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
	return "item #" .. tostring(itemID), false
end

--- The objective line for a .complete action: the client's live text, which already carries "4/7".
local function objectiveProgress(action)
	if not (action and action.questID and C_QuestLog.GetQuestObjectives) then return nil end
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, action.questID)
	if not ok or type(objectives) ~= "table" then return nil end
	local chosen = action.objective and objectives[action.objective]
	if not chosen then
		for _, o in ipairs(objectives) do
			if not o.finished and o.text and o.text ~= "" then chosen = o break end
		end
	end
	chosen = chosen or objectives[1]
	if not chosen then return nil end
	local text = chosen.text
	if (not text or text == "") and chosen.numRequired then
		text = ("%s/%s"):format(tostring(chosen.numFulfilled or 0), tostring(chosen.numRequired))
	end
	if not text or text == "" then return nil end
	return text, chosen.finished and true or false
end

-- Places and directions ---------------------------------------------------------------------------

--- Zone / subzone the harvest recorded for a known NPC or object standing near (mapID, x, y).
--- Cached per rounded position: the scan is only worth doing once per step.
local function harvestPlace(mapID, x, y)
	if not (mapID and x and y and Guide.HarvestDB) then return nil end
	local key = ("%d:%d:%d"):format(mapID, math.floor(x * 1000), math.floor(y * 1000))
	local hit = placeCache[key]
	if hit ~= nil then
		if hit == false then return nil end
		return hit.zone, hit.sub
	end
	local ok, db = pcall(Guide.HarvestDB, Guide)
	if not ok or type(db) ~= "table" then
		placeCache[key] = false
		return nil
	end
	local px, py = x * 100, y * 100
	local best, bestDist
	local function scan(store)
		for _, e in pairs(store or {}) do
			if e.map == mapID and e.x and e.y and (e.subzone or e.zone) then
				local dx, dy = e.x - px, e.y - py
				local d = dx * dx + dy * dy
				-- 2.5 percent of the map is roughly 100 yd on a Vanilla zone: close enough to share a subzone.
				if d <= 6.25 and (not bestDist or d < bestDist) then best, bestDist = e, d end
			end
		end
	end
	scan(db.npcs)
	scan(db.objects)
	if not best then
		placeCache[key] = false
		return nil
	end
	placeCache[key] = { zone = best.zone, sub = best.subzone }
	return best.zone, best.subzone
end

--- "Brill · Tirisfal Glades" for a map position, falling back to the map name and then to the
--- player's own zone.
local function placeName(mapID, x, y)
	local zone, sub = harvestPlace(mapID, x, y)
	if not zone or zone == "" then
		zone = mapID and Guide:MapName(mapID) or nil
	end
	if not zone or zone == "" then
		local ok, z = pcall(GetRealZoneText)
		zone = (ok and type(z) == "string" and z ~= "") and z or nil
	end
	if sub and sub ~= "" and sub ~= zone then
		return (zone and (sub .. " · " .. zone) or sub), sub
	end
	return zone, sub
end

--- The shortest name that still says where: the subzone when one is known, else the zone.
local function shortPlaceName(mapID, x, y)
	local full, sub = placeName(mapID, x, y)
	if sub and sub ~= "" then return sub end
	return full
end

local function compass(bearing)
	if type(bearing) ~= "number" then return nil end
	local twoPi = math.pi * 2
	local b = bearing % twoPi
	if b < 0 then b = b + twoPi end
	return COMPASS[(math.floor(b / (math.pi / 4) + 0.5) % 8) + 1]
end

--- The location bar text for a target: where it is, how far and which way.
local function locationLine(mapID, x, y, preferArrowDistance)
	if not (mapID and x and y) then return DIM .. "No position for this step|r" end
	local where = placeName(mapID, x, y) or "Somewhere"
	local dist, bearing = Guide:VectorTo(mapID, x, y)
	if preferArrowDistance then
		local target = Guide:GetArrowTarget()
		if target and target.kind == "guide" then dist = Guide:GetArrowDistance() or dist end
	end
	if not dist then
		return ("%s   %sother zone|r"):format(where, DIM)
	end
	local dir = compass(bearing)
	return ("%s   %s%d yd|r%s"):format(where, GREY, math.floor(dist), dir and ("  " .. DIM .. dir .. "|r") or "")
end

-- Where a single action lives ---------------------------------------------------------------------

local function dataPosition(questID, complete)
	if not (questID and Guide.DataQuestPosition) then return nil end
	local ok, mapID, x, y = pcall(Guide.DataQuestPosition, Guide, questID, complete)
	if ok and mapID then return mapID, x, y end
	return nil
end

local function harvestPosition(questID, complete)
	if not (questID and Guide.HarvestQuestPosition) then return nil end
	local ok, mapID, x, y = pcall(Guide.HarvestQuestPosition, Guide, questID, complete)
	if ok and mapID then return mapID, x, y end
	return nil
end

--- The action's own spot (quest giver, ender or objective) when anything knows one.
local function actionPosition(action)
	local t = action and action.type
	if not (t and action.questID) then return nil end
	local mapID, x, y
	if t == "turnin" then
		mapID, x, y = dataPosition(action.questID, true)
		if not mapID then mapID, x, y = harvestPosition(action.questID, true) end
	elseif t == "accept" then
		if Guide.DataQuestStartPosition then
			local ok, m, ax, ay = pcall(Guide.DataQuestStartPosition, Guide, action.questID)
			if ok and m then mapID, x, y = m, ax, ay end
		end
	elseif t == "complete" then
		if C_QuestLog.GetNextWaypoint and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(action.questID) then
			local ok, m, wx, wy = pcall(C_QuestLog.GetNextWaypoint, action.questID)
			if ok and m and wx and wy then mapID, x, y = m, wx, wy end
		end
		if not mapID then mapID, x, y = dataPosition(action.questID, false) end
		if not mapID then mapID, x, y = harvestPosition(action.questID, false) end
	end
	if mapID and x and y then return mapID, x, y end
	return nil
end

-- Pointing the arrow ------------------------------------------------------------------------------

--- Drop the temporary waypoint a row click created and hand the arrow back to the guide step.
local function releaseFocus()
	if not focus then return end
	local held = focus
	focus = nil
	local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	local pos = wp and wp.position
	if pos and wp.uiMapID == held.mapID and math.abs((pos.x or 0) - held.x) < 1e-4 and math.abs((pos.y or 0) - held.y) < 1e-4 then
		if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	end
	if Guide.db.profile.arrow.mode == "WAYPOINT" then Guide.db.profile.arrow.mode = "AUTO" end
	Guide:RetargetArrow()
end

--- Point the arrow at one action by dropping a waypoint on it (the same mechanism as /way). Returns
--- false when the position cannot be used, so the caller falls back to the step itself.
local function pointArrowAt(mapID, x, y, stepIndex)
	if not (mapID and x and y and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
	local ok, wasSet = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
	if not ok or wasSet == false then return false end
	focus = { mapID = mapID, x = x, y = y, step = stepIndex }
	Guide.db.profile.arrow.mode = "WAYPOINT"
	Guide:RetargetArrow()
	return true
end

local function pointArrowAtStep()
	releaseFocus()
	Guide.db.profile.arrow.mode = "AUTO"
	Guide:RetargetArrow()
end

-- Per-step derivation (cached) --------------------------------------------------------------------

local function stepTarget(step)
	if not (step and step.go) then return nil end
	local mapID = Guide:ResolveMap(step.go.map)
	if not mapID then return nil end
	return mapID, step.go.x / 100, step.go.y / 100
end

--- Names the built-in data knows for the quests in a step: who hands them out, who takes them back,
--- and what the first objective is about.
local function stepNPCNames(step)
	local giver, ender, objName, objIsCreature
	if not Guide.DataQuestNames then return nil end
	for _, a in ipairs(step.actions) do
		if a.questID then
			local ok, g, e, o, isCreature = pcall(Guide.DataQuestNames, Guide, a.questID)
			if ok then
				if a.type == "accept" and not giver then giver = g end
				if a.type == "turnin" and not ender then ender = e end
				if a.type == "complete" and not objName then objName, objIsCreature = o, isCreature end
			end
		end
	end
	return giver, ender, objName, objIsCreature
end

--- One short line saying what this step is.
local function headlineFor(step, chars)
	if step.label then return trim(step.label, chars * 2) end
	local counts, first = {}, {}
	for _, a in ipairs(step.actions) do
		counts[a.type] = (counts[a.type] or 0) + 1
		first[a.type] = first[a.type] or a
	end
	local giver, ender, objName, objIsCreature = stepNPCNames(step)
	local at = ender or giver
	if (counts.turnin or 0) > 0 and (counts.accept or 0) > 0 then
		return "Turn in and pick up" .. (at and (" at " .. at) or "")
	end
	if (counts.turnin or 0) > 0 then
		if at then return "Turn in at " .. at end
		return "Turn in " .. (questTitle(first.turnin.questID))
	end
	if (counts.accept or 0) > 0 then
		if giver then return "Pick up at " .. giver end
		return "Pick up " .. (questTitle(first.accept.questID))
	end
	if (counts.complete or 0) > 0 then
		if objName then return (objIsCreature and "Kill " or "Find ") .. plural(objName) end
		return "Work on " .. (questTitle(first.complete.questID))
	end
	if #step.actions == 0 and step.go then
		local mapID, x, y = stepTarget(step)
		return "Run to " .. (step.go.text or (mapID and shortPlaceName(mapID, x, y)) or Guide:MapName(step.go.map))
	end
	local a = step.actions[1]
	return a and trim(Guide:ActionText(a), chars * 2) or "Continue"
end

--- Everything about a step that does not change between refreshes.
local function derive(guide, step, chars)
	local d = { rows = {}, resolved = true }
	d.headline = headlineFor(step, chars)
	d.mapID, d.x, d.y = stepTarget(step)
	for _, a in ipairs(step.actions) do
		local verb = VERB[a.type] or { "Do", WHITE }
		local row = { action = a, verb = verb[1], color = verb[2] }
		if a.questID then
			local title, known = questTitle(a.questID)
			row.questID, row.title = a.questID, title
			row.level = questLevel(a.questID)
			if not known then d.resolved = false end
			if a.text then row.detail = a.text end
		elseif a.type == "buy" then
			local name, known = itemLabel(a.itemID)
			row.itemID, row.title, row.need = a.itemID, name, a.count or 1
			if not known then d.resolved = false end
			if a.text then row.detail = a.text end
		else
			-- The author's own >>text is never rewritten; a generated one loses the verb the chip repeats.
			local generated = Guide:ActionText(a)
			row.title = a.text and generated or stripVerb(generated, verb[1])
		end
		row.mapID, row.x, row.y = actionPosition(a)
		tinsert(d.rows, row)
	end
	-- "Coming up": the next steps that apply to this character, as one readable line each.
	d.upcoming = {}
	local pf = Guide:PlayerFilters()
	for idx = step.index + 1, #guide.steps do
		if #d.upcoming >= MAX_UPCOMING then break end
		local s = guide.steps[idx]
		if Guide:StepApplies(s, pf) then
			local parts = {}
			for _, a in ipairs(s.actions) do
				if a.type == "turnin" then
					tinsert(parts, "turn in " .. (questTitle(a.questID)))
				elseif a.type == "accept" then
					tinsert(parts, "accept " .. (questTitle(a.questID)))
				elseif a.type == "complete" then
					tinsert(parts, "do " .. (questTitle(a.questID)))
				else
					tinsert(parts, Guide:ActionText(a))
				end
			end
			local where
			if s.go then
				local m, sx, sy = stepTarget(s)
				where = s.go.text or (m and shortPlaceName(m, sx, sy)) or nil
			end
			if #parts == 0 then parts[1] = where and ("run to " .. where) or Guide:StepText(s) end
			local line = ("%d. %s%s"):format(s.index, (where and #s.actions > 0) and (where .. " — ") or "", table.concat(parts, ", "))
			tinsert(d.upcoming, { index = s.index, text = line .. (s.optional and OPTIONAL_TAG or "") })
		end
	end
	return d
end

--- The cached derivation for the current step, rebuilt when the step, the guide, the character's
--- level or an unresolved quest name changes.
local function stepData(guide, step, chars)
	local key = ("%s#%d#%d#%d"):format(guide.name or "?", step.index, UnitLevel("player") or 0, chars)
	if stepCache.key == key and stepCache.data and stepCache.data.resolved then return stepCache.data end
	local ok, data = pcall(derive, guide, step, chars)
	if not ok or type(data) ~= "table" then
		data = { rows = {}, upcoming = {}, resolved = false, headline = Guide:StepText(step) }
	end
	stepCache.key, stepCache.data = key, data
	return data
end

function Guide:InvalidateStepFrameCache()
	stepCache.key, stepCache.data = nil, nil
	wipe(placeCache)
end

-- Frame -------------------------------------------------------------------------------------------

local function rowTooltip(self)
	if not self.tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	for _, line in ipairs(self.tip) do GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5]) end
	GameTooltip:Show()
end

local function createRow(parent, onClick)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(14)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)
	row.glyph = makeText(row, "GameFontHighlightSmall", "LEFT")
	row.chip = makeText(row, "GameFontHighlightSmall", "LEFT")
	row.right = makeText(row, "GameFontHighlightSmall", "RIGHT")
	row.main = makeText(row, "GameFontHighlightSmall", "LEFT")
	row.main:SetWordWrap(false)
	row.detail = makeText(row, "GameFontDisableSmall", "LEFT")
	row.detail:SetWordWrap(false)
	row.detail:SetTextColor(0.6, 0.6, 0.6)
	row:SetScript("OnClick", onClick)
	row:SetScript("OnEnter", rowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

--- Position a row's parts for the current width / font scale.
local function layoutRow(row, width, scale, indent)
	local lineH = math.floor(12 * scale + 0.5) + 2
	local glyphW = math.floor(16 * scale + 0.5)
	local chipW = math.floor(46 * scale + 0.5)
	local rightW = math.floor(58 * scale + 0.5)
	row.lineH, row.glyphW, row.chipW, row.rightW = lineH, glyphW, chipW, rightW
	row:SetWidth(width - PAD * 2)
	row.glyph:ClearAllPoints()
	row.glyph:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.glyph:SetWidth(glyphW)
	row.chip:ClearAllPoints()
	row.chip:SetPoint("TOPLEFT", row, "TOPLEFT", glyphW, 0)
	row.chip:SetWidth(chipW)
	row.right:ClearAllPoints()
	row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.right:SetWidth(rightW)
	row.textLeft = indent and (glyphW + chipW) or glyphW
	row.main:ClearAllPoints()
	row.main:SetPoint("TOPLEFT", row, "TOPLEFT", row.textLeft, 0)
	row.main:SetPoint("TOPRIGHT", row, "TOPRIGHT", -rightW - 4, 0)
	row.detail:ClearAllPoints()
	row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", row.textLeft, -lineH)
	row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -lineH)
	for _, fs in ipairs({ row.glyph, row.chip, row.right, row.main, row.detail }) do applyFont(fs, scale) end
end

--- Show a row and return the height it takes.
local function fillRow(row, parts)
	row.glyph:SetText(parts.glyph or "")
	row.chip:SetText(parts.chip or "")
	row.main:SetText(parts.main or "")
	row.right:SetText(parts.right or "")
	row.detail:SetText(parts.detail or "")
	row.tip = parts.tip
	row.onClick = parts.onClick
	row.isHeader = parts.headerRow and true or false
	-- The text column starts after the chip only when there is one.
	local left = parts.chip and parts.chip ~= "" and (row.glyphW + row.chipW) or row.glyphW
	if parts.headerRow then left = 0 end
	row.main:ClearAllPoints()
	row.main:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
	row.main:SetPoint("TOPRIGHT", row, "TOPRIGHT", -row.rightW - 4, 0)
	row.detail:ClearAllPoints()
	row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", left, -row.lineH)
	row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -row.lineH)
	local h = row.lineH + ((parts.detail and parts.detail ~= "") and row.lineH or 0)
	row:SetHeight(h)
	row:Show()
	return h
end

local function hideRow(row)
	row.tip, row.onClick, row.isHeader = nil, nil, nil
	row.glyph:SetText("")
	row.chip:SetText("")
	row.main:SetText("")
	row.right:SetText("")
	row.detail:SetText("")
	row:Hide()
end

local function onRowClick(self)
	if type(self.onClick) ~= "function" then return end
	local ok, err = pcall(self.onClick, self)
	if not ok then Lodestar:Debug("guide row click failed: %s", tostring(err)) end
end

local applyWidth   -- forward declaration: the resize scripts created below call it

local function createFrame()
	frame = CreateFrame("Frame", "LodestarGuideFrame", UIParent, "BackdropTemplate")
	frame:SetSize(DEFAULT_WIDTH, 120)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, MIN_WIDTH, 60, MAX_WIDTH, 2000) end
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.65)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	frame:SetScript("OnDragStart", function(self) if not cfg().locked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Guide:ShowGuideMenu() end
	end)
	-- Live feedback while the grip is dragged; the height snaps back to the content on every refresh.
	frame:SetScript("OnSizeChanged", function(self, w)
		if not self.sizing or self.inResize then return end
		self.inResize = true
		local dragged = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor((tonumber(w) or DEFAULT_WIDTH) + 0.5)))
		if dragged ~= self.uiWidth then
			applyWidth(dragged)
			Guide:RefreshStepFrame()
		end
		self.inResize = nil
	end)

	-- Title bar ------------------------------------------------------------------------------------
	frame.title = makeText(frame, "GameFontNormalSmall", "LEFT")
	frame.title:SetWordWrap(false)
	frame.title:SetTextColor(0.31, 0.76, 0.97)

	frame.prev = makeButton(frame, "<")
	frame.prev:SetScript("OnClick", function() Guide:PrevStep() end)
	frame.next = makeButton(frame, ">")
	frame.next:SetScript("OnClick", function() Guide:NextStep() end)
	for _, b in ipairs({ frame.prev, frame.next }) do
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(Guide:InSmartMode() and "Point the arrow at the previous / next thing in the list" or "Previous / next step", 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	-- Sync: re-read the quest log and jump to the step this character is really at.
	frame.sync = makeButton(frame, "Sync", 40)
	frame.sync:SetScript("OnClick", function() Guide:SyncToQuestLog() end)
	frame.sync:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Sync to your quest log", 1, 1, 1)
		GameTooltip:AddLine("Finds the step after the last one your completed quests account for. Use it any time the guide seems behind or ahead of you.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	frame.sync:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Location bar ---------------------------------------------------------------------------------
	frame.location = makeText(frame, "GameFontHighlightSmall", "LEFT")
	frame.location:SetWordWrap(false)
	frame.location:SetTextColor(0.82, 0.82, 0.86)

	-- Headline -------------------------------------------------------------------------------------
	frame.headline = makeText(frame, "GameFontNormal", "LEFT")
	frame.headline:SetWordWrap(true)
	if frame.headline.SetMaxLines then pcall(frame.headline.SetMaxLines, frame.headline, 2) end
	frame.headline:SetTextColor(1, 1, 1)

	frame.headlineButton = CreateFrame("Button", nil, frame)
	frame.headlineButton:SetScript("OnClick", function() pointArrowAtStep() end)
	frame.headlineButton:SetScript("OnEnter", function(self)
		local step = Guide:CurrentStep()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(Guide.current and Guide.current.name or "Lodestar")
		if step then
			for _, a in ipairs(step.actions) do GameTooltip:AddLine("• " .. Guide:ActionText(a), 1, 1, 1, true) end
			if step.optional then
				GameTooltip:AddLine("Optional" .. (step.optionalReason and (" — " .. step.optionalReason) or "") .. " (completionist mode)", 0.7, 0.7, 0.7, true)
			end
			if step.go then
				GameTooltip:AddLine(("%s %.1f, %.1f"):format(Guide:MapName(step.go.map), step.go.x, step.go.y), 0.7, 0.7, 0.7)
			end
		end
		GameTooltip:AddLine(GREY .. "Click: point the arrow at this step · Right-click: menu|r")
		GameTooltip:Show()
	end)
	frame.headlineButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Banner: trainer suggestion / sync hint / guide finished --------------------------------------
	frame.banner = makeText(frame, "GameFontHighlightSmall", "LEFT")
	frame.banner:SetWordWrap(true)
	frame.banner:SetTextColor(1, 0.84, 0)
	frame.banner:SetHeight(1)

	frame.divider = frame:CreateTexture(nil, "ARTWORK")
	frame.divider:SetColorTexture(1, 1, 1, 0.12)
	frame.divider:SetHeight(1)

	frame.upcomingHeader = makeText(frame, "GameFontDisableSmall", "LEFT")
	frame.upcomingHeader:SetTextColor(0.55, 0.55, 0.55)

	-- Rows ------------------------------------------------------------------------------------------
	for i = 1, MAX_ACTION_ROWS do actionRows[i] = createRow(frame, onRowClick) end
	for i = 1, MAX_UPCOMING do upcomingRows[i] = createRow(frame, onRowClick) end
	frame.actionRows, frame.upcomingRows = actionRows, upcomingRows

	-- Resize grip -----------------------------------------------------------------------------------
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		if cfg().locked then return end
		frame.sizing = true
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		if not frame.sizing then return end
		frame.sizing = nil
		frame:StopMovingOrSizing()
		Guide:SetStepFrameWidth(frame:GetWidth())
		savePosition()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Drag to resize", 1, 1, 1)
		GameTooltip:AddLine(("Width %d (%d–%d). The height follows the content."):format(frameWidth(), MIN_WIDTH, MAX_WIDTH), 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.grip = grip
end

--- Apply a width: chrome positions, font sizes and row geometry. Height stays content-driven.
function applyWidth(width)
	if not frame then return end
	local scale = math.max(0.85, math.min(1.25, width / DEFAULT_WIDTH))
	frame.uiWidth, frame.uiScale = width, scale
	frame:SetWidth(width)
	frame.title:ClearAllPoints()
	frame.title:SetPoint("TOPLEFT", PAD, -8)
	frame.next:ClearAllPoints()
	frame.next:SetPoint("TOPRIGHT", -8, -5)
	frame.prev:ClearAllPoints()
	frame.prev:SetPoint("TOPRIGHT", -36, -5)
	frame.sync:ClearAllPoints()
	frame.sync:SetPoint("TOPRIGHT", -64, -5)
	for _, fs in ipairs({ frame.location, frame.headline, frame.banner, frame.upcomingHeader }) do
		fs:SetWidth(width - PAD * 2)
		applyFont(fs, scale)
	end
	frame.title:SetWidth(math.max(40, width - PAD * 2 - TITLE_BUTTONS))
	applyFont(frame.title, scale)
	for _, row in ipairs(actionRows) do layoutRow(row, width, scale, true) end
	for _, row in ipairs(upcomingRows) do layoutRow(row, width, scale, false) end
	frame.divider:ClearAllPoints()
	frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, 0)
	frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, 0)
end

--- The window width, clamped and saved; re-lays out and refreshes.
function Guide:SetStepFrameWidth(width)
	local w = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor((tonumber(width) or DEFAULT_WIDTH) + 0.5)))
	cfg().width = w
	if frame then
		applyWidth(w)
		self:RefreshStepFrame()
	end
	return w
end

function Guide:GetStepFrameWidth() return frameWidth() end

-- Banners ------------------------------------------------------------------------------------------

--- Set the banner text (or clear it) and return the height it takes.
local function setBanner(text)
	if text then
		frame.banner:SetText(text)
		local h = (frame.banner:GetStringHeight() or 12) + 4
		frame.banner:SetHeight(h)
		return h
	end
	frame.banner:SetText("")
	frame.banner:SetHeight(1)
	return 1
end

--- Guided mode banner: the class trainer suggestion, when there is one.
local function trainerBanner()
	local t = Guide:TrainerSuggestion()
	if not t then return nil end
	return (GOLD .. "New spells available|r — %s is %d yd away"):format(t.name or "your class trainer", math.floor(t.dist or 0))
end

--- "Your quest log says you're further along" hint, recomputed at most every 5 s.
local syncHint = { at = 0 }
local function syncBanner(guide, stepIndex)
	local now = GetTime()
	if now - syncHint.at > 5 or syncHint.guide ~= guide or syncHint.step ~= stepIndex then
		syncHint.at, syncHint.guide, syncHint.step = now, guide, stepIndex
		local start, _, open = Guide:SuggestStartIndex(guide)
		syncHint.start, syncHint.open = start, open
	end
	if syncHint.start and syncHint.start > stepIndex + 1 then
		return (GREEN .. "You look further along|r — quest log points at step %d. Click Sync."):format(syncHint.start)
	end
	if syncHint.open and syncHint.open > 0 and syncHint.start and syncHint.start <= stepIndex then
		return (GREY .. "%d earlier step%s still open (press <)|r"):format(syncHint.open, syncHint.open == 1 and "" or "s")
	end
	return nil
end

-- Rendering ----------------------------------------------------------------------------------------

--- One action row: state glyph, verb chip, quest name with its level, live detail line.
local function renderAction(row, entry, flags, chars, stepIndex)
	local a = entry.action
	local done = false
	local okDone, isDone = pcall(Guide.IsActionComplete, Guide, a, flags)
	if okDone then done = isDone and true or false end
	local main, right, detail
	if entry.questID then
		main = questLabel(entry.questID, entry.level, chars)
		detail = entry.detail
		if a.type == "complete" then
			local text, finished = objectiveProgress(a)
			if text then detail = (finished and GREEN or WHITE) .. text .. "|r" end
		end
	elseif entry.itemID then
		local have = 0
		if C_Item and C_Item.GetItemCount then
			local okCount, n = pcall(C_Item.GetItemCount, entry.itemID, true)
			if okCount and type(n) == "number" then have = n end
		end
		main = WHITE .. trim(entry.title, chars) .. "|r"
		right = ("%s%d/%d|r"):format(have >= entry.need and GREEN or GREY, have, entry.need)
		detail = entry.detail
	else
		main = WHITE .. trim(entry.title or "", chars) .. "|r"
	end
	local tip = { { entry.title or "", 1, 1, 1 } }
	if entry.level then tinsert(tip, { "Level " .. entry.level, 0.8, 0.8, 0.8 }) end
	if a.text then tinsert(tip, { a.text, 0.8, 0.8, 0.8, true }) end
	if a.type == "complete" then
		local text = objectiveProgress(a)
		if text then tinsert(tip, { text, 1, 1, 1, true }) end
	end
	tinsert(tip, { done and (GREEN .. "Done|r") or (DIM .. "Not done yet|r") })
	tinsert(tip, { GREY .. (entry.mapID and "Click: point the arrow at this" or "Click: point the arrow at this step") .. "|r" })
	return fillRow(row, {
		glyph = done and DONE_GLYPH or TODO_GLYPH,
		chip = entry.color .. entry.verb .. "|r",
		main = main, right = right, detail = detail and trim(detail, math.floor(chars * 1.4)) or nil,
		tip = tip,
		onClick = function()
			if entry.mapID and pointArrowAt(entry.mapID, entry.x, entry.y, stepIndex) then return end
			pointArrowAtStep()
		end,
	})
end

--- Guided mode.
local function refreshGuided(guide, step)
	local width = frame.uiWidth or frameWidth()
	local scale = frame.uiScale or 1
	local chars = fitChars(width - PAD * 2 - 120, scale)
	if frame.sync then frame.sync:Show() end
	if focus and focus.step ~= step.index then releaseFocus() end

	local title = trim(guide.name or "Guide", fitChars(width - PAD * 2 - TITLE_BUTTONS - 44, scale))
	frame.title:SetText(("%s  %s%d/%d%s|r"):format(title, GREY, step.index, #guide.steps, Guide.finished and " · done" or ""))

	local data = stepData(guide, step, chars)
	frame.location:SetText(locationLine(data.mapID, data.x, data.y, true))
	frame.headline:SetText(data.headline .. (step.optional and OPTIONAL_TAG or ""))

	local flags = Guide.stepFlags[step.index]
	local shown, rowsHeight = 0, 0
	-- A step with more actions than there are rows keeps the last row for "+N more".
	local limit = (#data.rows > MAX_ACTION_ROWS) and (MAX_ACTION_ROWS - 1) or MAX_ACTION_ROWS
	for i = 1, MAX_ACTION_ROWS do
		local row = actionRows[i]
		local entry = (i <= limit) and data.rows[i] or nil
		if entry then
			local ok, h = pcall(renderAction, row, entry, flags, chars, step.index)
			if ok then
				rowsHeight = rowsHeight + (h or 0)
			else
				rowsHeight = rowsHeight + fillRow(row, { glyph = TODO_GLYPH, main = DIM .. "(could not draw this action)|r" })
			end
			shown = shown + 1
		elseif i > limit and #data.rows > limit then
			rowsHeight = rowsHeight + fillRow(row, { main = (DIM .. "+%d more in this step|r"):format(#data.rows - limit) })
			shown = shown + 1
			break
		else
			hideRow(row)
		end
	end
	if shown == 0 and step.go then
		rowsHeight = rowsHeight + fillRow(actionRows[1], {
			glyph = TODO_GLYPH, chip = BLUE .. "Reach|r", main = WHITE .. trim(data.headline, chars) .. "|r",
			tip = { { data.headline, 1, 1, 1 }, { GREY .. "Click: point the arrow here|r" } },
			onClick = function() pointArrowAtStep() end,
		})
	end

	local banner = trainerBanner() or syncBanner(guide, step.index)
	if Guide.finished then
		banner = GREEN .. "Guide finished|r — > for smart mode, right-click for other guides"
	elseif step.optional and step.optionalReason then
		banner = banner or (DIM .. "Optional — " .. step.optionalReason .. "|r")
	end
	local bannerH = setBanner(banner)

	-- Coming up
	local want = math.min(Guide.db.profile.steps.upcoming or 3, MAX_UPCOMING)
	local upcomingShown, upcomingHeight = 0, 0
	for i = 1, MAX_UPCOMING do
		local row = upcomingRows[i]
		local entry = i <= want and data.upcoming[i] or nil
		if entry then
			local ok, h = pcall(fillRow, row, {
				main = GREY .. trim(entry.text, math.floor(chars * 1.5)) .. "|r",
				tip = { { entry.text, 1, 1, 1, true }, { GREY .. "Click: jump to this step|r" } },
				onClick = function() Guide:SetStep(entry.index) Guide:EvaluateStep() end,
			})
			if ok then
				upcomingHeight = upcomingHeight + (h or 0)
				upcomingShown = upcomingShown + 1
			else
				hideRow(row)
			end
		else
			hideRow(row)
		end
	end
	return rowsHeight, bannerH, upcomingShown, upcomingHeight
end

--- Smart mode: the "next up" list built from the quest log and the map, grouped by kind.
local function refreshSmart()
	local width = frame.uiWidth or frameWidth()
	local scale = frame.uiScale or 1
	local chars = fitChars(width - PAD * 2 - 120, scale)
	if frame.sync then frame.sync:Hide() end
	if focus then releaseFocus() end
	frame.title:SetText("Lodestar  " .. GREY .. "smart mode|r")

	local items = Guide:CollectSmartItems()
	local pinnedItem = Guide:GetPinnedSmartItem()
	local lead
	if pinnedItem then
		for _, it in ipairs(items) do
			if it.kind == pinnedItem.kind and it.questID == pinnedItem.questID and it.x == pinnedItem.x then lead = it end
		end
	end
	lead = lead or items[1]

	if lead then
		frame.headline:SetText(("%s%s|r %s"):format(KIND_COLOR[lead.kind] or WHITE, KIND_LABEL[lead.kind] or "Next", trim(lead.title or "", chars * 2)))
		if lead.mapID and lead.x and lead.y then
			frame.location:SetText(locationLine(lead.mapID, lead.x, lead.y, false))
		else
			frame.location:SetText((lead.subtitle and trim(lead.subtitle, chars) or "") .. "   " .. DIM .. "location unknown|r")
		end
	else
		frame.headline:SetText("Nothing to do here yet. Pick up quests at the nearest hub, or /lode record start and play.")
		frame.location:SetText("")
	end

	-- group the rest by kind, keeping the distance order inside each group
	local grouped = {}
	for _, it in ipairs(items) do
		if it ~= lead then
			grouped[it.kind] = grouped[it.kind] or {}
			tinsert(grouped[it.kind], it)
		end
	end
	local used, rowsHeight = 0, 0
	local function row()
		used = used + 1
		return actionRows[used]
	end
	for _, kind in ipairs(KIND_ORDER) do
		local list = grouped[kind]
		if list and #list > 0 and used < MAX_ACTION_ROWS - 1 then
			rowsHeight = rowsHeight + fillRow(row(), { headerRow = true, main = (KIND_COLOR[kind] or GREY) .. (KIND_LABEL[kind] or kind) .. "|r" })
			for _, it in ipairs(list) do
				if used >= MAX_ACTION_ROWS then break end
				local item = it
				local main
				if kind == "available" and item.questID then
					-- "what are we picking up": the quest level, coloured by how hard it is for this character
					main = questLabel(item.questID, item.level or questLevel(item.questID), chars, item.title)
				else
					main = ((kind == "available") and GOLD or WHITE) .. trim(item.title or "", chars) .. "|r"
				end
				-- the level is already on the row, so drop the "· lvl N" the list builders append
				local subtitle = item.subtitle and (item.subtitle:gsub("%s*·%s*lvl%s*%d+%s*$", "")) or nil
				local ok, h = pcall(fillRow, row(), {
					glyph = "",
					main = main,
					right = item.dist and (GREY .. math.floor(item.dist) .. " yd|r") or (item.noPosition and (DIM .. "?|r") or nil),
					detail = subtitle and trim(subtitle, math.floor(chars * 1.4)) or nil,
					tip = { { item.title or "", 1, 1, 1 }, { item.subtitle or "", 0.8, 0.8, 0.8, true }, { GREY .. "Click: point the arrow at this|r" } },
					onClick = function() Guide:PinSmartItem(item) end,
				})
				if ok then rowsHeight = rowsHeight + (h or 0) else hideRow(actionRows[used]) end
			end
		end
	end
	for i = used + 1, MAX_ACTION_ROWS do hideRow(actionRows[i]) end
	for i = 1, MAX_UPCOMING do hideRow(upcomingRows[i]) end
	return rowsHeight, setBanner(nil)
end

--- Stack everything vertically and size the frame to its content.
local function place(rowsHeight, bannerH, upcomingShown, upcomingHeight)
	local y = 8 + 20 + 2                                     -- title bar
	frame.location:ClearAllPoints()
	frame.location:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + (frame.location:GetStringHeight() or 12) + 4
	frame.headline:ClearAllPoints()
	frame.headline:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.headlineButton:ClearAllPoints()
	frame.headlineButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 2, -y + 2)
	local headlineH = (frame.headline:GetStringHeight() or 12) + 4
	frame.headlineButton:SetSize(math.max(20, (frame.uiWidth or DEFAULT_WIDTH) - PAD * 2), headlineH)
	y = y + headlineH
	if rowsHeight > 0 then
		y = y + 2
		local rowY = y
		for _, row in ipairs(actionRows) do
			if row:IsShown() then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -rowY)
				rowY = rowY + (row:GetHeight() or 14)
			end
		end
		y = rowY + 2
	end
	if bannerH and bannerH > 1 then
		frame.banner:ClearAllPoints()
		frame.banner:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		y = y + bannerH
	else
		frame.banner:ClearAllPoints()
		frame.banner:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	end
	if (upcomingShown or 0) > 0 then
		y = y + 4
		frame.divider:ClearAllPoints()
		frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
		frame.divider:Show()
		y = y + 5
		frame.upcomingHeader:Show()
		frame.upcomingHeader:ClearAllPoints()
		frame.upcomingHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		frame.upcomingHeader:SetText("Coming up")
		y = y + (frame.upcomingHeader:GetStringHeight() or 12) + 3
		local rowY = y
		for _, row in ipairs(upcomingRows) do
			if row:IsShown() then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -rowY)
				rowY = rowY + (row:GetHeight() or 14)
			end
		end
		y = rowY
	else
		frame.divider:Hide()
		frame.upcomingHeader:Hide()
		frame.upcomingHeader:SetText("")
	end
	frame:SetHeight(math.max(70, y + 10))
end

function Guide:RefreshStepFrame()
	if not frame or not frame:IsShown() then return end
	if not frame.uiWidth then applyWidth(frameWidth()) end
	local guide, step = self.current, self:CurrentStep()
	if not guide or not step then
		local ok, rowsHeight, bannerH = pcall(refreshSmart)
		if ok then place(rowsHeight or 0, bannerH or 1, 0, 0) end
		return
	end
	local ok, rowsHeight, bannerH, upcomingShown, upcomingHeight = pcall(refreshGuided, guide, step)
	if ok then place(rowsHeight or 0, bannerH or 1, upcomingShown or 0, upcomingHeight or 0) end
end

function Guide:UpdateStepFrame()
	if not frame then return end
	local c = cfg()
	if not self:IsEnabled() or not c.show then
		frame:Hide()
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(c.pos.point or "TOPRIGHT", UIParent, c.pos.point or "TOPRIGHT", c.pos.x or -40, c.pos.y or -200)
	frame:SetScale(c.scale or 1)
	frame:SetBackdropBorderColor(c.locked and 0.4 or 0.3, c.locked and 0.4 or 0.75, c.locked and 0.4 or 1, 0.9)
	applyWidth(frameWidth())
	frame:Show()
	self:RefreshStepFrame()
end

function Guide:ShowGuideMenu()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then self:OpenSettings() return end
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Lodestar Guide")
		local applicable = self:ApplicableGuides(true)
		local level = UnitLevel("player")
		if #applicable == 0 then
			root:CreateButton(DIM .. "No guides for this character|r", function() end)
		end
		for _, g in ipairs(applicable) do
			local outleveled = g.maxLevel and level > g.maxLevel
			local label = g.name .. (g.minLevel and (" (" .. g.minLevel .. "-" .. g.maxLevel .. ")") or "")
			if outleveled then label = DIM .. label .. " · outleveled|r" end
			root:CreateRadio(label,
				function() return self.current and self.current.name == g.name end,
				function() self:LoadGuide(g.name) end)
		end
		root:CreateRadio("Smart mode (no guide) — nearest turn-ins, objectives and pick-ups", function() return self.current == nil end, function() self:UnloadGuide() end)
		root:CreateDivider()
		if self.current then
			root:CreateButton("Next step", function() self:NextStep() end)
			root:CreateButton("Previous step", function() self:PrevStep() end)
			root:CreateButton("Restart this guide", function() self:LoadGuide(self.current.name, 1) end)
		else
			root:CreateButton("Point at the next thing in the list", function() self:NextStep() end)
			root:CreateButton("Point at the previous thing", function() self:PrevStep() end)
			root:CreateButton("Print the list to chat", function() self:PrintNextUp() end)
		end
		root:CreateDivider()
		local widthMenu = root:CreateButton("Width")
		if widthMenu and widthMenu.CreateRadio then
			for _, px in ipairs(WIDTH_PRESETS) do
				widthMenu:CreateRadio(tostring(px) .. (px == DEFAULT_WIDTH and " (default)" or ""),
					function() return frameWidth() == px end,
					function() self:SetStepFrameWidth(px) end)
			end
		end
		root:CreateCheckbox("Locked", function() return self.db.profile.steps.locked end,
			function() self.db.profile.steps.locked = not self.db.profile.steps.locked self:UpdateStepFrame() end)
		root:CreateCheckbox("Auto-advance", function() return self.db.profile.steps.autoAdvance end,
			function() self.db.profile.steps.autoAdvance = not self.db.profile.steps.autoAdvance end)
		root:CreateCheckbox("Completionist (do optional quests)", function() return self.db.profile.steps.completionist end,
			function() self:SetCompletionist(not self.db.profile.steps.completionist) end)
		root:CreateButton("Hide window", function() self.db.profile.steps.show = false self:UpdateStepFrame() end)
		root:CreateButton("Settings", function() self:OpenSettings() end)
	end)
end

function Guide:EnableStepFrame()
	if not frame then createFrame() end
	self:UpdateStepFrame()
	self.stepFrameTicker = self:ScheduleRepeatingTimer("RefreshStepFrame", 2)
end

function Guide:DisableStepFrame()
	if self.stepFrameTicker then self:CancelTimer(self.stepFrameTicker) self.stepFrameTicker = nil end
	if frame then frame:Hide() end
end

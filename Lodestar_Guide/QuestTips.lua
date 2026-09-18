-- Lodestar_Guide: quest relevance on tooltips — what a mob, quest giver, object or item means for the
-- quests in your log and the ones you could pick up (the Questie tooltip, fed by the Vanilla database
-- and the harvest).
--
--   units    "Rattling the Rattlecages  Rattlecage Skeleton slain: 3/8"   objective mob, or drop source of
--            an objective item (green once that objective is done)
--            "Turn in: <title>"        green when the quest in the log is complete
--            "Turn in later: <title>"  grey when it is not
--            "Starts: <title> (lvl 3)" quests this character can take from the NPC; "(new)" = seen by the
--                                      harvest only (Forever quests the Vanilla data does not know)
--            "Vendor · Repair"         roles the harvest has seen for the NPC, small grey
--   objects  the same lines by GameObject id: Enum.TooltipDataType.Object exists on this client and the
--            world-cursor tooltip data carries the object's GUID
--   items    "<title> — 3/6" for quest objective items, "Starts a quest: <title>" for quest starters
--
-- The NPC id comes from the GUID in the tooltip data (the same field TooltipUtil.GetDisplayedUnit reads),
-- so no unit token is needed and secret values are dropped rather than compared.
-- Blizzard's own tooltip prints objective progress for mobs it links to active quests (QuestTitle /
-- QuestObjective lines); quests it already lists are skipped so nothing shows twice.
-- Results are cached per entity for 2 s and dropped on quest-log events; the reverse index over the
-- Vanilla data (npc/object/item -> quests) is built once, lazily, on the first tooltip.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local CACHE_TTL = 2
local MAX_QUEST_LINES, MAX_START_LINES = 4, 3
local TRIVIAL_BELOW = 6                       -- harvest-only quests this many levels under the player are skipped
local GOLD, GREEN, GREY = "|cffffd700", "|cff7fff7f", "|cff9d9d9d"
local ROLES = { { "trainer", "Trainer" }, { "vendor", "Vendor" }, { "repair", "Repair" }, { "inn", "Innkeeper" }, { "taxi", "Flight master" } }

local hooked, hookPending, active = false, false, false
local index                                   -- reverse index over the Vanilla data (built lazily)
local cache = {}                              -- ["npcs:1890"] = { at = GetTime(), lines = { { text, r, g, b, small } } }

local function cfg() return Guide.db.profile.questTips end
local function data() return Guide.VanillaData end

local function plain(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Reverse index --------------------------------------------------------------------------------------------
-- index[kind][id] = { obj = { { questID, objectiveIndex, nameInObjectiveText }, ... }, ends = { questID, ... } }
-- Objective indices follow the data order npcs, items, objs, areas (tools/router/vanilla_catalog.py);
-- the name is what the client's objective text should contain, used to confirm or correct the index.

local function entry(kind, id)
	local store = index[kind]
	local e = store[id]
	if not e then
		e = {}
		store[id] = e
	end
	return e
end

local function addObjective(kind, id, qid, idx, name)
	local e = entry(kind, id)
	e.obj = e.obj or {}
	tinsert(e.obj, { qid, idx, name })
end

local function addEnder(kind, id, qid)
	local e = entry(kind, id)
	e.ends = e.ends or {}
	tinsert(e.ends, qid)
end

local function buildIndex()
	index = { npcs = {}, objs = {}, items = {} }
	local d = data()
	if not d then return end
	for qid, q in pairs(d.quests) do
		local o = q.obj
		if o then
			local i = 0
			for _, id in ipairs(o.npcs or {}) do
				i = i + 1
				local n = d.npcs[id]
				addObjective("npcs", id, qid, i, n and n.n)
			end
			for _, itemID in ipairs(o.items or {}) do
				i = i + 1
				local it = d.items[itemID]
				local name = it and it.n
				addObjective("items", itemID, qid, i, name)
				if it then
					for _, src in ipairs(it.npcs or {}) do addObjective("npcs", src[1], qid, i, name) end
					for _, src in ipairs(it.objs or {}) do addObjective("objs", src[1], qid, i, name) end
				end
			end
			for _, id in ipairs(o.objs or {}) do
				i = i + 1
				local ob = d.objs[id]
				addObjective("objs", id, qid, i, ob and ob.n)
			end
		end
		local e = q["end"]
		if e then
			for _, id in ipairs(e.npcs or {}) do addEnder("npcs", id, qid) end
			for _, id in ipairs(e.objs or {}) do addEnder("objs", id, qid) end
		end
	end
end

-- Quest log helpers ------------------------------------------------------------------------------------------

local function questLogEmpty()
	local n, numQuests = C_QuestLog.GetNumQuestLogEntries()
	return (tonumber(numQuests) or tonumber(n) or 0) == 0
end

local function questTitle(qid)
	local title = plain(C_QuestLog.GetTitleForQuestID(qid))
	if type(title) == "string" and title ~= "" then return title end
	local d = data()
	local q = d and d.quests[qid]
	if q and q.t then return q.t end
	local H = Guide.HarvestDB and Guide:HarvestDB()
	local hq = H and H.quests[qid]
	return (hq and hq.t) or ("Quest " .. qid)
end

--- The objective of a quest that `name` (mob / item / object) belongs to: the data's index when the
--- client's text agrees (or nothing disagrees), any objective naming it otherwise, else the first
--- unfinished one.
local function objectiveFor(qid, idx, name)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, qid)
	if not ok or type(objectives) ~= "table" or #objectives == 0 then return nil end
	local o = objectives[idx]
	if name then
		local text = o and plain(o.text)
		if type(text) == "string" and text:find(name, 1, true) then return o end
		for _, cand in ipairs(objectives) do
			text = plain(cand.text)
			if type(text) == "string" and text:find(name, 1, true) then return cand end
		end
	end
	if o then return o end
	for _, cand in ipairs(objectives) do if not cand.finished then return cand end end
	return objectives[1]
end

local function objectiveCounts(o)
	if not o then return nil end
	local have, need = tonumber(plain(o.numFulfilled)), tonumber(plain(o.numRequired))
	if have and need and need > 0 then return have, need end
	local text = plain(o.text)
	if type(text) == "string" then
		local a, b = text:match("(%d+)%s*/%s*(%d+)")
		if a then return tonumber(a), tonumber(b) end
	end
	return nil
end

local function objectiveText(o)
	if not o then return nil end
	local text = plain(o.text)
	if type(text) == "string" and text ~= "" then return text end
	local have, need = objectiveCounts(o)
	if have then return have .. "/" .. need end
	return nil
end

--- Titles of the quests Blizzard's own tooltip already lists for this unit (QuestTitle lines).
local function blizzardQuestTitles(tooltipData)
	local LT = Enum.TooltipDataLineType
	local lines = tooltipData and tooltipData.lines
	if not (LT and LT.QuestTitle and type(lines) == "table") then return nil end
	local titles
	for _, l in ipairs(lines) do
		if l.type == LT.QuestTitle then
			local text = plain(l.leftText)
			if type(text) == "string" and text ~= "" then
				titles = titles or {}
				titles[text] = true
			end
		end
	end
	return titles
end

-- Lines --------------------------------------------------------------------------------------------------------

local function line(lines, text, r, g, b, small)
	tinsert(lines, { text, r or 1, g or 1, b or 1, small })
end

--- Objective lines for one entity: "<title>  <objective text>", green once that objective is finished.
local function objectiveLines(lines, e, blizzTitles, itemStyle)
	local shown, nQuests = {}, 0
	for _, ob in ipairs(e and e.obj or {}) do
		local qid, idx, name = ob[1], ob[2], ob[3]
		if nQuests >= MAX_QUEST_LINES then break end
		if C_QuestLog.IsOnQuest(qid) and (itemStyle or not C_QuestLog.IsComplete(qid)) then
			local title = questTitle(qid)
			local key = qid .. ":" .. idx
			if not shown[key] and not (blizzTitles and blizzTitles[title]) then
				if not shown[qid] then nQuests = nQuests + 1 end
				shown[key], shown[qid] = true, true
				local o = objectiveFor(qid, idx, name)
				local text
				if itemStyle then
					local have, need = objectiveCounts(o)
					text = have and (have .. "/" .. need) or objectiveText(o) or "quest item"
				else
					text = objectiveText(o) or "objective"
				end
				local sep = itemStyle and " — " or "  "
				if o and o.finished then
					line(lines, GREEN .. title .. sep .. text .. "|r")
				else
					line(lines, GOLD .. title .. "|r" .. sep .. text)
				end
			end
		end
	end
end

--- "Turn in" lines from the data's enders plus the harvest's.
local function turnInLines(lines, e, harvestEntry)
	local enders, list = {}, {}
	for _, qid in ipairs(e and e.ends or {}) do enders[qid] = true end
	for qid in pairs(harvestEntry and harvestEntry.ends or {}) do enders[qid] = true end
	for qid in pairs(enders) do
		if C_QuestLog.IsOnQuest(qid) then tinsert(list, qid) end
	end
	table.sort(list)
	for _, qid in ipairs(list) do
		if C_QuestLog.IsComplete(qid) then
			line(lines, GREEN .. "Turn in: " .. questTitle(qid) .. "|r")
		else
			line(lines, GREY .. "Turn in later: " .. questTitle(qid) .. "|r")
		end
	end
end

local function levelSuffix(level)
	if level and cfg().showLevel then return " (lvl " .. level .. ")" end
	return ""
end

--- True when the data itself starts `qid` at this exact giver, i.e. DataAvailableFrom already
--- considered it (and may have filtered it out on level, race, class or prerequisites, deliberately).
--- Knowing the quest is not enough: the Forever overlay ships titles and levels for quests whose
--- giver it never recorded, and those land in `d.quests` with no `start` at all.
local function dataStartsHere(d, qid, kind, id)
	local q = d and d.quests[qid]
	local s = q and q.start
	for _, sid in ipairs(s and s[kind] or {}) do
		if sid == id then return true end
	end
	return false
end

--- "Starts:" lines: the Vanilla data's quest givers filtered like the pick-up list, then quests the
--- harvest saw this NPC offer that the data does not start here ("(new)").
local function startLines(lines, kind, id, harvestEntry, label)
	local n = 0
	for _, s in ipairs(Guide:DataAvailableFrom(kind, id)) do
		if n >= MAX_START_LINES then break end
		n = n + 1
		line(lines, GOLD .. label .. s.title .. levelSuffix(s.level) .. "|r")
	end
	if not (harvestEntry and harvestEntry.gives) then return end
	local d = data()
	local H = Guide:HarvestDB()
	local level = UnitLevel("player")
	local extra = {}
	for qid in pairs(harvestEntry.gives) do
		if not dataStartsHere(d, qid, kind, id) and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid) then
			local hq = H.quests[qid]
			local dq = d and d.quests[qid]
			-- `done` is account-wide and says nothing about this character; the flag check above is
			-- what decides eligibility. The level falls back to the overlay, which is where the
			-- levels for these quests actually live.
			local lvl = (hq and hq.lvl) or (dq and dq.lvl)
			local trivial = lvl and (level - lvl) >= TRIVIAL_BELOW
			if not trivial then tinsert(extra, qid) end
		end
	end
	table.sort(extra)
	for _, qid in ipairs(extra) do
		if n >= MAX_START_LINES then break end
		n = n + 1
		local hq = H.quests[qid]
		local dq = d and d.quests[qid]
		line(lines, GOLD .. label .. questTitle(qid) .. levelSuffix((hq and hq.lvl) or (dq and dq.lvl)) .. " (new)|r")
	end
end

local function roleLine(lines, harvestEntry)
	local kinds = harvestEntry and harvestEntry.kind
	if type(kinds) ~= "table" then return end
	local parts = {}
	for _, role in ipairs(ROLES) do
		if kinds[role[1]] then tinsert(parts, role[2]) end
	end
	if #parts > 0 then line(lines, table.concat(parts, " · "), 0.6, 0.6, 0.6, true) end
end

--- Everything to say about a creature (kind "npcs") or a game object (kind "objs").
local function entityLines(kind, id, tooltipData)
	if not index then buildIndex() end
	local lines = {}
	local e = index and index[kind][id]
	local H = Guide:HarvestDB()
	local harvestEntry = (kind == "objs" and H.objects or H.npcs)[id]
	if not questLogEmpty() then
		objectiveLines(lines, e, blizzardQuestTitles(tooltipData), false)
		turnInLines(lines, e, harvestEntry)
	end
	startLines(lines, kind, id, harvestEntry, "Starts: ")
	if kind == "npcs" then roleLine(lines, harvestEntry) end
	return lines
end

local function itemLines(itemID)
	if not index then buildIndex() end
	local lines = {}
	local e = index and index.items[itemID]
	if not questLogEmpty() then objectiveLines(lines, e, nil, true) end
	startLines(lines, "items", itemID, nil, "Starts a quest: ")
	return lines
end

-- Cache and rendering --------------------------------------------------------------------------------------------

local function cachedLines(key, build)
	local now = GetTime()
	local hit = cache[key]
	if hit and now - hit.at < CACHE_TTL then return hit.lines, true end
	local lines = build()
	cache[key] = { at = now, lines = lines }
	return lines, false
end

local function shrinkLastLine(tooltip)
	local name = tooltip.GetName and tooltip:GetName()
	local n = name and tooltip.NumLines and tooltip:NumLines()
	local fs = n and rawget(_G, name .. "TextLeft" .. n)
	local font = rawget(_G, "GameTooltipTextSmall")
	if fs and font and fs.SetFontObject then fs:SetFontObject(font) end
end

local function render(tooltip, lines)
	for _, l in ipairs(lines) do
		tooltip:AddLine(l[1], l[2], l[3], l[4])
		if l[5] then shrinkLastLine(tooltip) end
	end
end

--- "npcs"/"objs" and the id from a Creature / Vehicle / GameObject GUID (players, pets: nil).
local function guidKind(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	id = tonumber(id)
	if not id then return nil end
	if kind == "Creature" or kind == "Vehicle" then return "npcs", id end
	if kind == "GameObject" then return "objs", id end
	return nil
end

local function displayedGUID(tooltip, tooltipData)
	local guid = tooltipData and plain(tooltipData.guid)
	if type(guid) ~= "string" and TooltipUtil and TooltipUtil.GetDisplayedUnit then
		local _, _, g = TooltipUtil.GetDisplayedUnit(tooltip)
		guid = plain(g)
	end
	return type(guid) == "string" and guid or nil
end

local function decorateEntity(tooltip, tooltipData, want)
	local kind, id = guidKind(displayedGUID(tooltip, tooltipData))
	if kind ~= want then return end
	local lines = cachedLines(kind .. ":" .. id, function() return entityLines(kind, id, tooltipData) end)
	render(tooltip, lines)
end

local function decorateItem(tooltip, tooltipData)
	local itemID = tooltipData and plain(tooltipData.id)
	if type(itemID) ~= "number" and TooltipUtil and TooltipUtil.GetDisplayedItem then
		local _, _, id = TooltipUtil.GetDisplayedItem(tooltip)
		itemID = plain(id)
	end
	if type(itemID) ~= "number" then return end
	local lines = cachedLines("items:" .. itemID, function() return itemLines(itemID) end)
	render(tooltip, lines)
end

-- Hooks ------------------------------------------------------------------------------------------------------------

local function onUnitTooltip(tooltip, tooltipData)
	if not active or not cfg().units or tooltip ~= GameTooltip then return end
	local ok, err = pcall(decorateEntity, tooltip, tooltipData, "npcs")
	if not ok then Lodestar:Debug("quest tips (unit): %s", tostring(err)) end
end

local function onObjectTooltip(tooltip, tooltipData)
	if not active or not cfg().objects or tooltip ~= GameTooltip then return end
	local ok, err = pcall(decorateEntity, tooltip, tooltipData, "objs")
	if not ok then Lodestar:Debug("quest tips (object): %s", tostring(err)) end
end

local function onItemTooltip(tooltip, tooltipData)
	if not active or not cfg().items then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local ok, err = pcall(decorateItem, tooltip, tooltipData)
	if not ok then Lodestar:Debug("quest tips (item): %s", tostring(err)) end
end

function Guide:QuestTipsOnEvent(event)
	if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED"
		or event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
		wipe(cache)
	end
end

local function hook()
	hookPending = false
	if hooked then return end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then
		Lodestar:Debug("TooltipDataProcessor unavailable; quest tooltips disabled")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
	if Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, onObjectTooltip)
	end
	hooked = true
end

function Guide:EnableQuestTips()
	active = true
	wipe(cache)
	if hooked or hookPending then return end
	-- Post-calls run in registration order and the modules enable in load order (Guide before UI), so
	-- register one tick later: the other modules' lines (ids, item level, prices) come first, ours after.
	hookPending = true
	self:ScheduleTimer(hook, 0)
end

function Guide:DisableQuestTips()
	-- Post-calls cannot be removed; the callbacks check `active`.
	active = false
	wipe(cache)
end

-- Lodestar_Guide: the harvest — everything the client tells us about the world.
--
-- Forever exposes no quest POIs to addons, so every position the guide can point at comes either from
-- the imported Vanilla database or from here. The beta census found ~640 quests with no Vanilla
-- counterpart at all; this file is the data engine that fills them in, and its output is meant to be
-- handed to other people, so it lives in its own saved variable:
--
--   LodestarShareDB   world knowledge worth sending to another player — and the only thing
--                     `/lode share` talks about:
--       npcs     [npcID]  = { name, seen, map, x, y, exact, zone, subzone, samples = { {map,x,y,zone,sub} },
--                            minL, maxL, cls, react, ctype, kind = { quest/vendor/repair/trainer/tradeskill/taxi/inn },
--                            gives = { [questID] = true }, ends = { … }, sells = { [itemID] = true },
--                            trains = "<CLASS>", taxiNode, objGuess = { [questID] = ticks }, via = "comm" }
--       objects  [objID]  = same shape, without the creature-only fields
--       quests   [questID]= { t, lvl, group, tag, cls, freq, rep, req, o, races, classes, giver, ender,
--                            src, item, acceptAt, turninAt, prog = { [i] = { {map,x,y,zone,sub} … } },
--                            wp / turninWp = {map,x,y} (the client's own waypoint for the next
--                            objective and, once complete, for the turn-in; see sweepWaypoints),
--                            fin = { [i] = {map,x,y,zone,sub} }, xp = { level, xp }, money, done, scanned, via }
--       taxi     [nodeID] = { name, map, x, y, zone, subzone, state, npc, links = { [nodeID] = true } }
--       levels   [level]  = UnitXPMax at that level
--       meta              = { v, build, contributors = { ["Name-Realm"] = { faction, race, class, level,
--                                                                           first, last, sessions } } }
--   (the backup slot lives in LodestarScanDB, not here, so it never travels with a shared file)
--
--   LodestarScanDB    per-account bookkeeping nobody else needs:
--       trails            learned walkable ground (Trails.lua)
--       scan              the `/lode scan quests` census cursor
--       migrated          when the world data was moved out of here into LodestarShareDB
--
-- Positions are the player's own position at the moment of the event, so an NPC you talked to is
-- placed within interaction range (~5 yd) and a mob you targeted is placed within sight of you.
-- Stored as map id + percent coordinates (61.2, 52.3), like the guide format; every coordinate tuple
-- carries the zone and subzone name after the numbers so the merged data can be eyeballed.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local SHARE_V = 1              -- LodestarShareDB format version (meta.v)
local MAX_SAMPLES = 6          -- approximate positions kept per creature
-- How close the player was when a creature was seen. A nameplate appears at ~40 yd, so a sighting
-- recorded at the player's own position can be that far out -- fine for an arrow, poor for a map pin.
--
-- This used to grade that with CheckInteractDistance. It must not: that function is PROTECTED on
-- this client, and calling it from an addon raises ADDON_ACTION_BLOCKED and taints the execution
-- path. Four of them landed in one second on a live session, every one traced to the two pcalls
-- that were here, reached from NAME_PLATE_UNIT_ADDED, UPDATE_MOUSEOVER_UNIT and
-- PLAYER_TARGET_CHANGED -- so it fired on essentially every creature walked past. pcall does not
-- help: it catches Lua errors, and a blocked protected call is not a Lua error.
--
-- There is no unprotected way to ask how far away an arbitrary creature is. So passive sightings
-- are all recorded at one grade, and precision comes from the signal we can trust completely:
-- `exact`, set when a gossip, merchant or trainer frame is actually open, which means the player is
-- standing on top of the NPC. Slightly coarser passive data, no taint.
local NEAR_PASSIVE = 1         -- a nameplate or mouseover: somewhere within nameplate range
local SAMPLE_MIN_APART = 3     -- percent-of-map units; closer samples are merged
local OBJ_SAMPLES = 6          -- positions kept per quest objective
local OBJ_MIN_APART = 2        -- percent-of-map units between two objective samples
local MERCHANT_MAX = 200       -- merchant pages are small; cap the walk anyway
local TARGET_LINK_SECONDS = 10 -- an objective tick this long after targeting a mob is weak evidence for a link
local SCAN_BATCH, SCAN_TICK = 4, 0.25   -- 16 quest ids per second; the first census at 32/s answered ~1 in 4
local SCAN_MAX_PENDING = 40              -- requests in flight before the ticker waits for answers
local SCAN_TIMEOUT = 8                   -- seconds without an answer -> counted as missed (retried later)

local WORLD_KEYS = { "npcs", "objects", "quests", "taxi", "levels" }

-- Defined below, next to the position resolver it feeds, but called from the event dispatcher above
-- it; Lua needs the name in scope first.
local sweepWaypoints

local db                        -- LodestarShareDB (world data)
local scanDB                    -- LodestarScanDB (this account's trails and census cursor)
local objectiveState = {}       -- [questID] = { [i] = { finished, num } }
local diffQueued = false
local lastInteraction           -- { id, kind = "npc"|"object", name, t, live }
local lastTarget                -- { id, t }: the creature targeted most recently
local offer                     -- { questID, src, item, t }: what the open quest offer came from
local shareOffer                -- GetTime() of the last QUEST_ACCEPT_CONFIRM (a party share)
local scanTicker
local scanPending = {}          -- [questID] = GetTime() while a load is in flight
local backupSlot               -- forward declaration; defined with the wipe helpers below
local scanPendingCount = 0

--- Strip anything the client refuses to hand an addon (combat secrets, restricted values).
local function plain(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if canaccessvalue and not canaccessvalue(v) then return nil end
	return v
end

local function pct(v) return math.floor(v * 1000 + 0.5) / 10 end

local function playerXY()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return nil end
	return mapID, pct(x), pct(y)
end

--- Zone and subzone names for the spot the player is standing on ("" when the client will not say).
local function zoneText()
	local zone, sub = "", ""
	if GetRealZoneText then
		local ok, z = pcall(GetRealZoneText)
		z = ok and plain(z) or nil
		if type(z) == "string" then zone = z end
	end
	if GetSubZoneText then
		local ok, s = pcall(GetSubZoneText)
		s = ok and plain(s) or nil
		if type(s) == "string" then sub = s end
	end
	return zone, sub
end

--- A recorded position: { mapID, x, y, zone, subzone }. Kept a pure array so the offline merge keeps
--- reading the first three entries exactly as it always has.
local function spot()
	local mapID, x, y = playerXY()
	if not mapID then return nil end
	local zone, sub = zoneText()
	return { mapID, x, y, zone, sub }
end

--- Map id and percent coordinates of the player, or nil.
function Guide:PlayerMapXY() return playerXY() end

-- Saved variables ------------------------------------------------------------------------------------

--- One-time move of the world tables out of LodestarScanDB into LodestarShareDB. Nothing is dropped:
--- an entry already present in the share DB wins, everything else is carried across.
local function migrate(local_, share)
	local moved = false
	for _, key in ipairs(WORLD_KEYS) do
		local old = local_[key]
		if type(old) == "table" then
			local into = share[key]
			if type(into) ~= "table" then
				share[key] = old
			else
				for k, v in pairs(old) do if into[k] == nil then into[k] = v end end
			end
			local_[key] = nil
			moved = true
		end
	end
	if moved then local_.migrated = time() end
	return moved
end

-- Load-order probe. WoW populates an addon's SavedVariables AFTER executing its Lua files and
-- BEFORE firing ADDON_LOADED for it, so sampling both moments says whether the client ever loaded
-- the file at all or whether something clears it afterwards. Those need opposite fixes and nothing
-- outside the client can tell them apart.
local function questCount(t)
	if type(t) ~= "table" or type(t.quests) ~= "table" then return -1 end
	local n = 0
	for _ in pairs(t.quests) do n = n + 1 end
	return n
end

-- Both the current names and the ones they replaced, because either can be the one the client
-- hands back: a player coming from an older build has data under the legacy name and nothing under
-- the new one, and on a client that refuses "DB"-suffixed names (Core/Saved.lua) it is the other
-- way round. Sampling both at both moments is what says which case we are in.
local loadProbe = {
	atFileLoad = type(_G.LodestarHarvest),
	atFileLoadQuests = questCount(_G.LodestarHarvest),
	legacyAtFileLoad = type(_G.LodestarShareDB),
	legacyAtFileLoadQuests = questCount(_G.LodestarShareDB),
}
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(self, _, addon)
		if addon == "Lodestar_Guide" then
			loadProbe.atAddonLoaded = type(_G.LodestarHarvest)
			loadProbe.atAddonLoadedQuests = questCount(_G.LodestarHarvest)
			loadProbe.scanAtAddonLoaded = type(_G.LodestarScans)
			loadProbe.legacyAtAddonLoaded = type(_G.LodestarShareDB)
			loadProbe.legacyAtAddonLoadedQuests = questCount(_G.LodestarShareDB)
			self:UnregisterEvent("ADDON_LOADED")
		end
	end)
end

--- What the saved variables actually looked like the moment we first touched them, recorded into
--- LodestarProbeDB (which belongs to the core addon and is known to persist). A harvest that comes
--- back empty every session is either not being loaded by the client or not being saved by it, and
--- those need opposite fixes -- this is the one observation that tells them apart, and guessing at
--- it from the outside has already cost two wrong fixes.
local bindNoted = false
local function noteBind()
	if bindNoted then return end
	bindNoted = true
	local share, scan = _G.LodestarHarvest, _G.LodestarScans
	local countQuests = questCount
	local record = {
		at = date("%Y-%m-%d %H:%M:%S"),
		atFileLoad = loadProbe.atFileLoad,
		atFileLoadQuests = loadProbe.atFileLoadQuests,
		atAddonLoaded = loadProbe.atAddonLoaded or "never fired",
		atAddonLoadedQuests = loadProbe.atAddonLoadedQuests,
		scanAtAddonLoaded = loadProbe.scanAtAddonLoaded,
		legacyAtFileLoad = loadProbe.legacyAtFileLoad,
		legacyAtFileLoadQuests = loadProbe.legacyAtFileLoadQuests,
		legacyAtAddonLoaded = loadProbe.legacyAtAddonLoaded or "never fired",
		legacyAtAddonLoadedQuests = loadProbe.legacyAtAddonLoadedQuests,
		shareType = type(share),
		shareQuests = countQuests(share),
		scanType = type(scan),
		scanHadCursor = (type(scan) == "table" and type(scan.scan) == "table" and scan.scan.next ~= nil) or false,
		scanHadTrails = (type(scan) == "table" and type(scan.trails) == "table") or false,
	}
	Guide.lastBind = record
	-- Losing a harvest silently is the worst failure this addon has: the player walks a zone, the
	-- client hands back an empty table next session, and nothing says so. If the saved variables
	-- came back missing, say it out loud, once, and say what to do about it.
	-- Only a genuine loss is worth shouting about: if the harvest came back under the name it used
	-- to have, Core/Saved.lua is about to adopt it and nothing was lost.
	if record.shareType ~= "table" and record.legacyAtAddonLoaded ~= "table" then
		Guide.harvestDidNotLoad = true
		Lodestar:ScheduleTimer(function()
			Lodestar:Say("|cffff5555Your harvest did not load.|r The client handed Lodestar an empty database this session.")
			Lodestar:Say("  If you have harvested before, that data is still on disk in |cffffff7fLodestar_Guide.lua.bak|r next to the live file -- |cffffff7f/lode share|r prints the folder. Copy it somewhere safe BEFORE you log out, or this session will overwrite it.")
			Lodestar:Say("  This is a client-level fault, not lost work: |cffffff7f/lode harvest|r shows the load probe.")
		end, 12)
	end
	local probe = _G.LodestarProbes
	if type(probe) ~= "table" then probe = {} _G.LodestarProbes = probe end
	probe.harvestBinds = type(probe.harvestBinds) == "table" and probe.harvestBinds or {}
	tinsert(probe.harvestBinds, record)
	while #probe.harvestBinds > 6 do tremove(probe.harvestBinds, 1) end
end

local function ensureDB()
	-- noteBind first: it records what the CLIENT handed back, which adoption is about to paper over.
	noteBind()
	db = Lodestar:AdoptSaved("LodestarHarvest", "LodestarShareDB")
	scanDB = Lodestar:AdoptSaved("LodestarScans", "LodestarScanDB")
	migrate(scanDB, db)
	local build = select(2, GetBuildInfo())
	db.v = SHARE_V
	db.build = build
	for _, key in ipairs(WORLD_KEYS) do
		if type(db[key]) ~= "table" then db[key] = {} end
	end
	if type(db.meta) ~= "table" then db.meta = {} end
	db.meta.v = SHARE_V
	db.meta.build = build
	if type(db.meta.contributors) ~= "table" then db.meta.contributors = {} end
	scanDB.v = SHARE_V
	scanDB.build = build
	if type(scanDB.scan) ~= "table" then scanDB.scan = {} end
	return db
end

--- The shareable world data (npcs / objects / quests / taxi / levels / meta).
function Guide:HarvestDB() return db or ensureDB() end

--- This account's local-only data: the census cursor and the learned trails.
function Guide:ScanDB()
	if not scanDB then ensureDB() end
	return scanDB
end

--- (Re)bind both saved variables and run the migration. Called at enable; exposed for the smoke test.
function Guide:HarvestBindDB() return ensureDB() end

--- Credit the character playing right now, so the offline merge can weight and attribute a harvest.
local function noteContributor()
	-- Keyed by a hash of Name-Realm rather than the name itself. Everything the attribution is for
	-- -- weighting a position three people saw against one somebody saw three times, telling a
	-- covered zone from a zone one player walked twice -- works exactly the same on an id, and it
	-- means the file a contributor hands over, and the database it is merged into, carry no
	-- character names at all. The same id is what `/lode export` sends, so a contributor who uses
	-- both routes is one contributor and not two.
	local id = Lodestar.ContributorID(Lodestar.player and Lodestar.player.fullName)
	if not id then return end
	local c = db.meta.contributors[id]
	if type(c) ~= "table" then
		c = { first = time(), sessions = 0 }
		db.meta.contributors[id] = c
	end
	c.faction = plain(UnitFactionGroup("player")) or c.faction
	local race = plain(select(2, UnitRace("player")))
	if type(race) == "string" then c.race = race end
	local class = (Lodestar.player and Lodestar.player.class) or plain(select(2, UnitClass("player")))
	if type(class) == "string" then c.class = class end
	c.level = tonumber(plain(UnitLevel("player"))) or c.level
	c.last = time()
	c.sessions = (c.sessions or 0) + 1
end

-- Creatures -----------------------------------------------------------------------------------------------

local function guidInfo(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	id = tonumber(id)
	if not id then return nil end
	if kind == "Creature" or kind == "Vehicle" then return "npc", id end
	if kind == "GameObject" then return "object", id end
	return nil
end

local function entryFor(kind, id, name)
	local store = kind == "object" and db.objects or db.npcs
	local e = store[id]
	if not e then
		e = { name = name, seen = 0 }
		store[id] = e
	end
	if name and (not e.name or e.name == "") then e.name = name end
	e.seen = (e.seen or 0) + 1
	return e
end

local function farEnough(e, mapID, x, y)
	for _, s in ipairs(e.samples or {}) do
		if s[1] == mapID and math.abs(s[2] - x) < SAMPLE_MIN_APART and math.abs(s[3] - y) < SAMPLE_MIN_APART then return false end
	end
	return true
end

--- Record a creature seen through a unit token. `exact` = we are interacting with it (within ~5 yd).
local function noteUnit(unit, exact)
	if not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
	local guid = plain(UnitGUID(unit))
	local kind, id = guidInfo(guid)
	if not kind then return nil end
	local name = plain(UnitName(unit))
	if type(name) ~= "string" then name = nil end
	local e = entryFor(kind, id, name)
	local mapID, x, y = playerXY()
	if kind == "npc" then
		local level = tonumber(plain(UnitLevel(unit)))
		if level and level > 0 then
			e.minL = e.minL and math.min(e.minL, level) or level
			e.maxL = e.maxL and math.max(e.maxL, level) or level
		end
		local cls = plain(UnitClassification(unit))
		if type(cls) == "string" and cls ~= "normal" then e.cls = cls end
		local react = tonumber(plain(UnitReaction("player", unit)))
		if react then e.react = react end
		local ctype = plain(UnitCreatureType(unit))
		if type(ctype) == "string" then e.ctype = ctype end
	end
	if mapID then
		-- Zone names cost two C calls; only ask when a position is actually going to be written. Every
		-- nameplate in a pull comes through here.
		if exact then
			-- Count only the first time this one is placed: walking past the same NPC twenty times
			-- is one contribution, and a nudge that fires on a busy pull is a nudge people mute.
			if not e.exact then
				Guide.placedThisSession = (Guide.placedThisSession or 0) + 1
				if Guide.MaybeNudgeShare then Guide:MaybeNudgeShare(Guide.placedThisSession) end
			end
			e.map, e.x, e.y, e.exact = mapID, x, y, true
			e.via = nil                                   -- seen first-hand: no longer second-hand
			local zone, sub = zoneText()
			if zone ~= "" then e.zone = zone end
			if sub ~= "" then e.subzone = sub end
			if kind == "npc" and Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("npc", id, e) end
		elseif not e.exact then
			e.samples = e.samples or {}
			local near = NEAR_PASSIVE
			if #e.samples < MAX_SAMPLES and farEnough(e, mapID, x, y) then
				local zone, sub = zoneText()
				tinsert(e.samples, { mapID, x, y, zone, sub })
			end
			-- A closer sighting always replaces a further one. Walking past an NPC inside trade range
			-- pins it about as well as opening its dialogue did, so a sweep through a zone maps it.
			if not e.map or near > (e.near or 0) then
				e.map, e.x, e.y, e.near = mapID, x, y, near
				if near >= 2 then
					local zone, sub = zoneText()
					if zone ~= "" then e.zone = zone end
					if sub ~= "" then e.subzone = sub end
					if kind == "npc" and Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("npc", id, e) end
				end
			end
		end
	end
	return e, kind, id
end

--- The NPC/object we are interacting with (gossip, quest, merchant, trainer, taxi frames). The
--- interaction is "live" only while that frame is open: a review found quests being credited to
--- whatever NPC had been talked to within the last 30 s, which mis-credits every quest that starts
--- from an item, a party share or an area trigger. Whenever a frame opens without a readable NPC the
--- previous interaction stops being live, so nothing stale can be credited.
local function noteInteraction(event)
	local unit = (event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "QUEST_GREETING") and "questnpc" or "npc"
	local e, kind, id = noteUnit(unit, true)
	if not e then e, kind, id = noteUnit(unit == "npc" and "questnpc" or "npc", true) end
	if not e then
		if lastInteraction then lastInteraction.live = false end
		return nil
	end
	lastInteraction = { id = id, kind = kind, name = e.name, t = GetTime(), live = true }
	return e, kind, id
end

local function endInteraction()
	if lastInteraction then lastInteraction.live = false end
end

--- The npc/object reference for the frame that is open right now, or nil. Never a stale one.
local function interactionRef()
	if lastInteraction and lastInteraction.live then
		return lastInteraction.kind == "object" and ("o" .. lastInteraction.id) or lastInteraction.id
	end
end

-- Quests --------------------------------------------------------------------------------------------------

local function questEntry(questID, title)
	local q = db.quests[questID]
	if not q then
		q = {}
		db.quests[questID] = q
	end
	if title and title ~= "" and not q.t then q.t = title end
	return q
end

--- Which race and class have had this quest in their log. A class or race quest is only ever seen by
--- one of them, so the offline merge can work the mask out across contributors.
local function noteSeenBy(q)
	local race = plain(select(2, UnitRace("player")))
	if type(race) == "string" and race ~= "" then
		q.races = q.races or {}
		q.races[race] = true
	end
	local class = (Lodestar.player and Lodestar.player.class) or plain(select(2, UnitClass("player")))
	if type(class) == "string" and class ~= "" then
		q.classes = q.classes or {}
		q.classes[class] = true
	end
end

local function objectivesOf(questID)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(objectives) ~= "table" then return nil end
	local list = {}
	for i, o in ipairs(objectives) do
		local text = o.text and o.text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "") or nil
		list[i] = { text = text, type = o.type, n = o.numRequired }
	end
	return #list > 0 and list or nil
end

local function snapshotObjectives(questID)
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(objectives) ~= "table" then return end
	local state = {}
	for i, o in ipairs(objectives) do
		local n = tonumber(o.numFulfilled) or tonumber(o.text and o.text:match("(%d+)%s*/%s*%d+")) or 0
		state[i] = { finished = o.finished and true or false, num = n }
	end
	objectiveState[questID] = state
end

--- Everything the quest log will tell us about a quest. Called when a quest enters the log and again
--- whenever one of its objectives moves, so a title/level/tag that only resolves later is picked up.
local function noteQuestFromLog(questID)
	local q = questEntry(questID, C_QuestLog.GetTitleForQuestID(questID))
	local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	local info = idx and C_QuestLog.GetInfo(idx)
	if info then
		if info.level and info.level > 0 then q.lvl = info.level end
		if info.suggestedGroup and info.suggestedGroup > 0 then q.group = info.suggestedGroup end
		if info.frequency and info.frequency ~= 0 then q.freq = info.frequency end
	end
	if not q.lvl and C_QuestLog.GetQuestDifficultyLevel then
		local lvl = C_QuestLog.GetQuestDifficultyLevel(questID)
		if lvl and lvl > 0 then q.lvl = lvl end
	end
	q.o = objectivesOf(questID) or q.o
	if C_QuestLog.GetQuestTagInfo then
		local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
		if ok and type(tag) == "table" and tag.tagName then q.tag = tag.tagName end
	end
	-- Escort/coin quests want money up front. GetQuestLogRequiredMoney does not exist on this client
	-- (checked against tools/wow-api); C_QuestLog.GetRequiredMoney is the one that does.
	if C_QuestLog.GetRequiredMoney then
		local ok, money = pcall(C_QuestLog.GetRequiredMoney, questID)
		money = ok and tonumber(plain(money)) or nil
		if money and money > 0 then q.req = money end
	end
	noteSeenBy(q)
	return q
end

--- Record the player's position against a quest. `single` keeps one spot (the finish); otherwise up to
--- OBJ_SAMPLES well-spread ones, so the offline merge can turn them into an objective area.
local function recordSpot(q, key, index, single)
	local s = spot()
	if not s then return end
	q[key] = q[key] or {}
	if single then
		q[key][index] = s
		return
	end
	local list = q[key][index]
	if not list then
		list = {}
		q[key][index] = list
	end
	if #list >= OBJ_SAMPLES then return end
	for _, p in ipairs(list) do
		if p[1] == s[1] and math.abs(p[2] - s[2]) < OBJ_MIN_APART and math.abs(p[3] - s[3]) < OBJ_MIN_APART then return end
	end
	tinsert(list, s)
end

--- Weak evidence: an objective counter moved shortly after this creature was targeted, so the creature
--- is probably what that objective is about. Stored as a tick count under `objGuess`, never as fact.
local function noteObjectiveTarget(questID)
	if not lastTarget or (GetTime() - lastTarget.t) > TARGET_LINK_SECONDS then return end
	local e = db.npcs[lastTarget.id]
	if not e then return end
	e.objGuess = e.objGuess or {}
	e.objGuess[questID] = (e.objGuess[questID] or 0) + 1
end

local function diffObjectives()
	diffQueued = false
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local qid = info.questID
			local prev = objectiveState[qid]
			local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, qid)
			local changed = prev == nil
			if prev and ok and type(objectives) == "table" then
				local q
				for idx, o in ipairs(objectives) do
					local before = prev[idx]
					local num = tonumber(o.numFulfilled) or tonumber(o.text and o.text:match("(%d+)%s*/%s*%d+")) or 0
					if before and num > (before.num or 0) then
						q = q or questEntry(qid, info.title)
						recordSpot(q, "prog", idx, false)
						noteObjectiveTarget(qid)
						changed = true
					end
					if o.finished and before and not before.finished then
						q = q or questEntry(qid, info.title)
						recordSpot(q, "fin", idx, true)
						recordSpot(q, "prog", idx, false)   -- the finishing spot counts toward the objective area too
						noteObjectiveTarget(qid)
						changed = true
					end
				end
			end
			-- Nothing moved: no metadata call either. Only a quest that is new to us or that just
			-- ticked pays for a re-read of the log.
			if changed then noteQuestFromLog(qid) end
			snapshotObjectives(qid)
		end
	end
end

local function queueDiff()
	if diffQueued then return end
	diffQueued = true
	Guide:ScheduleTimer(diffObjectives, 0.3)
end

local function noteOffered(e, list, ends)
	if type(list) ~= "table" then return end
	for _, info in ipairs(list) do
		local qid = info.questID
		if qid then
			local q = questEntry(qid, info.title)
			if info.questLevel and info.questLevel > 0 then q.lvl = info.questLevel end
			if info.frequency and info.frequency ~= 0 then q.freq = info.frequency end
			if info.repeatable then q.rep = true end
			if ends then
				e.ends = e.ends or {}
				e.ends[qid] = true
			else
				e.gives = e.gives or {}
				e.gives[qid] = true
			end
		end
	end
end

local function noteGreeting(e)
	if GetNumAvailableQuests then
		for i = 1, GetNumAvailableQuests() do
			local _, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(i)
			if questID then
				local q = questEntry(questID, GetAvailableTitle and GetAvailableTitle(i))
				if frequency and frequency ~= 0 then q.freq = frequency end
				if isRepeatable then q.rep = true end
				e.gives = e.gives or {}
				e.gives[questID] = true
			end
		end
	end
	if GetNumActiveQuests and GetActiveQuestID then
		for i = 1, GetNumActiveQuests() do
			local questID = GetActiveQuestID(i)
			if questID then
				questEntry(questID, GetActiveTitle and GetActiveTitle(i))
				e.ends = e.ends or {}
				e.ends[questID] = true
			end
		end
	end
end

local function noteRewardXP(q)
	if not GetRewardXP then return end
	local xp = tonumber(plain(GetRewardXP()))
	local level = UnitLevel("player")
	if xp and xp > 0 and (not q.xp or level <= q.xp[1]) then q.xp = { level, xp } end
	if GetRewardMoney then
		local money = tonumber(plain(GetRewardMoney()))
		if money and money > 0 then q.money = money end
	end
end

--- Where the offer that is on screen right now came from. `questStartItemID` is QUEST_DETAIL's own
--- payload (non-zero for a quest that starts from an item in your bags); an area-trigger offer says so
--- through QuestIsFromAreaTrigger; a party share arrives with a player, not an NPC, as the giver.
local function noteOffer(questStartItemID)
	local questID = GetQuestID and GetQuestID()
	if type(questID) ~= "number" or questID <= 0 then questID = nil end
	local item = tonumber(questStartItemID)
	if item and item > 0 then
		endInteraction()
		offer = { questID = questID, src = "item", item = item, t = GetTime() }
		return nil, questID
	end
	if QuestIsFromAreaTrigger then
		local ok, fromTrigger = pcall(QuestIsFromAreaTrigger)
		if ok and fromTrigger then
			endInteraction()
			offer = { questID = questID, src = "trigger", t = GetTime() }
			return nil, questID
		end
	end
	if UnitExists("questnpc") and UnitIsPlayer("questnpc") then
		endInteraction()
		offer = { questID = questID, src = "share", t = GetTime() }
		return nil, questID
	end
	local e, kind = noteInteraction("QUEST_DETAIL")
	offer = { questID = questID, src = e and (kind == "object" and "object" or "npc") or "unknown", t = GetTime() }
	return e, questID
end

--- Attribute a freshly accepted quest. Only a live interaction credits an NPC; everything else records
--- the player's own position and says where the quest came from instead.
local function attributeAccept(q, questID)
	local src
	local now = GetTime()
	if offer and offer.src and (offer.questID == nil or offer.questID == questID) and (now - offer.t) < 60 then
		src = offer.src
		if offer.item then q.item = offer.item end
	elseif shareOffer and (now - shareOffer) < 30 then
		src = "share"
	end
	local ref = interactionRef()
	if ref and (not src or src == "npc" or src == "object") then
		q.giver = ref
		q.via = nil                 -- we watched this one happen; it is no longer second-hand
		src = src or (type(ref) == "string" and "object" or "npc")
	elseif not src then
		src = "unknown"
	end
	q.src = q.src or src
	local s = spot()
	if s then q.acceptAt = s end
	if q.giver and Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("quest", questID, q) end
end

-- Merchants ---------------------------------------------------------------------------------------------------

--- What this vendor sells, so `.buy` steps can be authored from the merged data. Both APIs are
--- undocumented C globals on this client (verified in tools/wow-api/c_globals_inferred.txt); without
--- either of them the feature simply does not run.
local function noteMerchant(e)
	if not (GetMerchantNumItems and GetMerchantItemID) then return end
	local ok, count = pcall(GetMerchantNumItems)
	count = ok and tonumber(plain(count)) or nil
	if not count or count <= 0 then return end
	if count > MERCHANT_MAX then count = MERCHANT_MAX end
	for i = 1, count do
		local good, itemID = pcall(GetMerchantItemID, i)
		itemID = good and tonumber(plain(itemID)) or nil
		if itemID and itemID > 0 then
			e.sells = e.sells or {}
			e.sells[itemID] = true
		end
	end
end

-- Taxi --------------------------------------------------------------------------------------------------------

local TAXI_RANK = { unreachable = 1, reachable = 2, current = 3 }

local function taxiEntry(nodeID)
	local t = db.taxi[nodeID]
	if not t then
		t = {}
		db.taxi[nodeID] = t
	end
	return t
end

--- Every node on the flight map, and the edges out of the one we are standing on. The node list is not
--- ordered, so the current node is found first: a review found every edge listed before it being
--- dropped. Nothing is replaced — states only ever improve and the link set accumulates across visits,
--- so the graph grows instead of being rewritten by whatever one flight map happened to show.
local function noteTaxi(e)
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
	local mapID = (_G.GetTaxiMapID and _G.GetTaxiMapID()) or C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not ok or type(nodes) ~= "table" then return end
	local currentID
	for _, node in ipairs(nodes) do
		if node.nodeID and node.state == Enum.FlightPathState.Current then currentID = tonumber(node.nodeID) end
	end
	local reachable, n = {}, 0
	for _, node in ipairs(nodes) do
		local nodeID = tonumber(node.nodeID)
		if nodeID then
			local t = taxiEntry(nodeID)
			t.name = node.name or t.name
			if node.position then
				local x, y = node.position:GetXY()
				if type(x) == "number" and type(y) == "number" then t.map, t.x, t.y = mapID, pct(x), pct(y) end
			end
			local state = (node.state == Enum.FlightPathState.Current and "current")
				or (node.state == Enum.FlightPathState.Reachable and "reachable") or "unreachable"
			if (TAXI_RANK[state] or 0) >= (TAXI_RANK[t.state] or 0) then t.state = state end
			if nodeID == currentID then
				local zone, sub = zoneText()
				if zone ~= "" then t.zone = zone end
				if sub ~= "" then t.subzone = sub end
				-- node <-> flight master: the NPC whose window is open right now
				if e and lastInteraction and lastInteraction.live and lastInteraction.kind == "npc" then
					t.npc = lastInteraction.id
					e.taxiNode = nodeID
				end
				if Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("taxi", nodeID, t) end
			elseif state == "reachable" then
				n = n + 1
				reachable[n] = nodeID
			end
		end
	end
	if currentID then
		local cur = taxiEntry(currentID)
		cur.links = cur.links or {}
		for i = 1, n do cur.links[reachable[i]] = true end
	end
end

-- Levels -----------------------------------------------------------------------------------------------------

local function noteLevel()
	local level, max = UnitLevel("player"), UnitXPMax("player")
	if level and max and max > 0 then db.levels[level] = max end
end

-- Events -----------------------------------------------------------------------------------------------------

function Guide:HarvestOnEvent(event, ...)
	if not db then ensureDB() end
	if event == "GOSSIP_SHOW" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			local avail = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()
			local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
			if (avail and #avail > 0) or (active and #active > 0) then e.kind.quest = true end
			noteOffered(e, avail, false)
			noteOffered(e, active, true)
			-- Only the innkeeper bind is safe to infer from gossip text: guards offer "Class trainer" directions,
			-- so vendor/trainer/taxi roles are tagged by their own frames (MERCHANT_SHOW, TRAINER_SHOW, TAXIMAP_OPENED).
			for _, opt in ipairs((C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()) or {}) do
				local name = opt.name and opt.name:lower() or ""
				if name:find("inn your home", 1, true) or name:find("make this inn", 1, true) then e.kind.inn = true end
			end
		end
	elseif event == "QUEST_GREETING" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			e.kind.quest = true
			noteGreeting(e)
		end
	elseif event == "QUEST_DETAIL" then
		local e, questID = noteOffer(...)
		if questID then
			local q = questEntry(questID, GetTitleText and GetTitleText())
			if e then
				e.kind = e.kind or {}
				e.kind.quest = true
				e.gives = e.gives or {}
				e.gives[questID] = true
				q.giver = q.giver or interactionRef()
			else
				if offer and offer.src then q.src = q.src or offer.src end
				if offer and offer.item then q.item = offer.item end
				if QuestGetAutoAccept and QuestGetAutoAccept() then q.auto = true end
			end
			noteRewardXP(q)
		end
	elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
		local questID = GetQuestID and GetQuestID()
		if questID and questID > 0 then
			local e = noteInteraction(event)
			local q = questEntry(questID, GetTitleText and GetTitleText())
			if e then
				e.kind = e.kind or {}
				e.kind.quest = true
				e.ends = e.ends or {}
				e.ends[questID] = true
				q.ender = interactionRef()
				q.via = nil            -- watched first-hand
				if Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("quest", questID, q) end
			end
			if event == "QUEST_COMPLETE" then noteRewardXP(q) end
		end
	elseif event == "QUEST_ACCEPT_CONFIRM" then
		shareOffer = GetTime()
	elseif event == "QUEST_ACCEPTED" then
		local questID = ...
		if type(questID) == "number" then
			local q = noteQuestFromLog(questID)
			attributeAccept(q, questID)
			snapshotObjectives(questID)
			offer, shareOffer = nil, nil
		end
	elseif event == "QUEST_TURNED_IN" then
		local questID, xp, money = ...
		if type(questID) == "number" then
			local q = questEntry(questID, C_QuestLog.GetTitleForQuestID(questID))
			q.ender = q.ender or interactionRef()
			local level = UnitLevel("player")
			if type(xp) == "number" and xp > 0 and (not q.xp or level <= q.xp[1]) then q.xp = { level, xp } end
			if type(money) == "number" and money > 0 then q.money = money end
			q.turninAt = spot() or q.turninAt
			q.done = true
			objectiveState[questID] = nil
		end
	elseif event == "QUEST_REMOVED" then
		local questID = ...
		if type(questID) == "number" then objectiveState[questID] = nil end
	elseif event == "QUEST_FINISHED" or event == "GOSSIP_CLOSED" then
		endInteraction()
		offer = nil
	elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
		queueDiff()
		sweepWaypoints()
	elseif event == "PLAYER_TARGET_CHANGED" then
		local _, kind, id = noteUnit("target", false)
		lastTarget = (kind == "npc" and id) and { id = id, t = GetTime() } or nil
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		noteUnit("mouseover", false)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		if type(unit) == "string" then noteUnit(unit, false) end
	elseif event == "MERCHANT_SHOW" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			e.kind.vendor = true
			if CanMerchantRepair and CanMerchantRepair() then e.kind.repair = true end
			noteMerchant(e)
		end
	elseif event == "MERCHANT_CLOSED" then
		endInteraction()
	elseif event == "TRAINER_SHOW" then
		local e = noteInteraction(event)
		if e then
			e.kind = e.kind or {}
			e.kind.trainer = true
			if IsTradeskillTrainer then
				local ok, trade = pcall(IsTradeskillTrainer)
				if ok and trade then e.kind.tradeskill = true end
			end
		end
	elseif event == "TRAINER_CLOSED" then
		endInteraction()
	elseif event == "TAXIMAP_OPENED" then
		local e = noteInteraction(event)
		if e then e.kind = e.kind or {} e.kind.taxi = true end
		noteTaxi(e)
	elseif event == "HEARTHSTONE_BOUND" then
		local e = noteInteraction("GOSSIP_SHOW")
		if e then e.kind = e.kind or {} e.kind.inn = true end
	elseif event == "PLAYER_LEVEL_UP" then
		self:ScheduleTimer(noteLevel, 1)
	elseif event == "PLAYER_ENTERING_WORLD" then
		noteLevel()
		wipe(objectiveState)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				snapshotObjectives(info.questID)
				noteQuestFromLog(info.questID)
			end
		end
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		self:ScanOnLoadResult(...)
	end
end

-- Read-back for smart mode --------------------------------------------------------------------------------------

local function refPosition(ref)
	if not ref then return nil end
	local e
	if type(ref) == "string" then e = db.objects[tonumber(ref:sub(2))] else e = db.npcs[ref] end
	if e and e.map and e.x and e.y then return e.map, e.x, e.y, e.name end
	return nil
end

--- Best known position for a quest in the log: mapID, x, y (0..1), how.
-- Where the client itself says to go next ----------------------------------------------------------
--
-- C_QuestLog.GetNextWaypoint(questID) gives the map and position of a quest's next objective, for
-- anything in the log, without going there. Forever exposes no quest POIs to addons, so this is the
-- only source of objective positions that does not require a player to walk to the spot and be
-- standing on it when the counter moves -- which is what makes the harvest slow to fill in. A quest
-- accepted in a village now knows roughly where its objective is the moment it is accepted.
--
-- Recorded under its own key rather than as a sighting. It is the game's own hint, and it is about
-- the CURRENT objective of THIS character, so it moves as the quest progresses; a player standing
-- on the spot with the counter ticking is better evidence and keeps its precedence below.
local WAYPOINT_EVERY = 10        -- seconds between sweeps of the log
local lastWaypointSweep = 0

function sweepWaypoints()
	if not (C_QuestLog and C_QuestLog.GetNextWaypoint and C_QuestLog.GetNumQuestLogEntries) then return 0 end
	local now = GetTime()
	if now - lastWaypointSweep < WAYPOINT_EVERY then return 0 end
	lastWaypointSweep = now
	local added = 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local qi = C_QuestLog.GetInfo(i)
		if qi and not qi.isHeader and qi.questID then
			local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, qi.questID)
			map, x, y = plain(map), plain(x), plain(y)
			-- Fractions of the map, and 0,0 is what the client returns for "no waypoint" rather than
			-- a position at the top-left corner.
			if ok and type(map) == "number" and type(x) == "number" and type(y) == "number"
				and (x > 0 or y > 0) and x <= 1 and y <= 1 then
				local q = questEntry(qi.questID, qi.title)
				local px, py = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
				-- Once a quest is complete the "next objective" IS the turn-in, so the same call
				-- hands over the ender's position -- which is the thing route generation is actually
				-- short of. Objective waypoints and turn-in waypoints are kept apart: they mean
				-- different things and a turn-in written over an objective would send the arrow to
				-- the wrong end of the zone for everyone the data is shared with.
				local key = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(qi.questID)) and "turninWp" or "wp"
				local was = q[key]
				if not (was and was[1] == map and math.abs(was[2] - px) < 0.1 and math.abs(was[3] - py) < 0.1) then
					q[key] = { map, px, py }
					added = added + 1
					if Guide.QueueHarvestDelta then Guide:QueueHarvestDelta("quest", qi.questID, q) end
				end
			end
		end
	end
	return added
end

--- Exposed for the smoke test and for `/lode harvest`: sweep now, ignoring the throttle.
function Guide:HarvestWaypoints()
	lastWaypointSweep = 0
	return sweepWaypoints()
end

function Guide:HarvestQuestPosition(questID, complete)
	if not db then ensureDB() end
	local q = db.quests[questID]
	if not q then return nil end
	local mapID, x, y, how
	if complete then
		mapID, x, y = refPosition(q.ender)
		how = "ender"
		if not mapID and q.turninAt then mapID, x, y, how = q.turninAt[1], q.turninAt[2], q.turninAt[3], "turnin" end
		if not mapID and q.turninWp then
			-- The client's own arrow for a completed quest, which points at whoever takes it back.
			mapID, x, y, how = q.turninWp[1], q.turninWp[2], q.turninWp[3], "waypoint"
		end
		if not mapID then
			-- Most Classic quests end where they began; say so in the subtitle via `how`.
			mapID, x, y = refPosition(q.giver)
			how = "giver"
			if not mapID and q.acceptAt then mapID, x, y, how = q.acceptAt[1], q.acceptAt[2], q.acceptAt[3], "accept" end
		end
	else
		local objectives = C_QuestLog.GetQuestObjectives(questID)
		local idx
		for i, o in ipairs(objectives or {}) do if not o.finished then idx = i break end end
		idx = idx or 1
		local spot_ = type(q.fin) == "table" and q.fin[idx]
		if spot_ then mapID, x, y, how = spot_[1], spot_[2], spot_[3], "done" end
		if not mapID and q.prog and q.prog[idx] and q.prog[idx][1] then
			local s = q.prog[idx][1]
			mapID, x, y, how = s[1], s[2], s[3], "progress"
		end
		-- Last: the client's own waypoint. Weaker than a player who stood there and watched the
		-- counter move, but far better than no arrow at all, and it is there from the moment the
		-- quest is accepted.
		if not mapID and q.wp then
			mapID, x, y, how = q.wp[1], q.wp[2], q.wp[3], "waypoint"
		end
	end
	if not mapID then return nil end
	return mapID, x / 100, y / 100, how
end

--- Quests harvested quest givers on this map offer that the player can still pick up.
function Guide:HarvestAvailableItems(items, mapID)
	if not db then ensureDB() end
	local level = UnitLevel("player")
	local seen = {}
	for _, it in ipairs(items) do if it.questID then seen[it.questID] = true end end
	local function fromStore(store, isObject)
		for id, e in pairs(store) do
			if e.map == mapID and e.gives and e.x and e.y then
				for qid in pairs(e.gives) do
					if not seen[qid] and not C_QuestLog.IsOnQuest(qid) and not C_QuestLog.IsQuestFlaggedCompleted(qid)
						and not Guide:QuestUnavailable(qid) then
						local q = db.quests[qid]
						local lvl = q and q.lvl
						local trivial = lvl and (level - lvl) >= 6
						-- `done` means "some character on this account finished it", which says nothing
						-- about THIS character. IsQuestFlaggedCompleted above is the eligibility test.
						if not trivial then
							seen[qid] = true
							tinsert(items, { kind = "available", questID = qid, mapID = mapID, x = e.x / 100, y = e.y / 100, source = "harvest",
								title = (q and q.t) or C_QuestLog.GetTitleForQuestID(qid) or ("Quest " .. qid),
								subtitle = "Pick up from " .. (e.name or (isObject and "object" or ("NPC " .. id))) .. (lvl and (" · lvl " .. lvl) or ""),
								level = lvl })
						end
					end
				end
			end
		end
	end
	fromStore(db.npcs, false)
	fromStore(db.objects, true)
end

-- Counts --------------------------------------------------------------------------------------------------------

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

--- What is in the shareable file right now. Used by `/lode share`, the minimap tooltip and the
--- settings page.
function Guide:HarvestSummary()
	if not db then ensureDB() end
	local out = {
		quests = count(db.quests), npcs = count(db.npcs), objects = count(db.objects),
		taxi = count(db.taxi), levels = count(db.levels), contributors = count(db.meta and db.meta.contributors),
		positions = 0, backup = backupSlot() and true or false,
	}
	for _, e in pairs(db.npcs) do if e.exact then out.positions = out.positions + 1 end end
	for _, e in pairs(db.objects) do if e.map then out.positions = out.positions + 1 end end
	return out
end

-- Quest census: /lode scan quests ------------------------------------------------------------------------------

local function scanRecord(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if not title or title == "" then return false end
	local q = questEntry(questID, title)
	q.t = q.t or title
	q.o = objectivesOf(questID) or q.o
	if C_QuestLog.GetQuestDifficultyLevel and not q.lvl then
		local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
		if ok and lvl and lvl > 0 then q.lvl = lvl end
	end
	if C_QuestLog.GetQuestTagInfo and not q.tag then
		local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
		if ok and type(tag) == "table" and tag.tagName then q.tag = tag.tagName end
	end
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
		local ok, cls = pcall(C_QuestInfoSystem.GetQuestClassification, questID)
		if ok and type(cls) == "number" then q.cls = cls end
	end
	if C_QuestLog.IsQuestFlaggedCompleted(questID) then q.done = true end
	q.scanned = true
	return true
end

-- `missedCount` is a running mirror of `missed`, so every add and removal goes through this pair;
-- counting them separately is how the two drifted apart and left a permanent phantom backlog.
local function markMissed(s, questID)
	s.missed = s.missed or {}
	if not s.missed[questID] then s.missedCount = (s.missedCount or 0) + 1 end
	s.missed[questID] = (s.missed[questID] or 0) + 1
end

local function clearMissed(s, questID)
	if s.missed and s.missed[questID] then
		s.missed[questID] = nil
		s.missedCount = math.max(0, (s.missedCount or 1) - 1)
	end
end

function Guide:ScanOnLoadResult(questID, success)
	if not scanPending[questID] then return end
	scanPending[questID] = nil
	scanPendingCount = scanPendingCount - 1
	local s = scanDB.scan
	if success then
		if scanRecord(questID) then
			s.found = (s.found or 0) + 1
			clearMissed(s, questID)
		else
			-- the client said yes but the title is not readable yet: look again shortly
			self:ScheduleTimer(function()
				if scanRecord(questID) then
					s.found = (s.found or 0) + 1
					clearMissed(s, questID)
				else
					markMissed(s, questID)
				end
			end, 1)
		end
	else
		s.absent = (s.absent or 0) + 1
		clearMissed(s, questID)   -- the client answered: stop retrying this id
	end
end

--- Requests that never got an answer are counted as missed and retried by `/lode scan retry`.
local function expirePending(s)
	local now = GetTime()
	for id, at in pairs(scanPending) do
		if now - at > SCAN_TIMEOUT then
			scanPending[id] = nil
			scanPendingCount = scanPendingCount - 1
			markMissed(s, id)
		end
	end
end

local function scanTick()
	local s = scanDB.scan
	expirePending(s)
	if not s.next or s.next > s.to then
		if scanPendingCount > 0 then return end -- let the last answers land
		Guide:StopScan(true)
		return
	end
	if scanPendingCount >= SCAN_MAX_PENDING then return end
	local n = 0
	while n < (s.batch or SCAN_BATCH) and s.next <= s.to do
		local id = s.next
		s.next = s.next + 1
		s.checked = (s.checked or 0) + 1
		if scanRecord(id) then
			s.found = (s.found or 0) + 1        -- already cached; no request needed
		else
			scanPending[id] = GetTime()
			scanPendingCount = scanPendingCount + 1
			pcall(C_QuestLog.RequestLoadQuestByID, id)
		end
		n = n + 1
	end
	if s.checked % 500 == 0 then
		Lodestar:Msg("Quest scan: %d/%d checked, %d quests found, %d unanswered.", s.next - s.from, s.to - s.from + 1, s.found or 0, s.missedCount or 0)
	end
end

--- Second pass over ids that got no answer: one request per tick.
function Guide:RetryScan()
	if not db then ensureDB() end
	local s = scanDB.scan
	local list = {}
	for id in pairs(s.missed or {}) do tinsert(list, id) end
	table.sort(list)
	if #list == 0 then Lodestar:Say("Nothing to retry.") return end
	if scanTicker then Lodestar:Say("A scan is running; /lode scan stop first.") return end
	Lodestar:Say("Retrying %d unanswered quest ids slowly (4 per second).", #list)
	local i = 0
	scanTicker = self:ScheduleRepeatingTimer(function()
		expirePending(s)
		if i >= #list then
			if scanPendingCount > 0 then return end
			self:CancelTimer(scanTicker) scanTicker = nil
			local left = 0
			for _ in pairs(s.missed or {}) do left = left + 1 end
			s.missedCount = left   -- repair a count that drifted in an earlier session
			Lodestar:Say("Retry finished: %d quests found in total, %d ids still unanswered.", s.found or 0, left)
			return
		end
		i = i + 1
		local id = list[i]
		if scanRecord(id) then
			s.found = (s.found or 0) + 1
			clearMissed(s, id)
		else
			scanPending[id] = GetTime()
			scanPendingCount = scanPendingCount + 1
			pcall(C_QuestLog.RequestLoadQuestByID, id)
		end
	end, SCAN_TICK)
end

function Guide:StartScan(from, to)
	if not db then ensureDB() end
	local s = scanDB.scan
	if scanTicker then Lodestar:Say("A scan is already running (%d/%d). /lode scan stop", s.next - s.from, s.to - s.from + 1) return end
	if from then
		s.from, s.to, s.next, s.checked, s.found, s.absent, s.finishedAt = from, to, from, 0, 0, 0, nil
	elseif not s.next or not s.to or s.next > s.to then
		Lodestar:Say("Usage: /lode scan quests <from> <to>   e.g. /lode scan quests 1 10000")
		return
	end
	s.paused = nil                          -- an explicit start or /lode scan resume clears the user's pause
	s.startedAt = time()
	scanTicker = self:ScheduleRepeatingTimer(scanTick, SCAN_TICK)
	Lodestar:Say("Scanning quest ids %d-%d (%d per second). Keep playing; /lode scan status for progress, /lode scan stop to pause.",
		s.next, s.to, math.floor((s.batch or SCAN_BATCH) / SCAN_TICK))
end

function Guide:StopScan(finished)
	if scanTicker then self:CancelTimer(scanTicker) scanTicker = nil end
	local s = scanDB and scanDB.scan
	if not s then return end
	if finished then
		Lodestar:Say("Quest scan finished: %d ids checked, %d quests found. They are saved account-wide; /reload or log out to write them to disk.", s.checked or 0, s.found or 0)
		s.finishedAt = time()
	else
		s.paused = true                     -- a pause the user asked for sticks across /reload and logout
		Lodestar:Say("Quest scan paused at %d (%d found). /lode scan resume to continue.", s.next or 0, s.found or 0)
	end
end

local function scanStatus()
	local s = scanDB.scan
	local sum = Guide:HarvestSummary()
	Lodestar:Say("Harvest: %d quests, %d NPCs, %d objects, %d flight nodes.", sum.quests, sum.npcs, sum.objects, sum.taxi)
	if s.to then
		Lodestar:Say("Quest scan %s: ids %d-%d, at %d, %d checked, %d found, %d absent, %d unanswered (/lode scan retry).",
			scanTicker and "running" or (s.paused and "paused" or "stopped"),
			s.from or 0, s.to, s.next or 0, s.checked or 0, s.found or 0, s.absent or 0, s.missedCount or 0)
	end
end

local function handleScan(rest)
	if not db then ensureDB() end
	local verb, a, b = strsplit(" ", strtrim(rest or ""), 3)
	verb = (verb or ""):lower()
	if verb == "quests" or verb == "quest" then
		local from, to = tonumber(a), tonumber(b)
		if from and not to then to = from + 9999 end
		if from and to and to >= from then Guide:StartScan(math.max(1, from), to) else Guide:StartScan() end
	elseif verb == "resume" then
		Guide:StartScan()
	elseif verb == "retry" then
		Guide:RetryScan()
	elseif verb == "stop" or verb == "pause" then
		if scanTicker then Guide:StopScan(false) else Lodestar:Say("No scan running.") end
	elseif verb == "status" or verb == "" then
		scanStatus()
	elseif verb == "rate" then
		local n = tonumber(a)
		if n and n >= 1 and n <= 200 then
			scanDB.scan.batch = math.max(1, math.floor(n * SCAN_TICK + 0.5))
			Lodestar:Say("Scan rate: about %d ids per second.", math.floor(scanDB.scan.batch / SCAN_TICK))
		else
			Lodestar:Say("Usage: /lode scan rate <ids per second, 1-200>")
		end
	elseif verb == "npc" then
		local e, kind, id = noteUnit("target", false)
		if not e then Lodestar:Say("Target a creature first.") return end
		Lodestar:Say("%s #%d (%s): level %s-%s, at %s %.1f,%.1f%s", e.name or "?", id, kind, tostring(e.minL), tostring(e.maxL),
			tostring(e.map), e.x or 0, e.y or 0, e.exact and " (exact)" or " (approx)")
	elseif verb == "wipe" then
		-- Only the census cursor. The harvest itself is behind /lode harvest wipe, with a backup.
		if a == "confirm" then
			if scanTicker then Guide:StopScan(false) end
			wipe(scanDB.scan)
			wipe(scanPending)
			scanPendingCount = 0
			Lodestar:Say("Quest census reset: the ids checked so far are forgotten and the next /lode scan quests starts over.")
			Lodestar:Say("Your harvested world data was NOT touched — that is /lode harvest wipe.")
		else
			Lodestar:Say("This resets the quest census cursor only (which ids have been checked), not the harvested world data.")
			Lodestar:Say("Type |cffffff7f/lode scan wipe confirm|r to reset the census. To delete the harvest itself: |cffffff7f/lode harvest wipe|r.")
		end
	else
		Lodestar:Say("Usage: /lode scan [status | quests <from> <to> | resume | retry | stop | rate <n> | npc | wipe confirm]")
	end
end

-- The harvest itself: /lode harvest ----------------------------------------------------------------------------

local function worldCounts(t)
	return count(t and t.quests), count(t and t.npcs), count(t and t.objects), count(t and t.taxi)
end

--- The wipe backup lives in the local-only DB (LodestarScanDB) so it never travels with a shared file.
backupSlot = function()
	local scan = Guide:ScanDB()
	local slot = scan and scan.backup
	return type(slot) == "table" and slot or nil
end

local function worldIsEmpty()
	for _, key in ipairs(WORLD_KEYS) do
		if next(db[key]) ~= nil then return false end
	end
	return true
end

--- Move the world tables into the single backup slot and leave fresh empty ones behind. The backup is
--- replaced, never appended to, so it is always "the harvest as it was just before the last wipe" —
--- except that wiping an already-empty harvest keeps the older backup rather than overwriting it with
--- nothing, so a second wipe cannot destroy what the first one saved.
local function stashAndWipe()
	local scan = Guide:ScanDB()
	local keep = worldIsEmpty() and scan.backup
	local backup = { at = time(), build = db.build }
	for _, key in ipairs(WORLD_KEYS) do
		backup[key] = db[key]
		db[key] = {}
	end
	if not keep then scan.backup = backup end
	return scan.backup
end

local function restoreBackup()
	local backup = backupSlot()
	if type(backup) ~= "table" then return nil end
	for _, key in ipairs(WORLD_KEYS) do
		local saved = backup[key]
		if type(saved) == "table" then
			local into = db[key]
			for k, v in pairs(saved) do if into[k] == nil then into[k] = v end end
		end
	end
	return backup
end

--- What is still missing on the map the player is standing on. The point of this is that mapping a
--- zone does NOT require talking to anyone: a nameplate fires for every creature you walk past, so
--- the scarce thing is not conversations, it is ground covered -- and this says which ground. The
--- positions those sightings carry are approximate (see NEAR_PASSIVE); an interaction upgrades one
--- to exact.
--- Returns: known, placed, unplaced (quests on this map with no position), nearNPCs, farNPCs.
function Guide:HarvestGaps(mapID)
	if not db then ensureDB() end
	mapID = mapID or C_Map.GetBestMapForUnit("player")
	local d = self.VanillaData
	local known, placed, unplaced = 0, 0, {}
	local nearNPCs, farNPCs = 0, 0
	for _, e in pairs(db.npcs or {}) do
		if e.map == mapID then
			if e.exact or (e.near or 0) >= 2 then nearNPCs = nearNPCs + 1 else farNPCs = farNPCs + 1 end
		end
	end
	-- A quest counts as "placed" when anything can point at it: a giver position from any source.
	for qid, q in pairs(db.quests or {}) do
		local onMap = (q.acceptAt and q.acceptAt.m == mapID) or (q.turninAt and q.turninAt.m == mapID)
		local giver = q.giver and q.giver.id
		local ge = giver and db.npcs[giver]
		if not onMap and ge and ge.map == mapID then onMap = true end
		if onMap or (q.spots and next(q.spots)) then
			known = known + 1
			local dq = d and d.quests[qid]
			local hasPos = (ge and ge.x ~= nil) or (dq and (dq.start or dq.acceptAt)) or (q.acceptAt ~= nil)
			if hasPos then
				placed = placed + 1
			else
				unplaced[#unplaced + 1] = { id = qid, t = q.t or (dq and dq.t), lvl = q.lvl or (dq and dq.lvl) }
			end
		end
	end
	table.sort(unplaced, function(a, b) return (a.lvl or 99) < (b.lvl or 99) end)
	return known, placed, unplaced, nearNPCs, farNPCs
end

local function handleHarvest(rest)
	if not db then ensureDB() end
	local verb, a = strsplit(" ", strtrim(rest or ""), 2)
	verb = (verb or ""):lower()
	a = (a or ""):lower()
	if verb == "" or verb == "status" then
		local sum = Guide:HarvestSummary()
		Lodestar:Say("Harvest: %d quests, %d NPCs (%d with an exact position), %d objects, %d flight nodes, %d levels, %d contributor%s.",
			sum.quests, sum.npcs, sum.positions, sum.objects, sum.taxi, sum.levels, sum.contributors, sum.contributors == 1 and "" or "s")
		if sum.backup then
			local slot = backupSlot()
			Lodestar:Say("  A backup from %s is kept: %d quests, %d NPCs, %d objects, %d flight nodes (/lode harvest restore).",
				date("%Y-%m-%d %H:%M", slot.at or time()), worldCounts(slot))
		end
		local b = Guide.lastBind
		if b then
			Lodestar:Say("  Load probe: at file load %s(%s), at ADDON_LOADED %s(%s), at bind %s(%s).",
				tostring(b.atFileLoad), tostring(b.atFileLoadQuests),
				tostring(b.atAddonLoaded), tostring(b.atAddonLoadedQuests),
				tostring(b.shareType), tostring(b.shareQuests))
			if b.shareQuests and b.shareQuests >= 0 then
				Lodestar:Say("  At login the saved file held %d quest(s); census cursor %s, trails %s.",
					b.shareQuests, b.scanHadCursor and "present" or "absent", b.scanHadTrails and "present" or "absent")
			else
				Lodestar:Say("  |cffff7f7fAt login the saved file was not there|r (share=%s, scan=%s) — the client did not load it, so last session's harvest was lost.",
					tostring(b.shareType), tostring(b.scanType))
			end
		end
		Lodestar:Say("  |cffffff7f/lode share|r tells you where the file is. |cffffff7f/lode harvest sync on|off|r shares new finds with your guild.")
	elseif verb == "gaps" or verb == "coverage" then
		local mapID = C_Map.GetBestMapForUnit("player")
		local known, placed, unplaced, nearNPCs, farNPCs = Guide:HarvestGaps(mapID)
		Lodestar:Say("%s: %d of %d quests here can be pointed at; %d NPCs pinned closely, %d only roughly.",
			Guide:MapName(mapID), placed, known, nearNPCs, farNPCs)
		if #unplaced == 0 then
			Lodestar:Say("  Nothing here is missing a position. Walk a zone with quests you have not mapped.")
		else
			Lodestar:Say("  %d still have nowhere to point. Walking within a few yards of their giver is enough -- you do not have to talk to anyone:", #unplaced)
			for i = 1, math.min(#unplaced, 10) do
				local u = unplaced[i]
				Lodestar:Say("    %s%s", u.t or ("Quest " .. u.id), u.lvl and (" |cff888888(lvl " .. u.lvl .. ")|r") or "")
			end
			if #unplaced > 10 then Lodestar:Say("    ... and %d more.", #unplaced - 10) end
		end
	elseif verb == "share" then
		if Guide.HarvestShareInfo then Guide:HarvestShareInfo() else Lodestar:Say("Sharing is not loaded.") end
	elseif verb == "sync" then
		if Guide.SetHarvestSync then
			Guide:SetHarvestSync(a)
		else
			Lodestar:Say("Live harvest sharing is not loaded.")
		end
	elseif verb == "wipe" then
		if a == "yes-really" then
			local before = { worldCounts(db) }
			stashAndWipe()
			Lodestar:Say("Harvest deleted: %d quests, %d NPCs, %d objects, %d flight nodes removed.", before[1], before[2], before[3], before[4])
			Lodestar:Say("A copy was stashed — |cffffff7f/lode harvest restore|r brings it back until the next wipe. The census cursor and your trails were not touched.")
		elseif a == "confirm" then
			local q, n, o, t = worldCounts(db)
			Lodestar:Say("This deletes the harvested world data: %d quests, %d NPCs, %d objects, %d flight nodes. Trails and the census cursor stay.", q, n, o, t)
			Lodestar:Say("A backup is kept on this computer (not in the shared data). To go ahead, type |cffffff7f/lode harvest wipe yes-really|r.")
		else
			Lodestar:Say("|cffffff7f/lode harvest wipe|r deletes everything this account has harvested about the world (quests, NPCs, objects, flight nodes, levels).")
			Lodestar:Say("It does not touch your trails or the quest census cursor (/lode trails wipe, /lode scan wipe). Type |cffffff7f/lode harvest wipe confirm|r to see the counts.")
		end
	elseif verb == "restore" then
		local backup = restoreBackup()
		if not backup then
			Lodestar:Say("No harvest backup to restore. One is made every time /lode harvest wipe runs.")
			return
		end
		local bq, bn, bo, bt = worldCounts(backup)
		local q, n, o, t = worldCounts(db)
		Lodestar:Say("Restored the backup from %s: %d quests, %d NPCs, %d objects, %d flight nodes merged back in.",
			date("%Y-%m-%d %H:%M", backup.at or time()), bq, bn, bo, bt)
		Lodestar:Say("The harvest now holds %d quests, %d NPCs, %d objects, %d flight nodes. /reload to write it to disk.", q, n, o, t)
	else
		Lodestar:Say("Usage: /lode harvest [status | share | sync on|off | wipe confirm | restore]")
		Lodestar:Say("  |cffffff7f/lode share|r — where the file is and what is in it.")
	end
end

-- Diagnostics ------------------------------------------------------------------------------------------------------

--- `/lode guide diag`: what the guide sees for every quest in the log, printed and saved to LodestarProbeDB.
function Guide:Diagnose()
	if not db then ensureDB() end
	local out = { when = date("%Y-%m-%d %H:%M:%S"), quests = {}, arrow = {}, smart = {} }
	local mapID = C_Map.GetBestMapForUnit("player")
	out.mapID = mapID
	local info = mapID and C_Map.GetMapInfo(mapID)
	out.mapName = info and info.name
	out.playerPos = { playerXY() }
	local pois = {}
	if mapID and C_QuestLog.GetQuestsOnMap then
		local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
		out.questsOnMapOK = ok
		out.questsOnMapErr = (not ok) and tostring(list) or nil
		if ok and type(list) == "table" then
			out.questsOnMap = #list
			for _, p in ipairs(list) do pois[p.questID or 0] = { p.x, p.y, p.type } end
		end
	end
	local sources = self:SmartSources()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local qi = C_QuestLog.GetInfo(i)
		if qi and not qi.isHeader and qi.questID then
			local qid = qi.questID
			local d = { title = qi.title, level = qi.level, complete = C_QuestLog.IsComplete(qid) and true or false, isOnMap = qi.isOnMap, hasLocalPOI = qi.hasLocalPOI, isHidden = qi.isHidden, isTask = qi.isTask }
			local ok, wmap, wx, wy = pcall(C_QuestLog.GetNextWaypoint, qid)
			d.nextWaypoint = ok and wmap and { wmap, wx, wy } or (ok and "nil" or ("error: " .. tostring(wmap)))
			if C_QuestLog.GetNextWaypointForMap and mapID then
				local ok2, fx, fy = pcall(C_QuestLog.GetNextWaypointForMap, qid, mapID)
				d.nextWaypointForMap = ok2 and fx and { fx, fy } or (ok2 and "nil" or ("error: " .. tostring(fx)))
			end
			local ok3, distSq, onCont = pcall(C_QuestLog.GetDistanceSqToQuest, qid)
			d.distSq = ok3 and distSq or ("error: " .. tostring(distSq))
			d.onContinent = ok3 and onCont or nil
			d.poi = pois[qid]
			d.source = sources[qid]
			local hmap, hx, hy, how = self:HarvestQuestPosition(qid, d.complete)
			d.harvest = hmap and { hmap, hx, hy, how } or nil
			out.quests[qid] = d
		end
	end
	local t = self:GetArrowTarget()
	local cfg = self.db.profile.arrow
	out.arrow = { mode = cfg.mode, show = cfg.show, frameShown = _G.LodestarArrow and _G.LodestarArrow:IsShown() or false,
		target = t and { kind = t.kind, title = t.title, mapID = t.mapID, x = t.x, y = t.y, continent = t.continent } or "none",
		facing = GetPlayerFacing and GetPlayerFacing() or nil, pos = cfg.pos }
	local items = self:CollectSmartItems(true)
	for i, it in ipairs(items) do
		if i > 12 then break end
		out.smart[i] = { kind = it.kind, title = it.title, dist = it.dist, source = it.source, noPosition = it.noPosition or nil }
	end
	out.guide = self.current and { name = self.current.name, step = self.stepIndex } or "smart mode"
	out.harvest = self:HarvestSummary()
	if type(_G.LodestarProbes) ~= "table" then _G.LodestarProbes = {} end
	_G.LodestarProbes.guideDiag = out

	Lodestar:Say("Guide diag — map %s (%s), %s, arrow target: %s", tostring(mapID), tostring(out.mapName), type(out.guide) == "table" and out.guide.name or out.guide, t and t.title or "none")
	local n = 0
	for qid, d in pairs(out.quests) do
		n = n + 1
		Lodestar:Say("  %d %s%s — waypoint: %s, poi: %s, harvest: %s, dist: %s", qid, d.title or "?", d.complete and " |cff7fff7f(complete)|r" or "",
			type(d.nextWaypoint) == "table" and "yes" or tostring(d.nextWaypoint), d.poi and "yes" or "no", d.harvest and d.harvest[4] or "no",
			type(d.distSq) == "number" and tostring(math.floor(math.sqrt(math.max(d.distSq, 0)))) or tostring(d.distSq))
	end
	Lodestar:Say("%d quests. Saved to LodestarProbes.guideDiag (written on /reload or logout).", n)
end

-- Lifecycle -------------------------------------------------------------------------------------------------------

function Guide:EnableHarvest()
	ensureDB()
	-- Once per game session, not once per module toggle: `sessions` is what weights a contribution.
	if not self.harvestContributed then
		self.harvestContributed = true
		noteContributor()
	end
	if not self.scanSlash then
		self.scanSlash = true
		Lodestar:RegisterSlashVerb("scan", handleScan, "quest census: /lode scan quests <from> <to>")
		Lodestar:RegisterSlashVerb("harvest", handleHarvest, "harvested world data: status, gaps, sync, wipe, restore")
	end
	-- Resume an interrupted census automatically -- but never one the user paused on purpose.
	local s = scanDB.scan
	if s.next and s.to and s.next <= s.to and not s.finishedAt and not s.paused then
		self:ScheduleTimer(function() if not scanTicker then self:StartScan() end end, 10)
	end
end

function Guide:DisableHarvest()
	if scanTicker then self:CancelTimer(scanTicker) scanTicker = nil end
end

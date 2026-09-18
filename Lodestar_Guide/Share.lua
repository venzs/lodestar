-- Lodestar_Guide: sharing the harvest.
--
-- Two ways the world data leaves this client, both opt-outable with `harvest.share`:
--
--   the file    `/lode share` says where LodestarShareDB is written (WTF\Account\<ACCOUNT>\
--               SavedVariables\Lodestar_Guide.lua), what is in it and that SavedVariables only reach
--               the disk on /reload or logout. Sending that one file is how a contributor's harvest
--               gets to tools/pfquest/merge_scan.py.
--
--   live deltas a "H" message on the shared addon channel (Lodestar/Core/Comm.lua) carrying only
--               facts this client just learned first-hand:
--                   n = { { npcID, mapID, x, y, name }, … }   exact (interaction) NPC positions
--                   q = { { questID, giverNpcID, enderNpcID }, … }
--                   f = { { nodeID, mapID, x, y, name }, … }  flight points
--               At most one message every 15 s, at most 4 NPCs + 4 quests + 2 flight points in it,
--               to GUILD and to the party/raid. Nothing that arrived over the channel is ever
--               forwarded (entries are marked `via = "comm"` and skipped when queueing), so a bad
--               actor cannot get the guild to amplify anything. Incoming rows are untrusted: ids,
--               maps, coordinates and names are range-checked and anything odd is dropped in silence,
--               and a delta never overwrites a position this client saw for itself.
--
-- The whole delta path is dormant while the realm restricts addon messages (the Forever beta does,
-- realm-wide): nothing is sent, the ticker does not run, and Lodestar:OnCommAvailabilityChanged(true)
-- starts it without a reload.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local SEND_INTERVAL = 15       -- seconds between deltas, at the very most
local MAX_NPC, MAX_QUEST, MAX_TAXI = 4, 4, 2   -- rows of each kind in one message
local QUEUE_MAX = 150          -- facts held while comms are restricted
local MAX_ID = 5000000         -- sanity bound for npc / quest / node ids
local MAX_MAP = 10000          -- sanity bound for uiMapIDs
local MAX_NAME = 48            -- characters of a creature/node name we will carry or accept

local BUCKETS = { { "n", MAX_NPC }, { "q", MAX_QUEST }, { "f", MAX_TAXI } }

local pending = { n = {}, q = {}, f = {} }    -- [id] = row waiting to go out
local sentKeys = { n = {}, q = {}, f = {} }   -- [id] = the row we last sent, so nothing repeats
local pendingCount = 0
local syncTicker
local lastSent = -1e9
local received, dropped = 0, 0

local function sharing()
	local p = Guide.db and Guide.db.profile.harvest
	return not p or p.share ~= false
end

local function shortName(v)
	if type(v) ~= "string" or v == "" then return nil end
	if #v > MAX_NAME then return nil end
	return v
end

local function rowKey(row)
	return tostring(row[2]) .. ":" .. tostring(row[3]) .. ":" .. tostring(row[4])
end

-- Outgoing ----------------------------------------------------------------------------------------

--- Harvest.lua calls this whenever it learns a fact worth passing on. Cheap and allocation-light: a
--- fact already queued or already sent unchanged costs one table lookup and returns.
function Guide:QueueHarvestDelta(kind, id, entry)
	if type(id) ~= "number" or id <= 0 or id > MAX_ID then return end
	if type(entry) ~= "table" or entry.via == "comm" then return end   -- never relay second-hand data
	if not sharing() then return end
	local bucket, row
	if kind == "npc" then
		if not (entry.exact and entry.map and entry.x and entry.y) then return end
		bucket, row = "n", { id, entry.map, entry.x, entry.y, shortName(entry.name) }
	elseif kind == "quest" then
		local giver = type(entry.giver) == "number" and entry.giver or 0
		local ender = type(entry.ender) == "number" and entry.ender or 0
		if giver == 0 and ender == 0 then return end
		bucket, row = "q", { id, giver, ender }
	elseif kind == "taxi" then
		if not (entry.map and entry.x and entry.y) then return end
		bucket, row = "f", { id, entry.map, entry.x, entry.y, shortName(entry.name) }
	else
		return
	end
	local key = rowKey(row)
	if sentKeys[bucket][id] == key then return end
	if pending[bucket][id] == nil then
		if pendingCount >= QUEUE_MAX then return end
		pendingCount = pendingCount + 1
	end
	pending[bucket][id] = row
end

local function buildDelta()
	local msg, taken, any = { t = "H" }, {}, false
	for _, b in ipairs(BUCKETS) do
		local bucket, limit = b[1], b[2]
		local rows, ids, n = {}, {}, 0
		for id, row in pairs(pending[bucket]) do
			if n >= limit then break end
			n = n + 1
			rows[n], ids[n] = row, id
		end
		if n > 0 then
			msg[bucket] = rows
			taken[bucket] = ids
			any = true
		end
	end
	if not any then return nil end
	return msg, taken
end

--- Send one delta if there is anything to send, comms allow it and the interval has passed.
--- Returns true when a message actually left the client.
function Guide:FlushHarvestDelta()
	if not self:IsEnabled() or not sharing() then return false end
	if not Lodestar:CanSendComm() then return false end
	if (GetTime() - lastSent) < SEND_INTERVAL then return false end
	local msg, taken = buildDelta()
	if not msg then return false end
	local sent = false
	if IsInGuild() and Lodestar:SendComm(msg, "GUILD", nil, "BULK") then sent = true end
	if IsInRaid() then
		if Lodestar:SendComm(msg, "RAID", nil, "BULK") then sent = true end
	elseif IsInGroup() then
		if Lodestar:SendComm(msg, "PARTY", nil, "BULK") then sent = true end
	end
	if not sent then return false end
	lastSent = GetTime()
	for bucket, ids in pairs(taken) do
		for _, id in ipairs(ids) do
			local row = pending[bucket][id]
			if row then
				sentKeys[bucket][id] = rowKey(row)
				pending[bucket][id] = nil
				pendingCount = pendingCount - 1
			end
		end
	end
	return true
end

-- Incoming ----------------------------------------------------------------------------------------

local function id(v)
	if type(v) ~= "number" or v ~= v or v < 1 or v > MAX_ID or v ~= math.floor(v) then return nil end
	return v
end

local function mapID(v)
	if type(v) ~= "number" or v ~= v or v < 1 or v > MAX_MAP or v ~= math.floor(v) then return nil end
	return v
end

local function coord(v)
	if type(v) ~= "number" or v ~= v or v < 0 or v > 100 then return nil end
	return math.floor(v * 10 + 0.5) / 10
end

--- A delta from another player. Everything in it is untrusted input: every field is range-checked,
--- a row that fails any check is dropped without a word, and a fact we already know first-hand wins.
local function onDelta(sender, msg)
	if not Guide:IsEnabled() or not sharing() then return end
	if type(msg) ~= "table" then return end
	local db = Guide:HarvestDB()
	local rows = type(msg.n) == "table" and msg.n or nil
	if rows then
		for i = 1, math.min(#rows, MAX_NPC) do
			local r = rows[i]
			local nid = type(r) == "table" and id(r[1]) or nil
			local m, x, y = nid and mapID(r[2]), nid and coord(r[3]), nid and coord(r[4])
			if nid and m and x and y then
				local e = db.npcs[nid]
				if not e then
					e = { seen = 0 }
					db.npcs[nid] = e
				end
				if not e.exact then
					e.map, e.x, e.y, e.exact, e.via = m, x, y, true, "comm"
					local nm = shortName(r[5])
					if nm and (not e.name or e.name == "") then e.name = nm end
					received = received + 1
				end
			else
				dropped = dropped + 1
			end
		end
	end
	rows = type(msg.q) == "table" and msg.q or nil
	if rows then
		for i = 1, math.min(#rows, MAX_QUEST) do
			local r = rows[i]
			local qid = type(r) == "table" and id(r[1]) or nil
			if qid then
				local giver, ender = id(r[2]), id(r[3])
				if giver or ender then
					local q = db.quests[qid]
					if not q then
						q = {}
						db.quests[qid] = q
					end
					local took = false
					if giver and not q.giver then q.giver, took = giver, true end
					if ender and not q.ender then q.ender, took = ender, true end
					if took then
						q.via = "comm"
						received = received + 1
					end
				else
					dropped = dropped + 1
				end
			else
				dropped = dropped + 1
			end
		end
	end
	rows = type(msg.f) == "table" and msg.f or nil
	if rows then
		for i = 1, math.min(#rows, MAX_TAXI) do
			local r = rows[i]
			local nid = type(r) == "table" and id(r[1]) or nil
			local m, x, y = nid and mapID(r[2]), nid and coord(r[3]), nid and coord(r[4])
			if nid and m and x and y then
				local t = db.taxi[nid]
				if not t then
					t = {}
					db.taxi[nid] = t
				end
				if not t.map then
					t.map, t.x, t.y, t.via = m, x, y, "comm"
					t.state = t.state or "reachable"
					local nm = shortName(r[5])
					if nm and not t.name then t.name = nm end
					received = received + 1
				end
			else
				dropped = dropped + 1
			end
		end
	end
	Lodestar:Debug("harvest delta from %s: %d merged, %d dropped in total", tostring(sender), received, dropped)
end

--- Counters for the smoke test and /lode harvest status.
function Guide:HarvestSyncStats()
	return { queued = pendingCount, received = received, dropped = dropped, running = syncTicker ~= nil, on = sharing() }
end

-- Lifecycle ----------------------------------------------------------------------------------------

function Guide:StartHarvestSync()
	if syncTicker or not sharing() then return end
	if not Lodestar:CanSendComm() then return end
	syncTicker = self:ScheduleRepeatingTimer(function() self:FlushHarvestDelta() end, SEND_INTERVAL)
end

function Guide:StopHarvestSync()
	if syncTicker then
		self:CancelTimer(syncTicker)
		syncTicker = nil
	end
end

--- Core callback (Lodestar:OnCommAvailabilityChanged fans out to every enabled module). The delta
--- path is dormant on a restricted realm and lights up here, without a reload.
function Guide:OnCommAvailabilityChanged(available)
	if available then self:StartHarvestSync() else self:StopHarvestSync() end
end

function Guide:SetHarvestSync(arg)
	local p = self.db.profile
	p.harvest = p.harvest or {}
	arg = (arg or ""):lower()
	if arg == "on" then
		p.harvest.share = true
	elseif arg == "off" then
		p.harvest.share = false
	elseif arg == "" then
		p.harvest.share = not sharing()
	else
		Lodestar:Say("Usage: /lode harvest sync on|off")
		return
	end
	if sharing() then
		self:StartHarvestSync()
		if Lodestar:CanSendComm() then
			Lodestar:Say("Harvest sync on: NPC positions, quest givers and flight points you find are offered to your guild and party, at most one small message every %d seconds.", SEND_INTERVAL)
		else
			Lodestar:Say("Harvest sync on — but addon messages are restricted on this realm, so nothing is sent until that changes.")
		end
	else
		self:StopHarvestSync()
		Lodestar:Say("Harvest sync off: nothing about your harvest leaves this client. |cffffff7f/lode share|r still tells you where the file is.")
	end
end

-- The file ------------------------------------------------------------------------------------------

--- `/lode share`: where the harvest lives on disk and what is in it.
function Guide:HarvestShareInfo()
	local sum = self:HarvestSummary()
	local _, build = GetBuildInfo()
	Lodestar:Say("Your harvest is one file inside the World of Warcraft folder:")
	Lodestar:Say("  |cffffffffWTF\\Account\\<ACCOUNT>\\SavedVariables\\Lodestar_Guide.lua|r")
	Lodestar:Say("  |cff999999<ACCOUNT> is your account's folder — the client does not tell addons its name. It is the one folder under WTF\\Account that is not 'SavedVariables', usually your login in capitals.|r")
	Lodestar:Say("In it: |cffffffff%d|r quests, |cffffffff%d|r NPCs (%d with an exact position), |cffffffff%d|r objects, |cffffffff%d|r flight nodes, |cffffffff%d|r level XP values, from |cffffffff%d|r contributor%s. Client build %s.",
		sum.quests, sum.npcs, sum.positions, sum.objects, sum.taxi, sum.levels, sum.contributors, sum.contributors == 1 and "" or "s", tostring(build))
	Lodestar:Say("|cffff9933Type /reload first|r — SavedVariables are only written to disk on /reload or logout, so a copy taken before that is stale.")
	Lodestar:Say("Then send that one file. |cffffff7f/lode harvest|r shows the same counts; |cffffff7f/lode harvest restore|r undoes an accidental wipe.")
end

function Guide:EnableShare()
	Lodestar:RegisterCommHandler("H", onDelta)
	if not self.shareSlash then
		self.shareSlash = true
		Lodestar:RegisterSlashVerb("share", function() self:HarvestShareInfo() end, "where your harvested world data is saved, and what is in it")
		Lodestar:RegisterTooltipProvider(function(tooltip)
			if not self:IsEnabled() then return end
			local sum = self:HarvestSummary()
			tooltip:AddDoubleLine("Harvested world data", ("%d quests · %d NPCs · %d flight points"):format(sum.quests, sum.npcs, sum.taxi), 1, 0.82, 0, 1, 1, 1)
		end)
	end
	self:StartHarvestSync()
end

function Guide:DisableShare()
	Lodestar:RegisterCommHandler("H", nil)
	self:StopHarvestSync()
end

-- Options (merged into the Guide settings page; Guide.lua holds the defaults) --------------------------

if type(Guide.options) == "table" then
	Guide.options.harvestHeader = { type = "header", order = 50, name = "Harvested world data" }
	Guide.options.harvestDesc = {
		type = "description", order = 51, fontSize = "medium",
		name = function()
			local sum = Guide:HarvestSummary()
			return ("Forever gives addons no quest positions, so everything the arrow knows about new quests comes from what you meet while playing. You have |cffffffff%d|r quests, |cffffffff%d|r NPCs (%d with an exact position), |cffffffff%d|r objects and |cffffffff%d|r flight points, from %d contributor%s.\n|cffffff7f/lode share|r says where the file is so you can send it; |cffffff7f/lode harvest restore|r undoes an accidental wipe.\n")
				:format(sum.quests, sum.npcs, sum.positions, sum.objects, sum.taxi, sum.contributors, sum.contributors == 1 and "" or "s")
		end,
	}
	Guide.options.harvestShare = {
		type = "toggle", order = 52, name = "Share new finds with guild and party",
		desc = "Sends a tiny addon message (at most one every 15 seconds) with NPC positions, quest givers and flight points you have just found, and merges the ones other Lodestar players send you. Nothing anyone else sent is ever passed on. Dormant on realms that restrict addon messages.",
		get = function() return sharing() end,
		set = function(_, v)
			local p = Guide.db.profile
			p.harvest = p.harvest or {}
			p.harvest.share = v
			if v then Guide:StartHarvestSync() else Guide:StopHarvestSync() end
		end,
	}
end

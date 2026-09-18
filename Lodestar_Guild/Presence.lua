-- Lodestar_Guild: presence sharing over the guild addon channel.
--
-- Messages (see Lodestar/Core/Comm.lua for the envelope):
--   P  presence  { l = level, z = zone, s = subzone, x = xp%, m = mapID, c = classFile, n = lfg note }
--   Q  query     "send me your presence" — answered with a P after a short random delay
local Lodestar = _G.Lodestar
local Guild = Lodestar:GetModule("Guild")

Guild.presence = {}   -- [shortName] = { l, z, s, x, m, c, n, v = version, t = GetTime() of last update }

local lastSent = {}

local function ownState()
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	return {
		t = "P",
		l = UnitLevel("player"),
		z = GetRealZoneText() or "",
		s = GetSubZoneText() or "",
		x = xpMax > 0 and math.floor(xp / xpMax * 100) or 0,
		m = C_Map.GetBestMapForUnit("player"),
		c = Lodestar.player.class,
		n = Guild.db.char.lfgNote,
	}
end

local function stateChanged(state)
	for k, v in pairs(state) do
		if k ~= "x" and lastSent[k] ~= v then return true end
	end
	return math.abs((state.x or 0) - (lastSent.x or 0)) >= 10
end

function Guild:Broadcast(force)
	if not self.db.profile.share or not IsInGuild() then return end
	local state = ownState()
	if not force and not stateChanged(state) then return end
	if Lodestar:SendComm(state, "GUILD", nil, "BULK") then
		lastSent = state
	end
end

function Guild:Query()
	if not IsInGuild() then return end
	Lodestar:SendComm({ t = "Q" }, "GUILD", nil, "BULK")
end

-- Incoming ------------------------------------------------------------------------------

local function onPresence(sender, msg)
	local name = Lodestar.ShortName(sender)
	local prev = Guild.presence[name]
	local entry = {
		l = tonumber(msg.l), z = msg.z, s = msg.s, x = tonumber(msg.x), m = tonumber(msg.m), c = msg.c, n = msg.n,
		v = msg.v, t = GetTime(),
	}
	Guild.presence[name] = entry
	if prev then
		local notify = Guild.db.profile.notify
		if notify.levelUps and entry.l and prev.l and entry.l > prev.l then
			Lodestar:Msg("%s reached level %d!", Lodestar.ClassColorText(name, entry.c), entry.l)
		end
		if notify.lfg and entry.n and entry.n ~= "" and entry.n ~= prev.n then
			Lodestar:Msg("%s is looking for: %s", Lodestar.ClassColorText(name, entry.c), entry.n)
		end
	elseif Guild.db.profile.notify.lfg and entry.n and entry.n ~= "" then
		Lodestar:Msg("%s is looking for: %s", Lodestar.ClassColorText(name, entry.c), entry.n)
	end
	Guild:RefreshBoard()
end

local function onQuery()
	-- Spread replies so a big guild doesn't burst the channel.
	Guild:ScheduleTimer(function() Guild:Broadcast(true) end, math.random() * 4)
end

-- LFG note -------------------------------------------------------------------------------

function Guild:SetLFGNote(text)
	text = strtrim(text or "")
	if text == "" or text:lower() == "clear" or text:lower() == "off" then
		self.db.char.lfgNote = nil
		Lodestar:Say("Group request cleared.")
	else
		if #text > 80 then text = text:sub(1, 80) end
		self.db.char.lfgNote = text
		Lodestar:Say("Group request set: %s", text)
	end
	self:Broadcast(true)
	self:RefreshBoard()
end

-- Lifecycle ---------------------------------------------------------------------------------

function Guild:RestartHeartbeat()
	if self.heartbeat then self:CancelTimer(self.heartbeat) end
	local minutes = math.max(1, self.db.profile.heartbeatMinutes or 5)
	self.heartbeat = self:ScheduleRepeatingTimer(function() self:Broadcast(true) end, minutes * 60)
end

function Guild:EnablePresence()
	Lodestar:RegisterCommHandler("P", onPresence)
	Lodestar:RegisterCommHandler("Q", onQuery)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnStateEvent")
	self:RegisterEvent("PLAYER_LEVEL_UP", "OnStateEvent")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnStateEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RestartHeartbeat()
	if not self.lfgSlash then
		self.lfgSlash = true
		Lodestar:RegisterSlashVerb("lfg", function(rest) self:SetLFGNote(rest) end, "post what you're looking for to the guild board")
	end
	-- Announce ourselves and ask who else is around.
	self:ScheduleTimer(function() self:Broadcast(true) self:Query() end, 10)
end

function Guild:OnStateEvent()
	self:ScheduleTimer(function() self:Broadcast() end, 2)
end

function Guild:OnEnteringWorld(_, isLogin, isReload)
	if isLogin or isReload then return end -- the enable-time timer covers the first send
	self:OnStateEvent()
end

function Guild:DisablePresence()
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:UnregisterEvent("PLAYER_GUILD_UPDATE")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if self.heartbeat then self:CancelTimer(self.heartbeat) self.heartbeat = nil end
end

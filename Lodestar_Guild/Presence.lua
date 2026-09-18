-- Lodestar_Guild: presence sharing over the guild addon channel.
--
-- Messages (see Lodestar/Core/Comm.lua for the envelope):
--   P  presence  { l = level, z = zone, s = subzone, x = xp%, m = mapID, c = classFile, n = lfg note }
--   Q  query     "send me your presence" — answered with a P after a short random delay
local Lodestar = _G.Lodestar
local Guild = Lodestar:GetModule("Guild")

Guild.presence = {}   -- [shortName] = { l, z, s, x, m, c, n, v = version, t = GetTime() of last update }

local QUERY_INTERVAL = 60 -- seconds between guild-wide "who's here" queries

local lastSent = {}
local lastQuery = 0
local pendingReplies = {} -- [sender] = true: queriers waiting for our presence

--- True while addon messages are silently dropped (instances, PvP, encounters): sending would
--- only burn throttle budget and wrongly mark the state as delivered.
local function chatLocked()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

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
	if not self.db.profile.share or not IsInGuild() or chatLocked() then return end
	local state = ownState()
	if not force and not stateChanged(state) then return end
	-- Only remember the state as sent when it actually left the client.
	if Lodestar:SendComm(state, "GUILD", nil, "BULK") then
		lastSent = state
	end
end

function Guild:Query()
	if not IsInGuild() or chatLocked() then return end
	-- Every Q costs each Lodestar guildmate a reply; opening and closing the board must not re-ask.
	if GetTime() - lastQuery < QUERY_INTERVAL then return end
	if Lodestar:SendComm({ t = "Q" }, "GUILD", nil, "BULK") then
		lastQuery = GetTime()
	end
end

-- Incoming ------------------------------------------------------------------------------

local function onPresence(sender, msg)
	if not Guild:IsEnabled() then return end
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

--- Whisper our presence to everyone who asked since the last reply. One timer covers every Q in the
--- window, and the answer goes only to the querier: a guild-wide reply per Q is O(N^2) traffic at login.
local function sendReplies()
	Guild.replyTimer = nil
	local recipients = pendingReplies
	pendingReplies = {}
	if not Guild:IsEnabled() or not Guild.db.profile.share or not IsInGuild() or chatLocked() then return end
	local state = ownState()
	for target in pairs(recipients) do
		Lodestar:SendComm(state, "WHISPER", target, "BULK")
	end
end

local function onQuery(sender)
	if not Guild:IsEnabled() or type(sender) ~= "string" then return end
	pendingReplies[sender] = true
	if Guild.replyTimer then return end
	-- Spread replies so a big guild doesn't burst the channel.
	Guild.replyTimer = Guild:ScheduleTimer(sendReplies, 1 + math.random() * 4)
end

-- LFG note -------------------------------------------------------------------------------

function Guild:SetLFGNote(text)
	if not self:IsEnabled() then
		Lodestar:Say("The Guild module is disabled.")
		return
	end
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
	self.currentGuild = GetGuildInfo("player")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnStateEvent")
	self:RegisterEvent("PLAYER_LEVEL_UP", "OnStateEvent")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnGuildUpdate")
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

--- Joining or leaving a guild: the old guild's presence is meaningless and the new one has never
--- heard of us. Also covers login, where guild info can arrive after the module enabled.
function Guild:OnGuildUpdate(_, unit)
	if unit and unit ~= "player" then return end
	local guild = GetGuildInfo("player")
	if guild == self.currentGuild then return end
	self.currentGuild = guild
	wipe(self.presence)
	wipe(pendingReplies)
	lastSent = {}
	lastQuery = 0
	if guild then
		self:ScheduleTimer(function() self:Broadcast(true) self:Query() end, 2)
	end
	self:RefreshBoard()
end

function Guild:DisablePresence()
	Lodestar:RegisterCommHandler("P", nil)
	Lodestar:RegisterCommHandler("Q", nil)
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:UnregisterEvent("PLAYER_GUILD_UPDATE")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if self.heartbeat then self:CancelTimer(self.heartbeat) self.heartbeat = nil end
	if self.replyTimer then self:CancelTimer(self.replyTimer) self.replyTimer = nil end
	wipe(pendingReplies)
end

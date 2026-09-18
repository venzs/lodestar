-- Lodestar_Guild: presence sharing over the guild addon channel.
--
-- Messages (see Lodestar/Core/Comm.lua for the envelope):
--   P  presence  { l = level, z = zone, s = subzone, x = xp%, m = mapID, c = classFile, n = lfg note }
--   Q  query     "send me your presence" — answered with a P after a short random delay
--
-- Without addon comms (the Forever beta restricts them realm-wide) nothing here can be delivered:
-- the heartbeat stays off, the board shows the C_Club roster alone, and /lode lfg drafts a guild
-- chat line for the player to send instead of broadcasting. Lodestar:OnCommAvailabilityChanged
-- turns the sharing back on when a realm allows it.
local Lodestar = _G.Lodestar
local Guild = Lodestar:GetModule("Guild")

Guild.presence = {}   -- [shortName] = { l, z, s, x, m, c, n, v = version, t = GetTime() of last update }

local QUERY_INTERVAL = 60 -- seconds between guild-wide "who's here" queries
local LFG_MAX = 80

local lastSent = {}
local lastQuery = 0
local pendingReplies = {} -- [sender] = true: queriers waiting for our presence

--- True while addon messages can actually leave the client (realm restriction and the situational
--- chat lockdown both make SendAddonMessage fail); sending otherwise would only burn throttle budget
--- and wrongly mark the state as delivered.
function Guild:CommsAvailable()
	return Lodestar:CanSendComm()
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
	if not self.db.profile.share or not IsInGuild() or not self:CommsAvailable() then return end
	local state = ownState()
	if not force and not stateChanged(state) then return end
	-- Only remember the state as sent when it actually left the client.
	if Lodestar:SendComm(state, "GUILD", nil, "BULK") then
		lastSent = state
	end
end

function Guild:Query()
	if not IsInGuild() or not self:CommsAvailable() then return end
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
	if not Guild:IsEnabled() or not Guild.db.profile.share or not IsInGuild() or not Guild:CommsAvailable() then return end
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

--- Put text into the chat edit box for the player to send. Never sends by itself: automating
--- guild chat is exactly what the realm restriction is there to stop.
function Guild:DraftChat(text)
	local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
	if not open then return false end
	open(text, DEFAULT_CHAT_FRAME)
	return true
end

function Guild:SetLFGNote(text)
	if not self:IsEnabled() then
		Lodestar:Say("The Guild module is disabled.")
		return
	end
	text = strtrim(text or "")
	if text == "" or text:lower() == "clear" or text:lower() == "off" then
		self.db.char.lfgNote = nil
		Lodestar:Say("Group request cleared.")
		self:Broadcast(true)
		self:RefreshBoard()
		return
	end
	if #text > LFG_MAX then text = text:sub(1, LFG_MAX) end
	self.db.char.lfgNote = text
	if self:CommsAvailable() then
		Lodestar:Say("Group request set: %s", text)
		self:Broadcast(true)
	elseif self:DraftChat("/g LFG: " .. text) then
		Lodestar:Say("Addon messages are restricted on this realm — your request is in the chat box, press Enter to send it to the guild.")
	else
		Lodestar:Say("Addon messages are restricted on this realm; post it in guild chat: /g LFG: %s", text)
	end
	self:RefreshBoard()
end

-- Lifecycle ---------------------------------------------------------------------------------

--- (Re)start the periodic presence broadcast. Without comms there is nothing to send, so the timer
--- stays off rather than ticking into SendComm's refusal every few minutes.
function Guild:RestartHeartbeat()
	if self.heartbeat then self:CancelTimer(self.heartbeat) self.heartbeat = nil end
	if not self:CommsAvailable() then return end
	local minutes = math.max(1, self.db.profile.heartbeatMinutes or 5)
	self.heartbeat = self:ScheduleRepeatingTimer(function() self:Broadcast(true) end, minutes * 60)
end

--- Announce ourselves and ask who else is around, once, `delay` seconds from now.
function Guild:ScheduleAnnounce(delay)
	if self.announceTimer then self:CancelTimer(self.announceTimer) end
	self.announceTimer = self:ScheduleTimer(function()
		self.announceTimer = nil
		self:Broadcast(true)
		self:Query()
	end, delay)
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
	if self:CommsAvailable() then self:ScheduleAnnounce(10) end
end

--- Core callback: comms came back (a launch realm without the restriction, or leaving an instance)
--- or went away. Coming back, the guild has never heard of us: announce and ask again.
function Guild:OnCommAvailabilityChanged(available)
	if available then
		lastSent = {}
		lastQuery = 0
		self:RestartHeartbeat()
		if IsInGuild() then self:ScheduleAnnounce(2) end
	else
		if self.heartbeat then self:CancelTimer(self.heartbeat) self.heartbeat = nil end
		if self.announceTimer then self:CancelTimer(self.announceTimer) self.announceTimer = nil end
		if self.replyTimer then self:CancelTimer(self.replyTimer) self.replyTimer = nil end
		wipe(pendingReplies)
	end
	self:RefreshBoard()
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
	if guild and self:CommsAvailable() then self:ScheduleAnnounce(2) end
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
	if self.announceTimer then self:CancelTimer(self.announceTimer) self.announceTimer = nil end
	if self.replyTimer then self:CancelTimer(self.replyTimer) self.replyTimer = nil end
	wipe(pendingReplies)
end

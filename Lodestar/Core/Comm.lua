-- Lodestar core: addon-channel messaging shared by the suite.
--
-- Every message is a serialized table with a one-letter type in .t. Modules register
-- handlers with Lodestar:RegisterCommHandler("P", function(sender, msg, distribution) end).
-- The core owns "V" (version announce).
--
-- Availability: the Forever beta realm restricts outgoing addon messages everywhere
-- (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() == true, SendAddonMessage answers
-- AddOnMessageLockdown), and instances/PvP/encounters add the situational chat lockdown. Both
-- make CanSendComm() false; modules that talk over the channel fall back to whatever works without
-- it and get Lodestar:OnCommAvailabilityChanged(available) when the state flips.
local Lodestar = _G.Lodestar
local L = Lodestar.L

local handlers = {}

function Lodestar:SetupComm()
	self:RegisterComm(self.COMM_PREFIX, "OnCommReceived")
	self.commAvailable = self:CanSendComm()
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionStateChanged")
end

function Lodestar:RegisterCommHandler(msgType, fn)
	handlers[msgType] = fn
end

--- True when the client currently lets addons talk on addon channels: neither the realm-wide
--- restriction nor the situational chat-messaging lockdown is in effect.
function Lodestar:CanSendComm()
	if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
		return false
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return false
	end
	return true
end

--- Re-read the restriction state and notify modules when it differs from what they last heard.
--- Accurate outside ADDON_RESTRICTION_STATE_CHANGED dispatch; see OnRestrictionStateChanged.
function Lodestar:CheckCommAvailability()
	local available = self:CanSendComm()
	if available == self.commAvailable then return end
	self.commAvailable = available
	self:OnCommAvailabilityChanged(available)
end

--- ADDON_RESTRICTION_STATE_CHANGED fires BEFORE a restriction becomes active (payload state ==
--- Activating) and only AFTER one is lifted. For the whole of that dispatch every "is it active?"
--- query still answers no -- Blizzard documents this for IsAddOnRestrictionActive, and
--- C_ChatInfo.InChatMessagingLockdown() reports the same not-yet-enforced restriction. So the
--- activating edge has to come from the payload; anything else is safe to re-read once dispatch
--- has finished.
function Lodestar:OnRestrictionStateChanged(_, restrictionType, state)
	local types = Enum and Enum.AddOnRestrictionType
	local states = Enum and Enum.AddOnRestrictionState
	if types and states and restrictionType == types.Chat and state == states.Activating then
		if self.commAvailable then
			self.commAvailable = false
			self:OnCommAvailabilityChanged(false)
		end
		return
	end
	self:ScheduleTimer("CheckCommAvailability", 0) -- next frame: the queries only tell the truth after dispatch
end

--- Fan-out for availability changes. Modules implement M:OnCommAvailabilityChanged(available) (the
--- Guild module re-announces and re-queries when comms come back); anything else can hook this method.
function Lodestar:OnCommAvailabilityChanged(available)
	self:Debug("addon comms %s", available and "available" or "restricted")
	for _, module in ipairs(self.moduleList or {}) do
		if module.OnCommAvailabilityChanged and module:IsEnabled() then
			local ok, err = pcall(module.OnCommAvailabilityChanged, module, available)
			if not ok then self:Debug("%s OnCommAvailabilityChanged failed: %s", tostring(module.key), tostring(err)) end
		end
	end
end

--- Send a table to a distribution ("GUILD", "PARTY", "RAID", "WHISPER" with target).
--- Returns false, without queueing anything, while comms are unavailable.
function Lodestar:SendComm(msg, distribution, target, prio)
	if not self:CanSendComm() then return false end
	msg.v = msg.v or self.version
	local payload = self:Serialize(msg)
	self:SendCommMessage(self.COMM_PREFIX, payload, distribution, target, prio or "NORMAL")
	return true
end

function Lodestar:OnCommReceived(prefix, payload, distribution, sender)
	if prefix ~= self.COMM_PREFIX then return end
	local ok, msg = self:Deserialize(payload)
	if not ok or type(msg) ~= "table" or type(msg.t) ~= "string" then return end
	if sender == self.player.name or sender == self.player.fullName then return end
	self:CheckRemoteVersion(msg.v, sender)
	local handler = handlers[msg.t]
	if handler then
		local good, err = pcall(handler, sender, msg, distribution)
		if not good then self:Debug("comm handler %s failed: %s", msg.t, tostring(err)) end
	end
end

-- Version announce ----------------------------------------------------------------

--- Silently does nothing while comms are unavailable: SendComm refuses without queueing.
function Lodestar:BroadcastVersion()
	if not self:CanSendComm() then return end
	local msg = { t = "V" }
	if IsInGuild() then self:SendComm(msg, "GUILD", nil, "BULK") end
	if IsInRaid() then
		self:SendComm(msg, "RAID", nil, "BULK")
	elseif IsInGroup() then
		self:SendComm(msg, "PARTY", nil, "BULK")
	end
end

function Lodestar:CheckRemoteVersion(remote, sender)
	if type(remote) ~= "string" or self.versionNoticeShown then return end
	if not self.db.profile.versionNotices then return end
	if self.version == "dev" or remote == "dev" then return end -- unpackaged builds are not comparable
	if self.CompareVersions(remote, self.version) > 0 then
		self.versionNoticeShown = true
		self:Say(L["A newer Lodestar (%s) is available — you have %s."], remote, self.version)
		self:Debug("newer version seen from %s", tostring(sender))
	end
end

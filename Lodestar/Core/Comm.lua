-- Lodestar core: addon-channel messaging shared by the suite.
--
-- Every message is a serialized table with a one-letter type in .t. Modules register
-- handlers with Lodestar:RegisterCommHandler("P", function(sender, msg, distribution) end).
-- The core owns "V" (version announce).
local Lodestar = _G.Lodestar
local L = Lodestar.L

local handlers = {}

function Lodestar:SetupComm()
	self:RegisterComm(self.COMM_PREFIX, "OnCommReceived")
end

function Lodestar:RegisterCommHandler(msgType, fn)
	handlers[msgType] = fn
end

--- True when the client currently lets addons talk on addon channels.
function Lodestar:CanSendComm()
	if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
		return false
	end
	return true
end

--- Send a table to a distribution ("GUILD", "PARTY", "RAID", "WHISPER" with target).
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

function Lodestar:BroadcastVersion()
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
	if self.version == "dev" then return end
	if self.CompareVersions(remote, self.version) > 0 then
		self.versionNoticeShown = true
		self:Say(L["A newer Lodestar (%s) is available — you have %s."], remote, self.version)
		self:Debug("newer version seen from %s", tostring(sender))
	end
end

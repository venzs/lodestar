-- Lodestar core: error visibility on a client with no BugSack yet.
--
-- 12.x keeps every Lua error in ScriptErrorsFrame.errorData (even with the scriptErrors CVar off)
-- and only lets secure code install error handlers, so we never touch seterrorhandler. Instead:
--   /lode errors           lists Lodestar-related errors from ScriptErrorsFrame
--   ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED are recorded with the function name and printed
--   on logout the Lodestar-related entries are copied to LodestarProbeDB so they can be read from disk
local Lodestar = _G.Lodestar

local MAX = 40

local function probeDB()
	local db = _G.LodestarProbeDB
	if type(db) ~= "table" then
		db = {}
		_G.LodestarProbeDB = db
	end
	return db
end

--- Error messages/stacks can be secret values (12.x); indexing or serialising those raises from
--- insecure code, so entries we cannot read are skipped rather than inspected.
local function accessible(v)
	return canaccessvalue == nil or canaccessvalue(v)
end

local function isOurs(text)
	return type(text) == "string" and text:find("Lodestar", 1, true) ~= nil
end

--- Lodestar-related entries from Blizzard's error store: { message, stack, count, time }.
--- Entries at or below the count recorded by ClearRecordedErrors are skipped.
function Lodestar:GetRecordedErrors()
	local list = {}
	local frame = _G.ScriptErrorsFrame
	local baseline = self.errorBaseline
	if frame and frame.GetCount and frame.GetErrorData then
		local ok, count = pcall(frame.GetCount, frame)
		if ok and type(count) == "number" then
			for i = 1, count do
				local ok2, data = pcall(frame.GetErrorData, frame, i)
				if ok2 and type(data) == "table" and accessible(data.message) and accessible(data.stack)
					and (isOurs(data.message) or isOurs(data.stack)) then
					local seen = (accessible(data.count) and tonumber(data.count)) or 1
					local n = seen - (baseline and baseline[i] or 0)
					if n > 0 then
						tinsert(list, { message = data.message, stack = data.stack, count = n, time = data.time })
					end
				end
			end
		end
	end
	return list
end

--- ScriptErrorsFrame's list is append-only for the session (created in OnLoad, only ever inserted
--- into, no Clear method) and insecure code must not touch it, so "clear" remembers each entry's
--- occurrence count instead. A plain index floor would not do: Blizzard dedupes on message..stack,
--- so a repeat of an older error bumps the count at its original index rather than appending, and
--- would stay hidden forever.
function Lodestar:ClearRecordedErrors()
	local baseline = {}
	local frame = _G.ScriptErrorsFrame
	if frame and frame.GetCount and frame.GetErrorData then
		local ok, count = pcall(frame.GetCount, frame)
		if ok and type(count) == "number" then
			for i = 1, count do
				local ok2, data = pcall(frame.GetErrorData, frame, i)
				if ok2 and type(data) == "table" and accessible(data.count) then
					baseline[i] = tonumber(data.count) or 0
				end
			end
		end
	end
	self.errorBaseline = baseline
	local db = probeDB()
	db.blocked = nil
	db.errors = nil
	db.errorsAt = nil
end

function Lodestar:SnapshotErrors()
	local db = probeDB()
	local list = self:GetRecordedErrors()
	db.errors = {}
	for i = math.max(1, #list - MAX + 1), #list do tinsert(db.errors, list[i]) end
	db.errorsAt = date("%Y-%m-%d %H:%M:%S")
	db.lodestarVersion = self.version
end

-- Protected / forbidden calls ---------------------------------------------------------------------

function Lodestar:OnAddonActionEvent(event, addonName, functionName)
	if type(addonName) ~= "string" or not addonName:find("^Lodestar") then return end
	local db = probeDB()
	db.blocked = db.blocked or {}
	tinsert(db.blocked, { event = event, addon = addonName, func = tostring(functionName), at = date("%Y-%m-%d %H:%M:%S"),
		stack = debugstack and debugstack(2, 12, 0) or nil, version = self.version })
	while #db.blocked > MAX do tremove(db.blocked, 1) end
	self.blockedCount = (self.blockedCount or 0) + 1
	self:Say("|cffff5555%s|r: %s tried %s — recorded (/lode errors).", event == "ADDON_ACTION_FORBIDDEN" and "Forbidden call" or "Blocked call", addonName, tostring(functionName))
end

function Lodestar:InstallErrorCatcher()
	self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnAddonActionEvent")
	self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnAddonActionEvent")
	self:RegisterEvent("PLAYER_LOGOUT", "SnapshotErrors")
end

function Lodestar:PrintErrors()
	local db = probeDB()
	local blocked = db.blocked or {}
	local errors = self:GetRecordedErrors()
	if #blocked == 0 and #errors == 0 then
		self:Say("No Lodestar errors or blocked calls recorded.")
		return
	end
	for i, b in ipairs(blocked) do
		self:Say("|cffff5555block #%d|r %s: %s called %s", i, b.at or "?", b.addon, b.func)
	end
	for i, e in ipairs(errors) do
		self:Say("|cffff5555error #%d|r (x%d, %s) %s", i, e.count or 1, e.time or "?", tostring(e.message):sub(1, 300))
	end
	self:SnapshotErrors()
end

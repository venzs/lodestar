-- Lodestar core: remember our own Lua errors in LodestarProbeDB.errors so they can be read
-- from the saved variables after a /reload (the beta has no BugSack yet). Errors from other
-- addons are passed straight through to whatever handler was installed before us.
local Lodestar = _G.Lodestar

local MAX_ERRORS = 40
local installed = false

local function record(msg)
	local db = _G.LodestarProbeDB
	if type(db) ~= "table" then
		db = {}
		_G.LodestarProbeDB = db
	end
	db.errors = db.errors or {}
	local list = db.errors
	local text = tostring(msg)
	local last = list[#list]
	if last and last.msg == text then
		last.count = (last.count or 1) + 1
		last.last = date("%Y-%m-%d %H:%M:%S")
		return
	end
	tinsert(list, { msg = text, stack = debugstack and debugstack(3, 8, 0) or nil, at = date("%Y-%m-%d %H:%M:%S"), count = 1, version = Lodestar.version })
	while #list > MAX_ERRORS do tremove(list, 1) end
end

function Lodestar:InstallErrorCatcher()
	if installed or not seterrorhandler or not geterrorhandler then return end
	installed = true
	local previous = geterrorhandler()
	seterrorhandler(function(msg, ...)
		local text = tostring(msg)
		if text:find("Lodestar", 1, true) then
			pcall(record, text)
			Lodestar.errorCount = (Lodestar.errorCount or 0) + 1
		end
		if previous then return previous(msg, ...) end
	end)
end

function Lodestar:GetRecordedErrors()
	local db = _G.LodestarProbeDB
	return db and db.errors or {}
end

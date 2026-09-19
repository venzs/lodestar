-- Lodestar core: keeping the few things you'd notice, on a client that forgets everything.
--
-- The Forever beta does not hand addon saved variables back. Measured, not inferred: Lodestar
-- writes a session counter at login that nothing ever resets, and on this build it reads 1 every
-- time, with sawPreviousSession false, including across a plain /reload. The file on disk is
-- written correctly and then ignored on the way in.
--
-- So every window goes back to its default position, the guide restarts, and a session's harvest is
-- thrown away -- none of which is a bug in the addon, and none of which the addon can fix by saving
-- harder.
--
-- But the client's OWN config does persist. config-cache.wtf survives relaunches on the same
-- machine where the saved variables do not, and C_CVar.RegisterCVar lets an addon put a value into
-- it. That is the way out: a small amount of state, through a channel this client actually reads
-- back, until the saved-variable path is fixed.
--
-- Deliberately small. This is not a second database and must not become one -- it is the handful of
-- things whose loss is *noticeable every single login*: where the windows are, which guide you are
-- on, and how far through it you are. The harvest, the settings and the history stay in the saved
-- variables, where they belong and where they will work again the day the client does.
--
-- It also has to be safe on a client where this does not work: RegisterCVar may be absent, may
-- refuse the name, may cap the length, or may be restricted mid-session. Every path here degrades
-- to "no stored value", which is exactly the behaviour today.
local Lodestar = _G.Lodestar

local CVAR = "lodestarState"
local MAX_BYTES = 1800        -- comfortably inside what the config file handles; checked before every write
local SEP, PAIR = "\30", "\31" -- record and field separators: bytes no key or value of ours contains

local available, loaded = nil, nil
local cache = {}              -- [key] = string
local dirty = false

local function canUse()
	if available ~= nil then return available end
	available = false
	if not (C_CVar and C_CVar.RegisterCVar and C_CVar.GetCVar and C_CVar.SetCVar) then return false end
	-- RegisterCVar on a name the client already knows is not an error, so this is safe to repeat.
	local ok = pcall(C_CVar.RegisterCVar, CVAR, "")
	if not ok then return false end
	available = true
	return true
end

local function load()
	if loaded then return end
	loaded = true
	if not canUse() then return end
	local ok, raw = pcall(C_CVar.GetCVar, CVAR)
	if not (ok and type(raw) == "string" and raw ~= "") then return end
	for record in raw:gmatch("[^" .. SEP .. "]+") do
		local key, value = record:match("^(.-)" .. PAIR .. "(.*)$")
		if key and key ~= "" then cache[key] = value end
	end
end

local function flush()
	if not (dirty and canUse()) then return end
	dirty = false
	local parts = {}
	for key, value in pairs(cache) do
		parts[#parts + 1] = key .. PAIR .. value
	end
	local raw = table.concat(parts, SEP)
	if #raw > MAX_BYTES then
		-- Refuse rather than write a truncated value that would parse as plausible nonsense.
		Lodestar:Debug("vault: %d bytes is over the %d-byte limit; not written", #raw, MAX_BYTES)
		return
	end
	pcall(C_CVar.SetCVar, CVAR, raw)
end

--- The stored string for `key`, or nil. Safe before the client is fully up.
function Lodestar:VaultGet(key)
	load()
	return cache[key]
end

--- Store `value` (a string, or nil to forget it) under `key`.
---
--- Written through to the client's config immediately. That is the point: the client is not going
--- to ask us for it at logout the way saved variables are supposed to work, so there is no later.
function Lodestar:VaultSet(key, value)
	load()
	if value ~= nil then value = tostring(value) end
	if cache[key] == value then return end
	cache[key] = value
	dirty = true
	flush()
end

--- True when this client will keep anything for us at all.
function Lodestar:VaultWorks()
	load()
	return available == true
end

-- Anchors ---------------------------------------------------------------------------------------
--
-- The one shape the vault stores for other modules, because a window in the wrong place is the
-- thing you notice first and every session. Four fields, fixed order, so a value written by an
-- older build still reads.

function Lodestar:VaultSaveAnchor(key, store)
	if type(store) ~= "table" then return end
	self:VaultSet("a:" .. key, ("%s,%s,%s,%s"):format(
		tostring(store.point or ""), tostring(store.rel or ""),
		tostring(math.floor((tonumber(store.x) or 0) + 0.5)),
		tostring(math.floor((tonumber(store.y) or 0) + 0.5))))
end

--- Fill `store` from the vault, but only where it has nothing of its own -- a saved variable that
--- did come back is the better answer and must win.
---
--- "Nothing of its own" has to include *sitting at the default*, which is the trap here. AceDB
--- materialises its defaults into the profile, so on a client that hands nothing back `store` is
--- not empty, it is a full anchor that happens to be the factory one. Treating that as a real saved
--- position is how the vault reads correctly and then gets ignored: the window goes back to the
--- default on every login and the stored value is never used. `default` is what makes the two
--- distinguishable, so callers pass it.
local function atDefault(store, default)
	if type(default) ~= "table" then return false end
	return store.point == default.point
		and (store.rel or store.point) == (default.rel or default.point)
		and (tonumber(store.x) or 0) == (tonumber(default.x) or 0)
		and (tonumber(store.y) or 0) == (tonumber(default.y) or 0)
end

function Lodestar:VaultLoadAnchor(key, store, default)
	if type(store) ~= "table" then return false end
	if store.point and not atDefault(store, default) then return false end
	local raw = self:VaultGet("a:" .. key)
	if not raw then return false end
	local point, rel, x, y = raw:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
	if not (point and point ~= "") then return false end
	store.point, store.rel = point, (rel ~= "" and rel or point)
	store.x, store.y = tonumber(x) or 0, tonumber(y) or 0
	return true
end

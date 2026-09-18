-- Lodestar_Leveling: /way — TomTom-style coordinates on top of Blizzard's native user waypoint.
--
--   /way 45.2 63.1 Optional note      pin on the current map (also accepts 45,2 63,1 or 45.2, 63.1)
--   /way #1429 45 63 note             pin on a specific uiMapID
--   /way clear                        remove the pin
--   /way                              print where you are
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local lastNote

local function currentMapID()
	return C_Map.GetBestMapForUnit("player")
end

local function playerCoords(mapID)
	mapID = mapID or currentMapID()
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or not y or (x == 0 and y == 0) then return nil end
	return x * 100, y * 100, mapID
end

local function mapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or ("map " .. tostring(mapID))
end

--- Parse "[#mapID] x y [note]" with , or . decimal separators. Returns mapID, x, y, note or nil, err.
local function parseWay(input)
	local text = strtrim(input or "")
	local mapID
	local hash = text:match("^#(%d+)")
	if hash then
		mapID = tonumber(hash)
		text = strtrim(text:sub(#hash + 2))
	end
	-- Normalise "45,2 63,1" (comma decimals) and "45.2, 63.1" (comma separators).
	local a, b, rest = text:match("^([%d]+[%.,]?[%d]*)[%s,]+([%d]+[%.,]?[%d]*)%s*(.*)$")
	if not a then return nil, "usage: /way [#mapID] x y [note]" end
	local x, y = tonumber((a:gsub(",", "."))), tonumber((b:gsub(",", ".")))
	if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
		return nil, "coordinates must be between 0 and 100"
	end
	return mapID or currentMapID(), x, y, rest ~= "" and rest or nil
end

function Leveling:SetWaypoint(mapID, x, y, note)
	if not mapID then
		Lodestar:Say("Can't tell which map you are on.")
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
		Lodestar:Say("Waypoints aren't allowed on %s.", mapName(mapID))
		return false
	end
	local point = UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100)
	C_Map.SetUserWaypoint(point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	lastNote = note
	if self.db.profile.waypoints.announce then
		Lodestar:Msg("Waypoint set: %s %.1f, %.1f%s", mapName(mapID), x, y, note and (" — " .. note) or "")
	end
	return true
end

function Leveling:ClearWaypoint()
	C_Map.ClearUserWaypoint()
	lastNote = nil
	Lodestar:Msg("Waypoint cleared.")
end

function Leveling:PrintPosition()
	local x, y, mapID = playerCoords()
	if not x then
		Lodestar:Say("No coordinates available here (instances and some areas hide them).")
	else
		Lodestar:Say("You are at %s %.1f, %.1f (map %d).", mapName(mapID), x, y, mapID)
	end
	if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
		local wp = C_Map.GetUserWaypoint()
		if wp and wp.position then
			Lodestar:Say("Waypoint: %s %.1f, %.1f%s", mapName(wp.uiMapID), wp.position.x * 100, wp.position.y * 100,
				lastNote and (" — " .. lastNote) or "")
		end
	end
end

function Leveling:HandleWay(input)
	if not self.db.profile.waypoints.enabled then
		Lodestar:Say("/way is disabled in Lodestar Leveling settings.")
		return
	end
	local text = strtrim(input or ""):lower()
	if text == "" then
		self:PrintPosition()
		return
	end
	if text == "clear" or text == "reset" or text == "remove" then
		self:ClearWaypoint()
		return
	end
	local mapID, x, y, note = parseWay(input)
	if not mapID then
		Lodestar:Say(x) -- error message
		return
	end
	self:SetWaypoint(mapID, x, y, note)
end

function Leveling:EnableWaypoints()
	if not self.wayRegistered then
		self.wayRegistered = true
		_G.SLASH_LODESTARWAY1 = "/way"
		_G.SLASH_LODESTARWAY2 = "/lway"
		SlashCmdList.LODESTARWAY = function(input) Leveling:HandleWay(input) end
		Lodestar:RegisterSlashVerb("way", function(rest) self:HandleWay(rest) end, "set a map waypoint: /lode way 45.2 63.1")
		Lodestar:RegisterSlashVerb("loc", function() self:PrintPosition() end, "print your coordinates")
	end
end

function Leveling:DisableWaypoints()
	-- Slash commands stay registered; HandleWay checks the enabled flag.
end

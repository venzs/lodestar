-- Lodestar_Guide: travel hints — "hearth to Brill" or "fly to The Sepulcher" when that beats running.
--
-- Hearth position: recorded when the hearthstone is bound and after a hearthstone cast lands. Flight
-- nodes: the ones the harvest saw on the flight map (LodestarScanDB.taxi, state reachable). A hint
-- appears only when the detour saves a real distance (HINT_MIN_SAVING yards) and the hearthstone is
-- off cooldown for the hearth case.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local HEARTHSTONE_ITEM = 6948
local HEARTHSTONE_SPELL = 8690
local HINT_MIN_SAVING = 700       -- yards the detour must save before it is worth suggesting
local FLIGHT_MASTER_NEAR = 300    -- yards: how close a flight master must be to count as "here"
local CACHE_SECONDS = 5

local cache = { at = 0 }
local hearthCastPending = false

local function playerXYNow()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return nil end
	return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function recordHearth()
	local mapID, x, y = playerXYNow()
	if not mapID then return end
	local name = GetBindLocation and GetBindLocation() or nil
	Guide.db.char.hearth = { map = mapID, x = x, y = y, name = name, at = time() }
	cache.at = 0
end

--- The hearthstone's remaining cooldown in seconds (0 when ready, nil when no hearthstone).
function Guide:HearthCooldown()
	if not (C_Container and C_Container.GetItemCooldown) then return nil end
	local ok, start, duration = pcall(C_Container.GetItemCooldown, HEARTHSTONE_ITEM)
	if not ok or not start then return nil end
	if not duration or duration == 0 then return 0 end
	return math.max(0, (start + duration) - GetTime())
end

local function worldDistanceBetween(aMap, ax, ay, bMap, bx, by)
	local ca, awx, awy = Guide:WorldPos(aMap, ax, ay)
	local cb, bwx, bwy = Guide:WorldPos(bMap, bx, by)
	if not ca or not cb or ca ~= cb then return nil end
	local dx, dy = awx - bwx, awy - bwy
	return math.sqrt(dx * dx + dy * dy)
end

--- Reachable flight nodes from the harvest as { name, map, x (0..1), y (0..1) }.
local function knownFlightNodes()
	local db = Guide.HarvestDB and Guide:HarvestDB()
	local list = {}
	for _, node in pairs(db and db.taxi or {}) do
		if (node.state == "reachable" or node.state == "current") and node.map and node.x and node.y then
			tinsert(list, { name = node.name or "flight point", map = node.map, x = node.x / 100, y = node.y / 100 })
		end
	end
	return list
end

--- A short hint for reaching `target` ({ mapID, x, y } in 0..1 coords) when hearthing or flying beats
--- running, or nil. `dist` is the straight-line distance in yards.
function Guide:TravelHint(target, dist)
	if not target or not dist or dist < HINT_MIN_SAVING * 1.5 then return nil end
	local now = GetTime()
	if now - cache.at < CACHE_SECONDS and cache.target == target then return cache.hint end
	cache.at, cache.target, cache.hint = now, target, nil
	local best, bestSaving

	-- hearth
	local hearth = self.db.char.hearth
	local cd = self:HearthCooldown()
	if hearth and cd == 0 then
		local d = worldDistanceBetween(hearth.map, hearth.x / 100, hearth.y / 100, target.mapID, target.x, target.y)
		if d then
			local saving = dist - d
			if saving >= HINT_MIN_SAVING then
				best, bestSaving = ("|cff7fff7fHearth|r to %s, then %d yd"):format(hearth.name or "your inn", d), saving
			end
		end
	end

	-- flight: from a flight master near the player to the node nearest the target
	local nodes = knownFlightNodes()
	if #nodes >= 2 then
		local pmap, px, py = playerXYNow()
		if pmap then
			local from, fromDist
			for _, n in ipairs(nodes) do
				local d = worldDistanceBetween(pmap, px / 100, py / 100, n.map, n.x, n.y)
				if d and d <= FLIGHT_MASTER_NEAR and (not fromDist or d < fromDist) then from, fromDist = n, d end
			end
			if from then
				local to, toDist
				for _, n in ipairs(nodes) do
					if n ~= from then
						local d = worldDistanceBetween(n.map, n.x, n.y, target.mapID, target.x, target.y)
						if d and (not toDist or d < toDist) then to, toDist = n, d end
					end
				end
				if to and toDist then
					local saving = dist - toDist
					if saving >= HINT_MIN_SAVING and (not bestSaving or saving > bestSaving) then
						best = ("|cff7fff7fFly|r to %s, then %d yd"):format(to.name, toDist)
					end
				end
			end
		end
	end
	cache.hint = best
	return best
end

function Guide:TravelOnEvent(event, ...)
	if event == "HEARTHSTONE_BOUND" then
		recordHearth()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" and spellID == HEARTHSTONE_SPELL then hearthCastPending = true end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if hearthCastPending then
			hearthCastPending = false
			self:ScheduleTimer(recordHearth, 2)
		end
	elseif event == "TAXIMAP_OPENED" then
		cache.at = 0
	end
end

--- UNIT_SPELLCAST_SUCCEEDED fires for every unit in range, which on a busy night is hundreds of
--- events a second, and the module's shared dispatcher would run the harvest and the engine on each
--- one. RegisterUnitEvent narrows it to the player at the client level, so nothing else ever
--- reaches Lua. Where that method is missing the event is simply not registered: the hearth position
--- still gets recorded on HEARTHSTONE_BOUND, which is the case that matters.
local castFrame

function Guide:EnableTravel()
	if not self.db.profile.travel.hints then return end
	if not castFrame then
		castFrame = CreateFrame("Frame")
		castFrame:SetScript("OnEvent", function(_, event, ...) Guide:TravelOnEvent(event, ...) end)
	end
	if castFrame.RegisterUnitEvent then
		castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	end
end

function Guide:DisableTravel()
	if castFrame then castFrame:UnregisterAllEvents() end
	cache.at, cache.target, cache.hint = 0, nil, nil
end

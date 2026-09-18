-- Lodestar_Guide: the navigation arrow.
--
-- A compass arrow that rotates toward a target: the current guide step, the /way waypoint, or
-- the nearest thing worth doing in the quest log (Blizzard's own routing via
-- C_QuestLog.GetNextWaypoint gives the next point for any quest — objective, or turn-in once
-- the quest is complete). Distance is real yards from C_Map.GetWorldPosFromMapPos.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local FormatDuration = Lodestar.FormatDuration

local arrow                 -- frame
local target                -- { mapID, x, y, title, subtitle, questID, kind }
local lastDistance, lastDistanceTime, speed = nil, nil, 0
local lastViaTrail = false  -- whether the last update measured progress along a trail path
local lastSuperTracked
local retargetTimer

-- Coordinates ----------------------------------------------------------------------------------

--- World position (continent id, x, y in yards) for a map position.
local function worldPos(mapID, x, y)
	if not (mapID and x and y and C_Map.GetWorldPosFromMapPos) then return nil end
	local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not pos then return nil end
	return continent, pos.x, pos.y
end

--- Exposed for the recorder / optimizer.
function Guide:WorldPos(mapID, x, y)
	return worldPos(mapID, x, y)
end

local function playerMapPos()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or not y or (x == 0 and y == 0) then return nil end
	return mapID, x, y
end

--- Player world position (continent, north, west). UnitPosition is allocation-free and lives in the
--- same yard space as GetWorldPosFromMapPos (HereBeDragons relies on the same equivalence).
local function playerWorld()
	if UnitPosition then
		local wx, wy, _, instance = UnitPosition("player")
		if wx and wy and instance then return instance, wx, wy end
	end
	local pmap, px, py = playerMapPos()
	if not pmap then return nil end
	return worldPos(pmap, px, py)
end

--- Distance and bearing to a world point (continent, north, west).
local function vectorToWorld(tc, twx, twy)
	local pc, pwx, pwy = playerWorld()
	if not pc or not tc then return nil end
	if pc ~= tc then return nil, "continent" end
	local dx, dy = twx - pwx, twy - pwy
	return math.sqrt(dx * dx + dy * dy), math.atan2(dy, dx)
end

--- Distance in yards and bearing (radians, 0 = north, counter-clockwise) from the player to a map point.
function Guide:VectorTo(mapID, x, y)
	local tc, twx, twy = worldPos(mapID, x, y)
	if not tc then return nil end
	return vectorToWorld(tc, twx, twy)
end

--- Distance in yards from the player to a world point (nil on another continent).
function Guide:DistanceToWorld(continent, wx, wy)
	return (vectorToWorld(continent, wx, wy))
end

--- Resolve a map given as a uiMapID or a zone name. Names are looked up once from the whole map
--- tree (both continents); zone maps win over dungeons/micro maps that share a name.
local mapByName
local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
function Guide:ResolveMap(map)
	if type(map) == "number" then return map end
	if type(map) ~= "string" then return nil end
	if not mapByName then
		local root = C_Map.GetBestMapForUnit("player")
		if not root then return nil end -- not in the world yet; try again next call
		mapByName = {}
		local kinds = {}
		local info = C_Map.GetMapInfo(root)
		while info and info.parentMapID and info.parentMapID > 0 do
			root = info.parentMapID
			info = C_Map.GetMapInfo(root)
		end
		if root and C_Map.GetMapChildrenInfo then
			for _, child in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
				if child.name then
					local key = child.name:lower()
					if not mapByName[key] or (kinds[key] ~= ZONE_TYPE and child.mapType == ZONE_TYPE) then
						mapByName[key] = child.mapID
						kinds[key] = child.mapType
					end
				end
			end
		end
		if info and info.name and not mapByName[info.name:lower()] then mapByName[info.name:lower()] = root end
		-- Common aliases between the 1.12 area names and the modern map names.
		local alias = { ["stormwind"] = "stormwind city", ["undercity"] = "undercity", ["the undercity"] = "undercity" }
		for from, to in pairs(alias) do if not mapByName[from] and mapByName[to] then mapByName[from] = mapByName[to] end end
	end
	return mapByName[map:lower()]
end

function Guide:MapName(map)
	local id = self:ResolveMap(map)
	local info = id and C_Map.GetMapInfo(id)
	return info and info.name or tostring(map)
end

-- Targets ---------------------------------------------------------------------------------------

local function guideTarget()
	local step = Guide:CurrentStep()
	if not (step and step.go) then return nil end
	local mapID = Guide:ResolveMap(step.go.map)
	if not mapID then return nil end
	return { kind = "guide", mapID = mapID, x = step.go.x / 100, y = step.go.y / 100,
		title = Guide:StepText(step), subtitle = "Guide step " .. step.index, radius = step.go.radius }
end

local function waypointTarget()
	if not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
	local wp = C_Map.GetUserWaypoint()
	if not (wp and wp.position) then return nil end
	local Leveling = Lodestar.moduleByKey and Lodestar.moduleByKey.Leveling
	local note = Leveling and Leveling.GetWaypointNote and Leveling:GetWaypointNote()
	return { kind = "waypoint", mapID = wp.uiMapID, x = wp.position.x, y = wp.position.y,
		title = note or "Waypoint", subtitle = Guide:MapName(wp.uiMapID) }
end

-- A position the player pinned by clicking a row in the guide window. It takes precedence over the
-- mode until it is cleared, so pinning one action of a step never disturbs the player's own /way pin.
local pinned

--- Point the arrow at one position until ClearPinnedPosition. `owner` is an opaque token the caller
--- can use to tell whether the pin is still theirs.
function Guide:PinPosition(mapID, x, y, title, subtitle, owner)
	if not (mapID and x and y) then return false end
	pinned = { kind = "pinned", mapID = mapID, x = x, y = y, title = title or "Pinned", subtitle = subtitle, owner = owner }
	self:RetargetArrow()
	return true
end

function Guide:ClearPinnedPosition(owner)
	if not pinned then return false end
	if owner ~= nil and pinned.owner ~= owner then return false end
	pinned = nil
	self:RetargetArrow()
	return true
end

function Guide:GetPinnedPosition() return pinned end

local function questTarget()
	local it = Guide:SmartTarget(true)
	if not it then return nil end
	return { kind = "quest", mapID = it.mapID, x = it.x, y = it.y, questID = it.questID, title = it.title, subtitle = it.subtitle, smartKind = it.kind }
end

--- Pick the arrow target according to the mode.
function Guide:RetargetArrow()
	local mode = self.db.profile.arrow.mode
	local t
	if mode == "OFF" then
		t = nil
		pinned = nil
	elseif pinned then
		t = { kind = "pinned", mapID = pinned.mapID, x = pinned.x, y = pinned.y, title = pinned.title, subtitle = pinned.subtitle }
	elseif mode == "GUIDE" then
		t = guideTarget()
	elseif mode == "WAYPOINT" then
		t = waypointTarget()
	elseif mode == "QUEST" then
		t = questTarget()
	else
		t = guideTarget() or waypointTarget() or questTarget()
	end
	-- a guide step with explicit `path` points is walked point by point first (Trails.lua)
	if t and self.TrailTargetOverride then t = self:TrailTargetOverride(t) end
	if not (target and t and target.kind == t.kind and target.mapID == t.mapID and target.x == t.x and target.y == t.y) then
		lastDistance, lastDistanceTime, speed = nil, nil, 0
	end
	target = t
	if t then t.continent, t.wx, t.wy = worldPos(t.mapID, t.x, t.y) end
	if t and t.questID and self.db.profile.arrow.superTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		if lastSuperTracked ~= t.questID then
			lastSuperTracked = t.questID
			pcall(C_SuperTrack.SetSuperTrackedQuestID, t.questID)
		end
	end
	self:UpdateArrowFrame()
end

function Guide:GetArrowTarget() return target end

--- Distance in yards to the current target, or nil.
function Guide:GetArrowDistance()
	if not target then return nil end
	return (self:VectorTo(target.mapID, target.x, target.y))
end

-- Frame -----------------------------------------------------------------------------------------

local function savePosition()
	local point, _, _, x, y = arrow:GetPoint(1)
	Guide.db.profile.arrow.pos = { point = point or "CENTER", x = x or 0, y = y or 0 }
end

local function colorFor(relative)
	local a = math.abs(relative)
	while a > math.pi do a = a - 2 * math.pi end
	a = math.abs(a)
	if a < 0.2 then return 0.3, 1, 0.3 end
	if a < 0.8 then return 1, 0.9, 0.2 end
	return 1, 0.35, 0.3
end

local function onUpdate(self, elapsed)
	self.acc = (self.acc or 0) + elapsed
	if self.acc < 0.05 then return end
	self.acc = 0
	if not target then
		self.arrow:Hide()
		self.title:SetText("|cff888888No target|r")
		self.dist:SetText("")
		if Guide.DrawMinimapLine then Guide:DrawMinimapLine(nil) end
		return
	end
	local dist, bearing
	if target.continent then
		dist, bearing = vectorToWorld(target.continent, target.wx, target.wy)
	else
		dist, bearing = Guide:VectorTo(target.mapID, target.x, target.y)
	end
	if not dist then
		self.arrow:Hide()
		self.title:SetText(target.title or "")
		self.dist:SetText(bearing == "continent" and "|cff888888other continent|r" or "|cff888888no position|r")
		if Guide.DrawMinimapLine then Guide:DrawMinimapLine(nil) end
		return
	end
	local arrived = dist <= (target.radius or Guide.db.profile.arrow.arrivalYards or 10)
	if arrived and target.waypoint and Guide.TrailWaypointReached then
		Guide:TrailWaypointReached(target) -- retargets to the next path point
		return
	end
	-- Known walkable ground (Trails.lua): point at the next bend of the learned path instead of straight
	-- at the target. `remaining` is the yards left along that path.
	local remaining
	if Guide.TrailNext then
		local node, left = Guide:TrailNext(target, dist)
		if node then
			local ndist, nbearing = vectorToWorld(node.continent, node.wx, node.wy)
			if ndist then bearing, remaining = nbearing, left end
		end
	end
	local facing = GetPlayerFacing() or 0
	local relative = bearing - facing
	self.arrow:Show()
	self.arrow:SetRotation(relative)
	if Guide.DrawMinimapLine then Guide:DrawMinimapLine(target, dist, facing) end
	if arrived then self.arrow:SetVertexColor(0.3, 1, 0.3) else self.arrow:SetVertexColor(colorFor(relative)) end
	self.title:SetText(target.title or "")

	-- speed / ETA, measured along the path when there is one (the straight-line distance may grow on a detour)
	local now = GetTime()
	local progress = remaining or dist
	if (remaining ~= nil) ~= lastViaTrail then lastDistance = nil end
	lastViaTrail = remaining ~= nil
	if lastDistance and lastDistanceTime and now > lastDistanceTime then
		local v = (lastDistance - progress) / (now - lastDistanceTime)
		speed = speed * 0.8 + v * 0.2
	end
	lastDistance, lastDistanceTime = progress, now
	local eta = ""
	if Guide.db.profile.arrow.showETA and speed > 0.5 and dist > 5 then
		eta = "  ·  " .. FormatDuration(progress / speed)
	end
	local sub = target.subtitle and ("|cffaaaaaa" .. target.subtitle .. "|r  ·  ") or ""
	if arrived then
		self.dist:SetText(sub .. "|cff7fff7fhere|r")
	elseif remaining then
		self.dist:SetText(("%s%d yd |cff888888· via trail (%d yd)|r%s"):format(sub, dist, remaining, eta))
	else
		self.dist:SetText(("%s%d yd%s"):format(sub, dist, eta))
	end
end

local ARROW_ATLAS = "Navigation-Tracked-Arrow"
local ARROW_TEXTURE = "Interface\\AddOns\\Lodestar_Guide\\Textures\\Arrow"
local SIZES = { { "Small", 48 }, { "Normal", 72 }, { "Large", 100 }, { "Huge", 140 } }
local STYLES = { { "lodestar", "Lodestar (default)" }, { "classic", "Classic minimap arrow" }, { "blizzard", "Blizzard navigation arrow" } }

--- Apply the configured art: our own 256px arrow (crisp at any size), the classic minimap arrow, or
--- Blizzard's navigation atlas.
local function applyStyle(tex)
	local style = Guide.db.profile.arrow.style or "lodestar"
	if style == "blizzard" then
		local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ARROW_ATLAS)
		if atlas and atlas.width and atlas.height and atlas.height > 0 then
			tex:SetAtlas(ARROW_ATLAS)
			return atlas.width / atlas.height
		end
		style = "classic"
	end
	if style == "classic" then
		tex:SetTexture("Interface\\Minimap\\MinimapArrow")
	else
		tex:SetTexture(ARROW_TEXTURE)
	end
	tex:SetTexCoord(0, 1, 0, 1)
	return 1
end

--- Apply the configured arrow size: the art, the text widths and the frame follow it.
local function layoutArrow()
	local size = Guide.db.profile.arrow.size or 72
	arrow.aspect = applyStyle(arrow.arrow)
	arrow.arrow:SetSize(size * (arrow.aspect or 1), size)
	local width = math.max(260, size * 2.5)
	arrow.title:SetWidth(width)
	arrow.dist:SetWidth(width)
	arrow:SetSize(width, size + 44)
end

local function createArrow()
	arrow = CreateFrame("Frame", "LodestarArrow", UIParent)
	arrow:SetSize(260, 116)
	arrow:SetFrameStrata("MEDIUM")
	arrow:SetClampedToScreen(true)
	arrow:SetMovable(true)
	arrow:EnableMouse(true)
	arrow:RegisterForDrag("LeftButton")
	arrow:SetScript("OnDragStart", function(self) if not Guide.db.profile.arrow.locked then self:StartMoving() end end)
	arrow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
	arrow:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Guide:ShowArrowMenu() end
	end)

	arrow.arrow = arrow:CreateTexture(nil, "ARTWORK")
	arrow.arrow:SetPoint("TOP", 0, -2)
	arrow.aspect = applyStyle(arrow.arrow)

	arrow.title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	arrow.title:SetPoint("TOP", arrow.arrow, "BOTTOM", 0, -4)
	arrow.title:SetJustifyH("CENTER")
	arrow.title:SetWordWrap(false)

	arrow.dist = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	arrow.dist:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
	arrow.dist:SetJustifyH("CENTER")

	layoutArrow()
	arrow:SetScript("OnUpdate", onUpdate)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(Lodestar.COLOR .. "Lodestar|r arrow")
		if target then
			GameTooltip:AddLine(target.title or "", 1, 1, 1)
			GameTooltip:AddLine(("%s · %.1f, %.1f"):format(Guide:MapName(target.mapID), target.x * 100, target.y * 100), 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("|cffaaaaaaDrag to move when unlocked · Right-click: options|r")
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Guide:UpdateArrowFrame()
	if not arrow then return end
	local cfg = self.db.profile.arrow
	if not self:IsEnabled() or not cfg.show or cfg.mode == "OFF" then
		arrow:Hide()
		return
	end
	arrow:ClearAllPoints()
	arrow:SetPoint(cfg.pos.point or "CENTER", UIParent, cfg.pos.point or "CENTER", cfg.pos.x or 0, cfg.pos.y or 180)
	arrow:SetScale(cfg.scale or 1)
	layoutArrow()
	arrow:Show()
end

function Guide:ShowArrowMenu()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then self:OpenSettings() return end
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Lodestar arrow")
		for _, mode in ipairs({ "AUTO", "GUIDE", "WAYPOINT", "QUEST" }) do
			root:CreateRadio(({ AUTO = "Automatic", GUIDE = "Guide step", WAYPOINT = "Waypoint", QUEST = "Nearest quest" })[mode],
				function() return self.db.profile.arrow.mode == mode end,
				function() self.db.profile.arrow.mode = mode self:RetargetArrow() end)
		end
		root:CreateDivider()
		local sizeMenu = root:CreateButton("Size")
		if sizeMenu and sizeMenu.CreateRadio then
			for _, entry in ipairs(SIZES) do
				local label, px = entry[1], entry[2]
				sizeMenu:CreateRadio(label, function() return (self.db.profile.arrow.size or 72) == px end,
					function() self.db.profile.arrow.size = px self:UpdateArrowFrame() end)
			end
		end
		local styleMenu = root:CreateButton("Style")
		if styleMenu and styleMenu.CreateRadio then
			for _, entry in ipairs(STYLES) do
				local key, label = entry[1], entry[2]
				styleMenu:CreateRadio(label, function() return (self.db.profile.arrow.style or "lodestar") == key end,
					function() self.db.profile.arrow.style = key self:UpdateArrowFrame() end)
			end
		end
		root:CreateCheckbox("Line on the minimap", function() return self.db.profile.arrow.minimapLine ~= false end,
			function() self.db.profile.arrow.minimapLine = (self.db.profile.arrow.minimapLine == false) self:UpdateMinimapLine() end)
		root:CreateCheckbox("Locked", function() return self.db.profile.arrow.locked end,
			function() self.db.profile.arrow.locked = not self.db.profile.arrow.locked end)
		root:CreateButton("Hide arrow", function() self.db.profile.arrow.show = false self:UpdateArrowFrame() end)
		root:CreateButton("Settings", function() self:OpenSettings() end)
	end)
end

function Guide:OpenSettings()
	Lodestar:OpenConfig("Guide")
end

-- Lifecycle ----------------------------------------------------------------------------------------

function Guide:EnableArrow()
	if not arrow then createArrow() end
	retargetTimer = self:ScheduleRepeatingTimer("RetargetArrow", 5)
	self:RetargetArrow()
	if not self.arrowSlash then
		self.arrowSlash = true
		Lodestar:RegisterSlashVerb("arrow", function(rest)
			rest = strtrim(rest or ""):upper()
			if rest == "" then
				self.db.profile.arrow.show = not self.db.profile.arrow.show
				self:UpdateArrowFrame()
			elseif rest == "AUTO" or rest == "GUIDE" or rest == "WAYPOINT" or rest == "QUEST" or rest == "OFF" then
				self.db.profile.arrow.mode = rest
				self:RetargetArrow()
				Lodestar:Say("Arrow mode: %s", rest:lower())
			else
				Lodestar:Say("Usage: /lode arrow [auto|guide|waypoint|quest|off]")
			end
		end, "toggle the arrow, or set what it points at")
	end
end

local ARROW_EVENTS = { QUEST_LOG_UPDATE = true, QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true,
	USER_WAYPOINT_UPDATED = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_ENTERING_WORLD = true, LODESTAR_STEP_CHANGED = true,
	QUESTLINE_UPDATE = true, AREA_POIS_UPDATED = true }

--- Called by Guide:OnGameEvent for every game event the module listens to.
function Guide:ArrowOnEvent(event)
	if not ARROW_EVENTS[event] then return end
	if self.arrowRetargetQueued then return end
	self.arrowRetargetQueued = true
	self:ScheduleTimer(function() self.arrowRetargetQueued = false self:RetargetArrow() end, 0.5)
end

function Guide:DisableArrow()
	if retargetTimer then self:CancelTimer(retargetTimer) retargetTimer = nil end
	target = nil
	if arrow then arrow:Hide() end
	if self.DrawMinimapLine then self:DrawMinimapLine(nil) end
end

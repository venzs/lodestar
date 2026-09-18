-- Lodestar_Guide: the line on the minimap from you to the arrow's target, with a marker at the spot
-- (or at the minimap edge when the target is further than the minimap shows).
--
-- Yards per minimap pixel come from C_Minimap.GetViewRadius() (indoor/outdoor/hybrid aware, the value
-- Blizzard's own HybridMinimap uses); the HereBeDragons zoom presets remain only as a fallback.
-- The minimap's rotation setting is honoured, including Blizzard's own override of it.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

-- Minimap width in yards per zoom level.
local YARDS_OUTDOOR = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 3, [4] = 200, [5] = 133 + 1 / 3 }
local YARDS_INDOOR = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 }
local MARKER_TEXTURE = "Interface\\AddOns\\Lodestar_Guide\\Textures\\Arrow"
local EDGE_MARGIN = 6

local holder, line, marker
local lastEndX, lastEndY, lastRot, lastClamped = nil, nil, nil, false

local function minimapYards()
	-- The engine knows the real view radius in yards for the current zoom -- indoors, outdoors and
	-- under the hybrid minimap alike. Blizzard uses it the same way (Blizzard_HybridMinimap.lua).
	local r = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if type(r) == "number" and r > 0 then return r * 2 end -- x2: radius -> diameter, matching Minimap:GetWidth()
	-- Fallback only. minimapZoom and minimapInsideZoom both default to 0, so an equal pair says
	-- nothing about where we are: don't read it as "outdoors".
	local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
	local insideZoom = tonumber(GetCVar and GetCVar("minimapInsideZoom"))
	local outsideZoom = tonumber(GetCVar and GetCVar("minimapZoom"))
	local indoors
	if insideZoom and outsideZoom and insideZoom ~= outsideZoom then
		indoors = zoom == insideZoom
	else
		indoors = (IsIndoors and IsIndoors()) or false -- best effort when the cvars can't tell us
	end
	local preset = indoors and YARDS_INDOOR or YARDS_OUTDOOR
	return preset[zoom] or preset[0]
end

local function create()
	holder = CreateFrame("Frame", "LodestarMinimapLine", Minimap)
	holder:SetAllPoints(Minimap)
	holder:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
	line = holder:CreateLine(nil, "OVERLAY")
	line:SetColorTexture(0.35, 1, 0.45, 0.85)
	line:SetThickness(2.5)
	line:SetStartPoint("CENTER", Minimap, 0, 0)
	line:SetEndPoint("CENTER", Minimap, 0, 0)
	marker = holder:CreateTexture(nil, "OVERLAY", nil, 2)
	marker:SetTexture(MARKER_TEXTURE)
	marker:SetSize(14, 14)
	marker:SetVertexColor(0.35, 1, 0.45)
	marker:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
	holder:Hide()
end

--- Draw (or hide with nil) the line to `target` from the arrow's OnUpdate.
--- `dist` is yards to the target, `facing` the player facing in radians.
function Guide:DrawMinimapLine(target, dist, facing)
	local cfg = self.db and self.db.profile.arrow
	if not target or not dist or not cfg or cfg.minimapLine == false or not Minimap then
		if holder and holder:IsShown() then holder:Hide() end
		return
	end
	if not target.continent or not target.wx then
		if holder and holder:IsShown() then holder:Hide() end
		return
	end
	if not holder then create() end
	-- Offset from the player in yards: UnitPosition gives (north, west); minimap x is east, y is north.
	local pn, pw = UnitPosition("player")
	if not pn then holder:Hide() return end
	local north, east = target.wx - pn, -(target.wy - pw)
	-- Blizzard's hybrid minimap calls C_Minimap.SetIgnoreRotateMinimap(true), so the CVar alone is
	-- not the truth about whether the minimap actually rotates.
	local rotates = GetCVar and GetCVar("rotateMinimap") == "1"
		and not (C_Minimap and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored())
	if rotates then
		local a = -(facing or 0)
		local c, s = math.cos(a), math.sin(a)
		east, north = east * c - north * s, east * s + north * c
	end
	local width = Minimap:GetWidth() or 140
	local radius = width / 2 - EDGE_MARGIN
	local yards = minimapYards()
	local pxPerYard = width / yards
	local px, py = east * pxPerYard, north * pxPerYard
	local len = math.sqrt(px * px + py * py)
	local clamped = false
	local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local m = math.max(math.abs(px), math.abs(py))
		if m > radius then px, py, clamped = px * radius / m, py * radius / m, true end
	elseif len > radius then
		px, py, clamped = px * radius / len, py * radius / len, true
	end
	if px ~= lastEndX or py ~= lastEndY then
		line:SetEndPoint("CENTER", Minimap, px, py)
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", Minimap, "CENTER", px, py)
		lastEndX, lastEndY = px, py
	end
	lastClamped = clamped
	-- the marker points along the line when clamped to the edge; on the spot it shows as a dot-sized arrow
	local rot = clamped and (math.atan2(py, px) - math.pi / 2) or 0
	if rot ~= lastRot then
		marker:SetRotation(rot)
		lastRot = rot
	end
	marker:SetSize(clamped and 14 or 10, clamped and 14 or 10)
	local r, g, b = 0.35, 1, 0.45
	if dist <= (target.radius or cfg.arrivalYards or 10) then r, g, b = 0.6, 1, 0.6 end
	line:SetColorTexture(r, g, b, clamped and 0.7 or 0.9)
	marker:SetVertexColor(r, g, b)
	if not holder:IsShown() then holder:Show() end
end

--- Where the line currently ends (minimap pixels from the centre) and whether it was clamped to the edge.
function Guide:MinimapLineState()
	if not (holder and holder:IsShown()) then return nil end
	return lastEndX, lastEndY, lastClamped
end

function Guide:UpdateMinimapLine()
	if self.db.profile.arrow.minimapLine == false and holder then holder:Hide() end
end

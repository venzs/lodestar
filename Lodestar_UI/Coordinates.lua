-- Lodestar_UI: player/cursor coordinates on the world map and a readout under the minimap.
local Lodestar = _G.Lodestar
local UI = Lodestar:GetModule("UI")

local mapText, miniFrame
local elapsedAcc = 0

local function playerXY(mapID)
	if not mapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or not y or (x == 0 and y == 0) then return end
	return x * 100, y * 100
end

-- World map ------------------------------------------------------------------------------

local function updateWorldMap()
	if not (mapText and WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local mapID = WorldMapFrame:GetMapID()
	local px, py = playerXY(mapID)
	local cx, cy
	local container = WorldMapFrame.ScrollContainer
	if container and container.GetNormalizedCursorPosition and container:IsMouseOver() then
		local ok, nx, ny = pcall(container.GetNormalizedCursorPosition, container)
		if ok and nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then cx, cy = nx * 100, ny * 100 end
	end
	local parts = {}
	if px then tinsert(parts, ("|cffffd700Player|r %.1f, %.1f"):format(px, py)) end
	if cx then tinsert(parts, ("|cffffd700Cursor|r %.1f, %.1f"):format(cx, cy)) end
	mapText:SetText(table.concat(parts, "    "))
end

local function ensureWorldMap()
	if mapText or not WorldMapFrame then return end
	local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
	mapText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mapText:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 6)
	mapText:SetJustifyH("CENTER")
	mapText:SetShadowOffset(1, -1)
	WorldMapFrame:HookScript("OnUpdate", function(_, elapsed)
		if not UI.db.profile.coords.worldMap or not UI:IsEnabled() then return end
		elapsedAcc = elapsedAcc + elapsed
		if elapsedAcc < 0.1 then return end
		elapsedAcc = 0
		updateWorldMap()
	end)
end

-- Minimap --------------------------------------------------------------------------------

local function ensureMinimap()
	if miniFrame or not Minimap then return end
	miniFrame = CreateFrame("Frame", "LodestarCoordsFrame", Minimap)
	miniFrame:SetSize(90, 14)
	miniFrame:SetFrameStrata("LOW")
	miniFrame.text = miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	miniFrame.text:SetPoint("CENTER")
	miniFrame.text:SetShadowOffset(1, -1)
	miniFrame:SetScript("OnUpdate", function(self, elapsed)
		self.acc = (self.acc or 0) + elapsed
		if self.acc < 0.25 then return end
		self.acc = 0
		local x, y = playerXY(C_Map.GetBestMapForUnit("player"))
		if x then
			self.text:SetText(("%.1f, %.1f"):format(x, y))
		else
			self.text:SetText("")
		end
	end)
end

function UI:UpdateCoordinates()
	local c = self.db.profile.coords
	if mapText then mapText:SetShown(self:IsEnabled() and c.worldMap) end
	if miniFrame then
		if self:IsEnabled() and c.minimap then
			local pos = c.minimapPos
			miniFrame:ClearAllPoints()
			miniFrame:SetPoint(pos.point or "TOP", Minimap, pos.relativePoint or "BOTTOM", pos.x or 0, pos.y or -4)
			miniFrame:Show()
		else
			miniFrame:Hide()
		end
	end
end

function UI:EnableCoordinates()
	ensureWorldMap()
	ensureMinimap()
	self:UpdateCoordinates()
end

function UI:DisableCoordinates()
	self:UpdateCoordinates()
end

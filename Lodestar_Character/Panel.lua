-- Lodestar_Character: our own stats panel, docked to the character sheet.
--
-- WHY WE DO NOT INJECT INTO BLIZZARD'S STATS PANE
-- ----------------------------------------------
-- An earlier build of this module added categories to PAPERDOLL_STATCATEGORIES, registered entries in
-- PAPERDOLL_STATINFO and wrapped the showFunc of Blizzard's own HITCHANCE / CRITCHANCE / HASTE entries.
-- On Forever (Camelot) that taints the character frame: writing addon data into those Blizzard-owned
-- globals taints every execution path that reads them, and simply OPENING the character sheet threw
--
--   Interface/AddOns/Blizzard_TextStatusBar/TextStatusBar.lua:110: attempt to compare a secret number
--   value (execution tainted by 'Lodestar_Character')
--
-- (TextStatusBar UpdateTextStringWithValues <- UpdateTextString <- ShowStatusBarText <-
--  Blizzard_UIPanels_Game/Camelot/CharacterFrame.lua:737, inside the frame's OnShow <- Show <-
--  SetUIPanel <- ShowUIPanel <- ToggleCharacter), seen twice on the beta.
--
-- So nothing in this module writes to a Blizzard global table, replaces a Blizzard function or calls a
-- protected one. We read the stat API, draw our own unsecured frame, and touch Blizzard's UI only
-- through CharacterFrame:HookScript("OnShow"/"OnHide") and CharacterFrame:IsShown() — a hook script is
-- appended to the frame, it does not modify Blizzard's code or data, and reading IsShown is a read.
local Lodestar = _G.Lodestar
local Character = Lodestar:GetModule("Character")
local Stats = Character.Stats

local REFRESH_DELAY = 0.2
local PANEL_WIDTH = 300
local PAD, TITLE_H, ROW_H, HEADER_H, COLUMN_GAP = 8, 24, 14, 18, 10
local MAX_COLUMN_HEIGHT = 420        -- taller than this and the rows go into two columns
local DOCK_X, DOCK_Y = 6, -12        -- gap from the character sheet's top-right corner

local panel
local state = { refreshes = 0, rows = 0, columns = 1 }

function Character:GetPanelState() return state end
function Character:GetPanel() return panel end

--- Reading CharacterFrame:IsShown() is a plain read of Blizzard's frame: it taints nothing.
function Character:IsCharacterFrameShown()
	local frame = rawget(_G, "CharacterFrame")
	return (frame and frame.IsShown and frame:IsShown()) and true or false
end

function Character:OpenSettings()
	Lodestar:OpenConfig("Character")
end

-- Rows ------------------------------------------------------------------------------------------------

--- Is this row's value left out? A nil value means "not applicable", the row's own hideAt always
--- applies, and a plain 0 goes when "hide rows that are zero" is on and the row allows it.
local function isHidden(row, value)
	if value == nil then return true end
	if row.hideAt ~= nil then return value == row.hideAt end
	if Character.db.profile.hideZero and row.hideZero ~= false then return value == 0 end
	return false
end

--- A row's showFunc, in protected mode: a row that cannot decide is simply not shown.
local function rowShows(row)
	if not row.showFunc then return true end
	local ok, shown = pcall(row.showFunc)
	return (ok and shown) and true or false
end

--- Run one row's update against a stat frame of ours. Stats.lua keeps Blizzard's updateFunc contract:
--- it fills statFrame.Label / statFrame.Value, sets tooltip / tooltip2 / tooltip3 and returns the value.
--- Errors are swallowed and logged so one bad row cannot take the panel down.
function Character:RunRow(row, statFrame)
	local ok, value = pcall(row.update, statFrame, "player")
	if not ok then
		Lodestar:Debug("Character row %s: %s", row.stat, tostring(value))
		return nil
	end
	return value
end

-- Frame -----------------------------------------------------------------------------------------------

local function rowOnEnter(self)
	if not self.tooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.tooltip)
	if self.tooltip2 then GameTooltip:AddLine(self.tooltip2, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
	if self.tooltip3 then GameTooltip:AddLine(self.tooltip3, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
	GameTooltip:Show()
end

local function onMouseUp(_, button)
	if button == "RightButton" then Character:ShowPanelMenu() end
end

local function acquireRow(index)
	local row = panel.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, panel)
	row:SetSize(PANEL_WIDTH - PAD * 2, ROW_H)
	row:EnableMouse(true)
	row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Label:SetPoint("LEFT", 2, 0)
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWordWrap(false)
	row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Value:SetPoint("RIGHT", -2, 0)
	row.Value:SetJustifyH("RIGHT")
	row.Value:SetWordWrap(false)
	row:SetScript("OnEnter", rowOnEnter)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", onMouseUp)
	panel.rows[index] = row
	return row
end

local function acquireHeader(index)
	local header = panel.headers[index]
	if header then return header end
	header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetJustifyH("LEFT")
	header:SetWordWrap(false)
	header:SetTextColor(0.31, 0.76, 0.97)
	panel.headers[index] = header
	return header
end

local function savePosition()
	-- The relativePoint has to travel with the offsets: dragging re-anchors the frame and the
	-- corner WoW leaves behind is usually not the same one, so saving the point alone moves the
	-- panel somewhere new on every login.
	Character.db.profile.pos = Lodestar:SaveAnchor(panel, Character.db.profile.pos or {}, "TOPLEFT", "charpanel")
end

local function createPanel()
	panel = CreateFrame("Frame", "LodestarCharacterStatsFrame", UIParent, "BackdropTemplate")
	panel:SetSize(PANEL_WIDTH, 80)
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.75)
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	panel:SetScript("OnDragStart", function(self) if not Character.db.profile.locked then self:StartMoving() end end)
	panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
	panel:SetScript("OnMouseUp", onMouseUp)
	panel:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Lodestar.COLOR .. "Lodestar|r stats")
		GameTooltip:AddLine("|cffaaaaaaDrag to move when unlocked · Right-click: categories, lock, settings|r")
		GameTooltip:Show()
	end)
	panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel:SetScript("OnShow", function() Character:RegisterPanelEvents() end)
	panel:SetScript("OnHide", function() Character:UnregisterPanelEvents() end)
	-- UNIT_ events fire for every unit; only the player's own numbers are ours.
	panel:SetScript("OnEvent", function(_, event, unit)
		if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
		Character:RequestStatsUpdate()
	end)

	panel.rows, panel.headers = {}, {}
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.title:SetPoint("TOPLEFT", PAD, -PAD)
	panel.title:SetJustifyH("LEFT")
	panel.title:SetText(Lodestar.COLOR .. "Lodestar|r stats")
	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.empty:SetPoint("TOPLEFT", PAD, -TITLE_H)
	panel.empty:SetWidth(PANEL_WIDTH - PAD * 2)
	panel.empty:SetJustifyH("LEFT")
	panel.empty:SetText("Nothing to show — right-click to turn a category back on.")
	panel.empty:Hide()
	panel:Hide()
	return panel
end

function Character:EnsurePanel()
	return panel or createPanel()
end

--- Docked to the character sheet's top-right corner until the player drags it somewhere else.
function Character:AnchorPanel()
	if not panel then return end
	local pos = self.db.profile.pos
	local anchor = rawget(_G, "CharacterFrame")
	panel:ClearAllPoints()
	-- Asked before the branch, not inside it: on this client the saved variable comes back empty
	-- every login, so a vault lookup that only ran when a position already existed would never run.
	if type(pos) == "table" then Lodestar:VaultLoadAnchor("charpanel", pos, nil) end
	if pos and pos.point then
		Lodestar:ApplyAnchor(panel, pos, UIParent, nil, "charpanel")
	elseif anchor then
		panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", DOCK_X, DOCK_Y)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
	end
end

function Character:ResetPanelPosition()
	self.db.profile.pos = nil
	self:AnchorPanel()
end

-- Layout ----------------------------------------------------------------------------------------------

--- Fill the row frames for every category that is on, dropping rows that do not apply. Returns the
--- per-category blocks that have something to show plus the number of rows used.
local function buildBlocks()
	local blocks, used = {}, 0
	local enabled = Character.db.profile.categories
	for _, category in ipairs(Stats.categories) do
		if enabled[category.key] then
			local block = { name = category.name, key = category.key, rows = {} }
			for _, row in ipairs(category.rows) do
				if rowShows(row) then
					local frame = acquireRow(used + 1)
					frame.tooltip, frame.tooltip2, frame.tooltip3 = nil, nil, nil
					frame.Label:SetText("")
					frame.Value:SetText("")
					local value = Character:RunRow(row, frame)
					if isHidden(row, value) then
						frame:Hide()
					else
						used = used + 1
						tinsert(block.rows, frame)
					end
				end
			end
			if #block.rows > 0 then
				block.height = HEADER_H + #block.rows * ROW_H
				tinsert(blocks, block)
			end
		end
	end
	return blocks, used
end

--- Place the blocks top to bottom, in two columns once one column would run past MAX_COLUMN_HEIGHT.
--- Columns break between categories, so a header never ends up alone at the foot of a column.
--- Returns the number of columns and the height of the tallest one.
local function layoutBlocks(blocks)
	local total = 0
	for _, block in ipairs(blocks) do total = total + block.height end
	local columns = total > MAX_COLUMN_HEIGHT and 2 or 1
	local target = math.ceil(total / columns)
	local width = math.floor((PANEL_WIDTH - PAD * 2 - COLUMN_GAP * (columns - 1)) / columns)
	local column, y, tallest, headerIndex = 1, 0, 0, 0
	for _, block in ipairs(blocks) do
		if column < columns and y > 0 and y + block.height > target then
			tallest = math.max(tallest, y)
			column, y = column + 1, 0
		end
		local x = PAD + (column - 1) * (width + COLUMN_GAP)
		headerIndex = headerIndex + 1
		local header = acquireHeader(headerIndex)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -(TITLE_H + y))
		header:SetWidth(width)
		header:SetText(block.name)
		header:Show()
		y = y + HEADER_H
		for _, frame in ipairs(block.rows) do
			frame:ClearAllPoints()
			frame:SetSize(width, ROW_H)
			frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -(TITLE_H + y))
			frame:Show()
			y = y + ROW_H
		end
	end
	return columns, math.max(tallest, y), headerIndex
end

--- Re-read every row and lay the panel out. Returns the number of rows shown.
function Character:RefreshPanel()
	if not (panel and panel:IsShown()) then return 0 end
	state.refreshes = state.refreshes + 1
	for _, row in ipairs(panel.rows) do row:Hide() end
	for _, header in ipairs(panel.headers) do header:Hide() end
	local blocks, used = buildBlocks()
	local columns, tallest = layoutBlocks(blocks)
	panel.empty:SetShown(used == 0)
	panel:SetHeight(math.max(48, TITLE_H + tallest + PAD))
	state.rows, state.columns = used, columns
	panel.shownRows = used
	return used
end

-- Show / hide -----------------------------------------------------------------------------------------

--- Hooking CharacterFrame's OnShow/OnHide only appends scripts of ours; Blizzard's own code and tables
--- are left exactly as they were, so the character sheet stays untainted.
function Character:HookCharacterFrame()
	if self.characterHooked then return true end
	local frame = rawget(_G, "CharacterFrame")
	if not (frame and frame.HookScript) then return false end
	self.characterHooked = true
	frame:HookScript("OnShow", function() Character:UpdatePanel() end)
	frame:HookScript("OnHide", function() Character:HidePanel() end)
	return true
end

--- Show, hide, re-anchor and refresh the panel to match the options and the character sheet.
function Character:UpdatePanel()
	if not (self:IsEnabled() and self.db.profile.show and self:IsCharacterFrameShown()) then
		self:HidePanel()
		return false
	end
	local frame = self:EnsurePanel()
	self:AnchorPanel()
	local locked = self.db.profile.locked
	frame:SetBackdropBorderColor(locked and 0.4 or 0.3, locked and 0.4 or 0.75, locked and 0.4 or 1, 0.9)
	if not frame:IsShown() then frame:Show() end
	self:RefreshPanel()
	return true
end

function Character:HidePanel()
	if self.updateTimer then self:CancelTimer(self.updateTimer) self.updateTimer = nil end
	if panel and panel:IsShown() then panel:Hide() end
end

function Character:TogglePanel()
	local db = self.db.profile
	db.show = not db.show
	self:UpdatePanel()
	if db.show then
		Lodestar:Say("Character stats panel on%s.", self:IsCharacterFrameShown() and "" or " — it opens with the character sheet")
	else
		Lodestar:Say("Character stats panel off.")
	end
end

-- Menu ------------------------------------------------------------------------------------------------

function Character:ShowPanelMenu()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then self:OpenSettings() return end
	MenuUtil.CreateContextMenu(panel or UIParent, function(_, root)
		root:CreateTitle("Lodestar stats")
		for _, category in ipairs(Stats.categories) do
			local key = category.key
			root:CreateCheckbox(category.name,
				function() return self.db.profile.categories[key] end,
				function() self.db.profile.categories[key] = not self.db.profile.categories[key] self:RefreshPanel() end)
		end
		root:CreateDivider()
		root:CreateCheckbox("Hide rows that are zero", function() return self.db.profile.hideZero end,
			function() self.db.profile.hideZero = not self.db.profile.hideZero self:RefreshPanel() end)
		root:CreateCheckbox("Locked", function() return self.db.profile.locked end,
			function() self.db.profile.locked = not self.db.profile.locked self:UpdatePanel() end)
		root:CreateButton("Dock to the character sheet", function() self:ResetPanelPosition() end)
		root:CreateButton("Hide panel", function() self.db.profile.show = false self:UpdatePanel() end)
		root:CreateButton("Settings", function() self:OpenSettings() end)
	end)
end

-- Refresh ---------------------------------------------------------------------------------------------

--- Events are live only while the panel is up, so a closed character sheet costs nothing.
function Character:RegisterPanelEvents()
	if not panel then return end
	panel:RegisterEvent("UNIT_STATS")
	panel:RegisterEvent("COMBAT_RATING_UPDATE")
	panel:RegisterEvent("SKILL_LINES_CHANGED")
	panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	panel:RegisterEvent("UNIT_AURA")
	panel:RegisterEvent("SPELL_POWER_CHANGED")
	panel:RegisterEvent("UNIT_RESISTANCES")
	panel:RegisterEvent("UNIT_DEFENSE")
	panel:RegisterEvent("PLAYER_XP_UPDATE")
	panel:RegisterEvent("UPDATE_EXHAUSTION")
	panel:RegisterEvent("PLAYER_UPDATE_RESTING")
	panel:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
	panel:RegisterEvent("CHARACTER_POINTS_CHANGED")
	panel:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	panel:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
	panel:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
end

function Character:UnregisterPanelEvents()
	if self.updateTimer then self:CancelTimer(self.updateTimer) self.updateTimer = nil end
	if panel then panel:UnregisterAllEvents() end
end

--- Coalesce a burst of events into one refresh, and only while the panel is up.
function Character:RequestStatsUpdate(now)
	if not (panel and panel:IsShown()) then return end
	if now then
		if self.updateTimer then self:CancelTimer(self.updateTimer) self.updateTimer = nil end
		self:RunStatsUpdate()
		return
	end
	if self.updateTimer then return end
	self.updateTimer = self:ScheduleTimer("RunStatsUpdate", REFRESH_DELAY)
end

function Character:RunStatsUpdate()
	self.updateTimer = nil
	self:RefreshPanel()
end

-- Lifecycle -------------------------------------------------------------------------------------------

function Character:EnablePanel()
	if not self.panelSlash then
		self.panelSlash = true
		Lodestar:RegisterSlashVerb("character", function() self:TogglePanel() end, "show or hide the stats panel beside the character sheet")
	end
	if self:HookCharacterFrame() then
		self:UpdatePanel()
	else
		self:RegisterEvent("PLAYER_LOGIN", "OnCharacterFrameReady")
	end
end

--- The character sheet is not always there when the module enables (its UI addon can load later).
function Character:OnCharacterFrameReady()
	self:UnregisterEvent("PLAYER_LOGIN")
	if self:HookCharacterFrame() then self:UpdatePanel() end
end

function Character:DisablePanel()
	self:UnregisterAllEvents()
	self:HidePanel()
end

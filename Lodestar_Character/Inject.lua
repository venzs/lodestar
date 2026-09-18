-- Lodestar_Character: hooks the rows into Blizzard's stats pane, refreshes it, and falls back to a
-- small panel of our own when the camelot tables are not there.
--
-- CharacterStatsPaneScrollBoxMixin:UpdateStats (Camelot/CharacterFrame.lua) walks PAPERDOLL_STATCATEGORIES
-- at runtime and calls PAPERDOLL_STATINFO[stat].updateFunc(statFrame, unit, id) for every entry; a row is
-- dropped when the returned value equals the entry's hideAt (a nil return with no hideAt also drops it).
-- Everything here touches plain Lua tables and unsecured frames: no protected calls, nothing in combat.
local Lodestar = _G.Lodestar
local Character = Lodestar:GetModule("Character")
local Stats = Character.Stats

local BLIZZARD_MAX_ROWS = { HITCHANCE = true, CRITCHANCE = true, HASTE = true }
local REFRESH_DELAY = 0.2

local state = {
	injected = false,   -- our categories sit in PAPERDOLL_STATCATEGORIES
	fallback = false,   -- our own panel is in use instead
	wrapped = {},       -- Blizzard stat entries whose showFunc we replaced: [entry] = original showFunc or false
}
local panel -- fallback frame

-- Lookups --------------------------------------------------------------------------------------------

local function categoriesTable() return rawget(_G, "PAPERDOLL_STATCATEGORIES") end
local function statInfoTable() return rawget(_G, "PAPERDOLL_STATINFO") end

--- True when Blizzard's camelot stats pane can take our rows.
function Character:CanInject()
	return type(categoriesTable()) == "table" and type(statInfoTable()) == "table"
		and type(rawget(_G, "PaperDollFrame_SetLabelAndText")) == "function"
		and type(rawget(_G, "PaperDollFrame_UpdateStats")) == "function"
end

function Character:GetInjectionState() return state end

function Character:IsCharacterFrameShown()
	local frame = rawget(_G, "CharacterFrame")
	if not (frame and frame:IsShown()) then return false end
	local doll = rawget(_G, "PaperDollFrame")
	if doll and doll.IsShown and not doll:IsShown() then return false end
	return true
end

--- Blizzard's max-only Hit/Crit/Haste rows are hidden only while the option is on and at least one of
--- our split categories is there to replace them.
function Character:ReplacingMaxRows()
	local db = self.db.profile
	if not db.replaceBlizzardMaxRows then return false end
	local cats = db.categories
	return (cats.melee or cats.ranged or cats.spell) and true or false
end

-- Rows -----------------------------------------------------------------------------------------------

--- Effective hideAt for a row under the current options: the row's own hideAt, else 0 when "hide zero
--- rows" applies to it, else nil.
local function effectiveHideAt(row)
	if row.hideAt ~= nil then return row.hideAt end
	if Character.db.profile.hideZero and row.hideZero ~= false then return 0 end
	return nil
end

--- Run a row's update with Blizzard's updateFunc contract. Errors and "not applicable" both come back as
--- the row's hideAt so the pane drops the row instead of showing stale text.
function Character:RunRow(row, statFrame, unit)
	if unit and unit ~= "player" then return row.hideAtEffective end
	local ok, value = pcall(row.update, statFrame, unit or "player")
	if not ok then
		Lodestar:Debug("Character row %s: %s", row.stat, tostring(value))
		value = nil
	end
	if value == nil then return row.hideAtEffective end
	return value
end

local function statEntryFor(row)
	row.hideAtEffective = effectiveHideAt(row)
	return { stat = row.stat, hideAt = row.hideAtEffective, showFunc = row.showFunc, lodestar = true }
end

--- Our categories in PAPERDOLL_STATCATEGORIES form, honouring the per-category toggles.
function Character:BuildCategories()
	local out = {}
	local enabled = self.db.profile.categories
	for _, category in ipairs(Stats.categories) do
		if enabled[category.key] then
			local stats = {}
			for _, row in ipairs(category.rows) do tinsert(stats, statEntryFor(row)) end
			tinsert(out, { categoryName = category.name, unit = "player", lodestar = true, key = category.key, stats = stats })
		end
	end
	return out
end

--- Our categories currently sitting in Blizzard's table, in display order.
function Character:InjectedCategories()
	local out = {}
	local t = categoriesTable()
	if type(t) ~= "table" then return out end
	for _, category in ipairs(t) do
		if category.lodestar then tinsert(out, category) end
	end
	return out
end

-- Blizzard table surgery -----------------------------------------------------------------------------

local function registerStatInfo()
	local info = statInfoTable()
	for _, category in ipairs(Stats.categories) do
		for _, row in ipairs(category.rows) do
			local r = row
			info[row.stat] = {
				lodestar = true,
				updateFunc = function(statFrame, unit) return Character:RunRow(r, statFrame, unit) end,
			}
		end
	end
end

local function unregisterStatInfo()
	local info = statInfoTable()
	if type(info) ~= "table" then return end
	for stat in pairs(Stats.rowByStat) do
		if type(info[stat]) == "table" and info[stat].lodestar then info[stat] = nil end
	end
end

local function removeCategories()
	local t = categoriesTable()
	if type(t) ~= "table" then return end
	for i = #t, 1, -1 do
		if t[i].lodestar then tremove(t, i) end
	end
end

--- Insert after Blizzard's last player category (the pet category follows; resistances are hard-coded after all of them).
local function insertCategories(categories)
	local t = categoriesTable()
	local at = 0
	for i, category in ipairs(t) do
		if category.unit == "player" or category.unit == nil then at = i end
	end
	for i, category in ipairs(categories) do
		tinsert(t, at + i, category)
	end
end

local function hidden() return false end

--- Wrap or restore the showFunc of Blizzard's HITCHANCE / CRITCHANCE / HASTE entries.
local function applyMaxRowReplacement(on)
	local t = categoriesTable()
	if type(t) ~= "table" then return end
	for _, category in ipairs(t) do
		if not category.lodestar and (category.unit == "player" or category.unit == nil) and type(category.stats) == "table" then
			for _, entry in ipairs(category.stats) do
				if BLIZZARD_MAX_ROWS[entry.stat] then
					if on and state.wrapped[entry] == nil then
						state.wrapped[entry] = entry.showFunc or false
						entry.showFunc = hidden
					elseif not on and state.wrapped[entry] ~= nil then
						entry.showFunc = state.wrapped[entry] or nil
						state.wrapped[entry] = nil
					end
				end
			end
		end
	end
end

local function restoreMaxRows()
	for entry, original in pairs(state.wrapped) do
		entry.showFunc = original or nil
		state.wrapped[entry] = nil
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------

local function doInject()
	removeCategories()
	registerStatInfo()
	insertCategories(Character:BuildCategories())
	applyMaxRowReplacement(Character:ReplacingMaxRows())
end

--- Put our rows into Blizzard's pane, or bring up the fallback panel when that is impossible.
function Character:Inject()
	if not self:IsEnabled() then return end
	if self:CanInject() then
		local ok, err = pcall(doInject)
		if ok then
			state.injected = true
			self:DisableFallbackPanel()
			self:RequestStatsUpdate()
			return true
		end
		Lodestar:Debug("Character: injection failed, using the fallback panel: %s", tostring(err))
		pcall(removeCategories)
		pcall(restoreMaxRows)
	end
	state.injected = false
	self:EnableFallbackPanel()
	return false
end

--- Re-apply the options (category toggles, hideAt, max-row replacement) and refresh the pane.
function Character:RefreshInjection()
	if not self:IsEnabled() then return end
	if state.injected then
		local ok, err = pcall(doInject)
		if not ok then Lodestar:Debug("Character: refresh failed: %s", tostring(err)) end
		self:RequestStatsUpdate()
	elseif state.fallback then
		self:RefreshFallbackPanel()
	else
		self:Inject()
	end
end

function Character:EnableInjection()
	self:RegisterEvent("PLAYER_XP_UPDATE", "OnStatEvent")
	self:RegisterEvent("UPDATE_EXHAUSTION", "OnStatEvent")
	self:RegisterEvent("PLAYER_UPDATE_RESTING", "OnStatEvent")
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "OnStatEvent")
	self:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", "OnStatEvent")
	self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnStatEvent")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnStatEvent")
	self:RegisterEvent("SKILL_LINES_CHANGED", "OnStatEvent")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnStatEvent")
	self:RegisterEvent("UNIT_DEFENSE", "OnStatEvent")
	if IsLoggedIn() then
		self:Inject()
	else
		self:RegisterEvent("PLAYER_LOGIN", "Inject")
	end
end

function Character:DisableInjection()
	self:UnregisterAllEvents()
	if self.updateTimer then self:CancelTimer(self.updateTimer) self.updateTimer = nil end
	if state.injected then
		pcall(removeCategories)
		pcall(restoreMaxRows)
		pcall(unregisterStatInfo)
		state.injected = false
		if self:IsCharacterFrameShown() then pcall(_G.PaperDollFrame_UpdateStats) end
	end
	self:DisableFallbackPanel()
end

-- Refresh --------------------------------------------------------------------------------------------

function Character:OnStatEvent(event, unit)
	if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
	self:RequestStatsUpdate()
end

--- Re-run Blizzard's stats update (or our panel) once, shortly, and only while the sheet is open.
--- Blizzard already refreshes on the combat-rating / stat / equipment events; this covers the rest.
function Character:RequestStatsUpdate(now)
	if not (state.injected or state.fallback) then return end
	if not self:IsCharacterFrameShown() then return end
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
	if not self:IsCharacterFrameShown() then return end
	if state.injected then
		local ok, err = pcall(_G.PaperDollFrame_UpdateStats)
		if not ok then Lodestar:Debug("Character: PaperDollFrame_UpdateStats: %s", tostring(err)) end
	elseif state.fallback then
		self:RefreshFallbackPanel()
	end
end

-- Fallback panel -------------------------------------------------------------------------------------
-- A plain list docked to the character frame's right edge, showing the same rows with the same tooltips.

local ROW_HEIGHT, HEADER_HEIGHT, PANEL_WIDTH = 15, 20, 220

local function rowOnEnter(self)
	if not self.tooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.tooltip)
	if self.tooltip2 then GameTooltip:AddLine(self.tooltip2, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
	if self.tooltip3 then GameTooltip:AddLine(self.tooltip3, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
	GameTooltip:Show()
end

local function acquireRow(index)
	local row = panel.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, panel)
	row:SetSize(PANEL_WIDTH - 16, ROW_HEIGHT)
	row:EnableMouse(true)
	row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Label:SetPoint("LEFT", 4, 0)
	row.Label:SetJustifyH("LEFT")
	row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Value:SetPoint("RIGHT", -4, 0)
	row.Value:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", rowOnEnter)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.rows[index] = row
	return row
end

local function acquireHeader(index)
	local header = panel.headers[index]
	if header then return header end
	header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetJustifyH("LEFT")
	panel.headers[index] = header
	return header
end

local function createPanel()
	panel = CreateFrame("Frame", "LodestarCharacterStatsFrame", UIParent, "BackdropTemplate")
	panel:SetSize(PANEL_WIDTH, 60)
	panel:SetFrameStrata("MEDIUM")
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.8)
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	panel.rows, panel.headers = {}, {}
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel.title:SetText(Lodestar.COLOR .. "Lodestar|r stats")
	panel:Hide()

	local anchor = rawget(_G, "CharacterFrame")
	if anchor then
		panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, -12)
		anchor:HookScript("OnShow", function() if state.fallback then panel:Show() Character:RefreshFallbackPanel() end end)
		anchor:HookScript("OnHide", function() panel:Hide() end)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	end
end

function Character:EnableFallbackPanel()
	if not panel then createPanel() end
	state.fallback = true
	if self:IsCharacterFrameShown() then
		panel:Show()
		self:RefreshFallbackPanel()
	end
end

function Character:DisableFallbackPanel()
	state.fallback = false
	if panel then panel:Hide() end
end

--- Lay the enabled categories and their visible rows out top to bottom. Returns the number of rows shown.
function Character:RefreshFallbackPanel()
	if not panel or not state.fallback then return 0 end
	for _, row in ipairs(panel.rows) do row:Hide() end
	for _, header in ipairs(panel.headers) do header:Hide() end
	local y = -26
	local rowIndex, headerIndex, shown = 0, 0, 0
	for _, category in ipairs(self:BuildCategories()) do
		local first = true
		for _, entry in ipairs(category.stats) do
			local row = Stats.rowByStat[entry.stat]
			if not entry.showFunc or entry.showFunc() then
				rowIndex = rowIndex + 1
				local frame = acquireRow(rowIndex)
				frame.tooltip, frame.tooltip2, frame.tooltip3 = nil, nil, nil
				local value = self:RunRow(row, frame, "player")
				if value ~= entry.hideAt then
					if first then
						headerIndex = headerIndex + 1
						local header = acquireHeader(headerIndex)
						header:ClearAllPoints()
						header:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y)
						header:SetText(category.categoryName)
						header:Show()
						y = y - HEADER_HEIGHT
						first = false
					end
					frame:ClearAllPoints()
					frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
					frame:Show()
					y = y - ROW_HEIGHT
					shown = shown + 1
				else
					rowIndex = rowIndex - 1
					frame:Hide()
				end
			end
		end
	end
	panel:SetHeight(math.max(40, -y + 8))
	panel.shownRows = shown
	return shown
end

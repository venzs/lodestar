-- Lodestar_Guide: the guide window — current step, upcoming steps, prev/next, guide picker.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local WIDTH = 300
local frame
local upcomingLines = {}

local function savePosition()
	local point, _, _, x, y = frame:GetPoint(1)
	Guide.db.profile.steps.pos = { point = point or "TOPRIGHT", x = x or 0, y = y or 0 }
end

local function makeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 26, 20)
	b:SetText(text)
	return b
end

local function createFrame()
	frame = CreateFrame("Frame", "LodestarGuideFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 120)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.65)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	frame:SetScript("OnDragStart", function(self) if not Guide.db.profile.steps.locked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Guide:ShowGuideMenu() end
	end)

	-- Title bar
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", 10, -8)
	frame.title:SetPoint("TOPRIGHT", -108, -8)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.title:SetTextColor(0.31, 0.76, 0.97)

	frame.prev = makeButton(frame, "<")
	frame.prev:SetPoint("TOPRIGHT", -36, -5)
	frame.prev:SetScript("OnClick", function() Guide:PrevStep() end)
	frame.next = makeButton(frame, ">")
	frame.next:SetPoint("TOPRIGHT", -8, -5)
	frame.next:SetScript("OnClick", function() Guide:NextStep() end)
	for _, b in ipairs({ frame.prev, frame.next }) do
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(Guide:InSmartMode() and "Point the arrow at the previous / next thing in the list" or "Previous / next step", 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	-- Sync: re-read the quest log and jump to the step this character is really at.
	frame.sync = makeButton(frame, "Sync", 40)
	frame.sync:SetPoint("TOPRIGHT", -64, -5)
	frame.sync:SetScript("OnClick", function() Guide:SyncToQuestLog() end)
	frame.sync:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Sync to your quest log", 1, 1, 1)
		GameTooltip:AddLine("Finds the step after the last one your completed quests account for. Use it any time the guide seems behind or ahead of you.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	frame.sync:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Current step
	frame.step = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.step:SetPoint("TOPLEFT", 10, -32)
	frame.step:SetWidth(WIDTH - 20)
	frame.step:SetJustifyH("LEFT")
	frame.step:SetJustifyV("TOP")
	frame.step:SetWordWrap(true)
	frame.step:SetTextColor(1, 1, 1)

	frame.meta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.meta:SetPoint("TOPLEFT", frame.step, "BOTTOMLEFT", 0, -2)
	frame.meta:SetWidth(WIDTH - 20)
	frame.meta:SetJustifyH("LEFT")
	frame.meta:SetTextColor(0.7, 0.7, 0.7)

	-- Banner: "New spells available — <trainer> is 120 yd away" (guided mode; smart mode lists it instead).
	frame.banner = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.banner:SetPoint("TOPLEFT", frame.meta, "BOTTOMLEFT", 0, 0)
	frame.banner:SetWidth(WIDTH - 20)
	frame.banner:SetJustifyH("LEFT")
	frame.banner:SetWordWrap(true)
	frame.banner:SetTextColor(1, 0.84, 0)
	frame.banner:SetHeight(1)

	-- Clicking the step text points the arrow at it.
	local click = CreateFrame("Button", nil, frame)
	click:SetPoint("TOPLEFT", frame.step, "TOPLEFT", -2, 2)
	click:SetPoint("BOTTOMRIGHT", frame.meta, "BOTTOMRIGHT", 2, -2)
	click:SetScript("OnClick", function()
		Guide.db.profile.arrow.mode = "AUTO"
		Guide:RetargetArrow()
	end)
	click:SetScript("OnEnter", function(self)
		local step = Guide:CurrentStep()
		if not step then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(Guide.current.name)
		for _, a in ipairs(step.actions) do
			GameTooltip:AddLine("• " .. Guide:ActionText(a), 1, 1, 1, true)
		end
		if step.optional then
			GameTooltip:AddLine("Optional" .. (step.optionalReason and (" — " .. step.optionalReason) or "") .. " (completionist mode)", 0.7, 0.7, 0.7, true)
		end
		if step.go then
			GameTooltip:AddLine(("%s %.1f, %.1f"):format(Guide:MapName(step.go.map), step.go.x, step.go.y), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine("|cffaaaaaaClick: point the arrow here · Right-click: menu|r")
		GameTooltip:Show()
	end)
	click:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.click = click

	frame.divider = frame:CreateTexture(nil, "ARTWORK")
	frame.divider:SetColorTexture(1, 1, 1, 0.12)
	frame.divider:SetHeight(1)
	frame.divider:SetPoint("TOPLEFT", frame.banner, "BOTTOMLEFT", 0, -5)
	frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, 0)

	for i = 1, 8 do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 20, 14)
		if i == 1 then
			row:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 0, -5)
		else
			row:SetPoint("TOPLEFT", upcomingLines[i - 1], "BOTTOMLEFT", 0, -2)
		end
		row.hl = row:CreateTexture(nil, "HIGHLIGHT")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(1, 1, 1, 0.08)
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetAllPoints()
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:SetTextColor(0.55, 0.55, 0.55)
		row.text = fs
		row.SetText = function(self, t) self.text:SetText(t) end
		row:SetScript("OnClick", function(self)
			if self.item then
				Guide:PinSmartItem(self.item)
			elseif self.stepIndex then
				Guide:SetStep(self.stepIndex)
				Guide:EvaluateStep()
			end
		end)
		row:SetScript("OnEnter", function(self)
			if not (self.item or self.stepIndex) then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			if self.item then
				GameTooltip:AddLine(self.item.title, 1, 1, 1)
				GameTooltip:AddLine(self.item.subtitle or "", 0.8, 0.8, 0.8)
				GameTooltip:AddLine("|cffaaaaaaClick: point the arrow at this|r")
			else
				GameTooltip:AddLine("|cffaaaaaaClick: jump to this step|r")
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		upcomingLines[i] = row
	end
end

local KIND_LABEL = { turnin = "|cff7fff7fTurn in|r", objective = "|cffffffffDo|r", available = "|cffffd700Pick up|r", hub = "|cffaaaaaaHub|r", train = "|cff4fc3f7Train|r" }
local OPTIONAL_TAG = " |cff888888(optional)|r"

--- Set the banner text (or clear it) and return the height it takes.
local function setBanner(text)
	if text then
		frame.banner:SetText(text)
		local h = (frame.banner:GetStringHeight() or 12) + 4
		frame.banner:SetHeight(h)
		return h
	end
	frame.banner:SetText("")
	frame.banner:SetHeight(1)
	return 1
end

--- Smart mode: the "next up" list built from the quest log and the map.
local function refreshSmart()
	if frame.sync then frame.sync:Hide() end
	local items = Guide:CollectSmartItems()
	local pinnedItem = Guide:GetPinnedSmartItem()
	frame.title:SetText("Lodestar  |cffaaaaaasmart mode|r")
	local top = items[1]
	local pinnedShown
	if pinnedItem then
		for _, it in ipairs(items) do if it.kind == pinnedItem.kind and it.questID == pinnedItem.questID and it.x == pinnedItem.x then pinnedShown = it end end
	end
	local lead = pinnedShown or top
	if lead then
		frame.step:SetText(("%s %s"):format(KIND_LABEL[lead.kind] or "", lead.title))
		frame.meta:SetText(("%s%s"):format(lead.subtitle or "", lead.dist and ("  ·  " .. math.floor(lead.dist) .. " yd") or (lead.noPosition and "  ·  |cff888888location unknown|r" or "")))
	else
		frame.step:SetText("Nothing to do here yet. Pick up quests at the nearest hub, or /lode record start and play.")
		frame.meta:SetText("")
	end
	local shown = 0
	local n = 0
	for _, it in ipairs(items) do
		if it ~= lead then
			n = n + 1
			if n > 8 then break end
			local row = upcomingLines[n]
			row.item, row.stepIndex = it, nil
			row:SetText(("%s %s%s"):format(KIND_LABEL[it.kind] or "", it.title,
				it.dist and ("  |cff666666" .. math.floor(it.dist) .. " yd|r") or (it.noPosition and "  |cff666666?|r" or "")))
			row:Show()
			shown = shown + 1
		end
	end
	for i = shown + 1, 8 do
		local row = upcomingLines[i]
		row.item, row.stepIndex = nil, nil
		row:SetText("")
		row:Hide()
	end
	local bannerH = setBanner(nil)
	local height = 32 + frame.step:GetStringHeight() + 4 + 14 + bannerH + 10 + shown * 16 + 10
	frame:SetHeight(math.max(70, height))
end

--- Guided mode banner: the class trainer suggestion, when there is one.
local function trainerBanner()
	local t = Guide:TrainerSuggestion()
	if not t then return nil end
	return ("|cffffd700New spells available|r — %s is %d yd away"):format(t.name or "your class trainer", math.floor(t.dist or 0))
end

--- "Your quest log says you're further along" hint, recomputed at most every 5 s.
local syncHint = { at = 0 }
local function syncBanner(guide, stepIndex)
	local now = GetTime()
	if now - syncHint.at > 5 or syncHint.guide ~= guide or syncHint.step ~= stepIndex then
		syncHint.at, syncHint.guide, syncHint.step = now, guide, stepIndex
		local start, _, open = Guide:SuggestStartIndex(guide)
		syncHint.start, syncHint.open = start, open
	end
	if syncHint.start and syncHint.start > stepIndex + 1 then
		return ("|cff7fff7fYou look further along|r — quest log points at step %d. Click Sync."):format(syncHint.start)
	end
	if syncHint.open and syncHint.open > 0 and syncHint.start and syncHint.start <= stepIndex then
		return ("|cffaaaaaa%d earlier step%s still open (press <)|r"):format(syncHint.open, syncHint.open == 1 and "" or "s")
	end
	return nil
end

function Guide:RefreshStepFrame()
	if not frame or not frame:IsShown() then return end
	local guide, step = self.current, self:CurrentStep()
	if not guide or not step then
		refreshSmart()
		return
	end
	if frame.sync then frame.sync:Show() end
	frame.title:SetText(("%s  |cffaaaaaa%d/%d%s|r"):format(guide.name, step.index, #guide.steps, self.finished and " · done" or ""))
	frame.step:SetText(self:StepText(step) .. (step.optional and OPTIONAL_TAG or ""))
	local meta = {}
	if self.finished then tinsert(meta, "|cff7fff7fGuide finished|r — > for smart mode, right-click for other guides") end
	if step.go then tinsert(meta, ("%s %.1f, %.1f"):format(self:MapName(step.go.map), step.go.x, step.go.y)) end
	local dist = self:GetArrowDistance()
	local target = self:GetArrowTarget()
	if dist and target and target.kind == "guide" then tinsert(meta, ("%d yd"):format(dist)) end
	frame.meta:SetText(table.concat(meta, "  ·  "))
	local bannerH = setBanner(trainerBanner() or syncBanner(guide, step.index))

	-- Upcoming: the next steps that apply to this character (other classes' and, in speed-run mode,
	-- optional steps are left out, as the engine will skip them).
	local n = self.db.profile.steps.upcoming or 3
	local pf = self:PlayerFilters()
	local upcoming = {}
	for idx = step.index + 1, #guide.steps do
		if #upcoming >= n then break end
		local s = guide.steps[idx]
		if self:StepApplies(s, pf) then tinsert(upcoming, s) end
	end
	local shown = 0
	for i = 1, 8 do
		local row = upcomingLines[i]
		local nextStep = upcoming[i]
		row.item = nil
		if nextStep then
			row.stepIndex = nextStep.index
			row:SetText(("%d. %s%s"):format(nextStep.index, self:StepText(nextStep), nextStep.optional and OPTIONAL_TAG or ""))
			row:Show()
			shown = shown + 1
		else
			row.stepIndex = nil
			row:SetText("")
			row:Hide()
		end
	end
	local height = 32 + frame.step:GetStringHeight() + 4 + 14 + bannerH + 10 + shown * 16 + 10
	frame:SetHeight(math.max(70, height))
end

function Guide:UpdateStepFrame()
	if not frame then return end
	local cfg = self.db.profile.steps
	if not self:IsEnabled() or not cfg.show then
		frame:Hide()
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(cfg.pos.point or "TOPRIGHT", UIParent, cfg.pos.point or "TOPRIGHT", cfg.pos.x or -40, cfg.pos.y or -200)
	frame:SetScale(cfg.scale or 1)
	frame:SetBackdropBorderColor(cfg.locked and 0.4 or 0.3, cfg.locked and 0.4 or 0.75, cfg.locked and 0.4 or 1, 0.9)
	frame:Show()
	self:RefreshStepFrame()
end

function Guide:ShowGuideMenu()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then self:OpenSettings() return end
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Lodestar Guide")
		local applicable = self:ApplicableGuides(true)
		local level = UnitLevel("player")
		if #applicable == 0 then
			root:CreateButton("|cff888888No guides for this character|r", function() end)
		end
		for _, g in ipairs(applicable) do
			local outleveled = g.maxLevel and level > g.maxLevel
			local label = g.name .. (g.minLevel and (" (" .. g.minLevel .. "-" .. g.maxLevel .. ")") or "")
			if outleveled then label = "|cff888888" .. label .. " · outleveled|r" end
			root:CreateRadio(label,
				function() return self.current and self.current.name == g.name end,
				function() self:LoadGuide(g.name) end)
		end
		root:CreateRadio("Smart mode (no guide) — nearest turn-ins, objectives and pick-ups", function() return self.current == nil end, function() self:UnloadGuide() end)
		root:CreateDivider()
		if self.current then
			root:CreateButton("Next step", function() self:NextStep() end)
			root:CreateButton("Previous step", function() self:PrevStep() end)
			root:CreateButton("Restart this guide", function() self:LoadGuide(self.current.name, 1) end)
		else
			root:CreateButton("Point at the next thing in the list", function() self:NextStep() end)
			root:CreateButton("Point at the previous thing", function() self:PrevStep() end)
			root:CreateButton("Print the list to chat", function() self:PrintNextUp() end)
		end
		root:CreateDivider()
		root:CreateCheckbox("Locked", function() return self.db.profile.steps.locked end,
			function() self.db.profile.steps.locked = not self.db.profile.steps.locked self:UpdateStepFrame() end)
		root:CreateCheckbox("Auto-advance", function() return self.db.profile.steps.autoAdvance end,
			function() self.db.profile.steps.autoAdvance = not self.db.profile.steps.autoAdvance end)
		root:CreateCheckbox("Completionist (do optional quests)", function() return self.db.profile.steps.completionist end,
			function() self:SetCompletionist(not self.db.profile.steps.completionist) end)
		root:CreateButton("Hide window", function() self.db.profile.steps.show = false self:UpdateStepFrame() end)
		root:CreateButton("Settings", function() self:OpenSettings() end)
	end)
end

function Guide:EnableStepFrame()
	if not frame then createFrame() end
	self:UpdateStepFrame()
	self.stepFrameTicker = self:ScheduleRepeatingTimer("RefreshStepFrame", 2)
end

function Guide:DisableStepFrame()
	if self.stepFrameTicker then self:CancelTimer(self.stepFrameTicker) self.stepFrameTicker = nil end
	if frame then frame:Hide() end
end

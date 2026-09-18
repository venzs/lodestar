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
	frame.title:SetPoint("TOPRIGHT", -70, -8)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.title:SetTextColor(0.31, 0.76, 0.97)

	frame.prev = makeButton(frame, "<")
	frame.prev:SetPoint("TOPRIGHT", -36, -5)
	frame.prev:SetScript("OnClick", function() Guide:PrevStep() end)
	frame.next = makeButton(frame, ">")
	frame.next:SetPoint("TOPRIGHT", -8, -5)
	frame.next:SetScript("OnClick", function() Guide:NextStep() end)

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
			GameTooltip:AddLine("• " .. Guide.Parser.ActionText(a, function(id) return C_QuestLog.GetTitleForQuestID(id) or ("quest #" .. id) end), 1, 1, 1, true)
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
	frame.divider:SetPoint("TOPLEFT", frame.meta, "BOTTOMLEFT", 0, -5)
	frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, 0)

	for i = 1, 6 do
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWidth(WIDTH - 20)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:SetTextColor(0.55, 0.55, 0.55)
		if i == 1 then
			fs:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 0, -5)
		else
			fs:SetPoint("TOPLEFT", upcomingLines[i - 1], "BOTTOMLEFT", 0, -2)
		end
		upcomingLines[i] = fs
	end
end

function Guide:RefreshStepFrame()
	if not frame or not frame:IsShown() then return end
	local guide, step = self.current, self:CurrentStep()
	if not guide or not step then
		frame.title:SetText("Lodestar Guide")
		frame.step:SetText(#self.guides > 0 and "No guide loaded. Right-click to pick one." or "No guides installed.\nInstall a Lodestar guide pack, or /lode record start to make your own.")
		frame.meta:SetText("")
		for i = 1, 6 do upcomingLines[i]:SetText("") end
		frame:SetHeight(90)
		return
	end
	frame.title:SetText(("%s  |cffaaaaaa%d/%d|r"):format(guide.name, step.index, #guide.steps))
	frame.step:SetText(self:StepText(step))
	local meta = {}
	if step.go then tinsert(meta, ("%s %.1f, %.1f"):format(self:MapName(step.go.map), step.go.x, step.go.y)) end
	local dist = self:GetArrowDistance()
	local target = self:GetArrowTarget()
	if dist and target and target.kind == "guide" then tinsert(meta, ("%d yd"):format(dist)) end
	frame.meta:SetText(table.concat(meta, "  ·  "))

	local n = self.db.profile.steps.upcoming or 3
	local shown = 0
	for i = 1, 6 do
		local next = guide.steps[step.index + i]
		if i <= n and next then
			upcomingLines[i]:SetText(("%d. %s"):format(next.index, self:StepText(next)))
			shown = shown + 1
		else
			upcomingLines[i]:SetText("")
		end
	end
	local height = 32 + frame.step:GetStringHeight() + 4 + 14 + 10 + shown * 14 + 10
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
		if #applicable == 0 then
			root:CreateButton("|cff888888No guides for this character|r", function() end)
		end
		for _, g in ipairs(applicable) do
			root:CreateRadio(g.name .. (g.minLevel and (" (" .. g.minLevel .. "-" .. g.maxLevel .. ")") or ""),
				function() return self.current and self.current.name == g.name end,
				function() self:LoadGuide(g.name) end)
		end
		root:CreateDivider()
		root:CreateButton("Next step", function() self:NextStep() end)
		root:CreateButton("Previous step", function() self:PrevStep() end)
		root:CreateButton("Restart this guide", function() if self.current then self:LoadGuide(self.current.name, 1) end end)
		root:CreateDivider()
		root:CreateCheckbox("Locked", function() return self.db.profile.steps.locked end,
			function() self.db.profile.steps.locked = not self.db.profile.steps.locked self:UpdateStepFrame() end)
		root:CreateCheckbox("Auto-advance", function() return self.db.profile.steps.autoAdvance end,
			function() self.db.profile.steps.autoAdvance = not self.db.profile.steps.autoAdvance end)
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

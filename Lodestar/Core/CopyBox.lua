-- Lodestar core: a shared "copy this text" window (Ctrl+C friendly). Used for chat URLs, copy-chat
-- and exported guides.
local Lodestar = _G.Lodestar

local copyFrame

local function ensureCopyFrame()
	if copyFrame then return copyFrame end
	copyFrame = CreateFrame("Frame", "LodestarCopyFrame", UIParent, "BackdropTemplate")
	copyFrame:SetSize(620, 380)
	copyFrame:SetPoint("CENTER")
	copyFrame:SetFrameStrata("DIALOG")
	copyFrame:SetMovable(true)
	copyFrame:EnableMouse(true)
	copyFrame:SetClampedToScreen(true)
	copyFrame:RegisterForDrag("LeftButton")
	copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
	copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
	copyFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	copyFrame:Hide()
	tinsert(UISpecialFrames, "LodestarCopyFrame") -- Escape closes it

	copyFrame.title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	copyFrame.title:SetPoint("TOP", 0, -16)

	local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local scroll = CreateFrame("ScrollFrame", "LodestarCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 18, -40)
	scroll:SetPoint("BOTTOMRIGHT", -34, 18)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(560)
	edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
	edit:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
	scroll:SetScrollChild(edit)
	copyFrame.edit = edit
	return copyFrame
end

--- Show text in a selectable box. `title` is optional.
function Lodestar:ShowCopyBox(text, title)
	local frame = ensureCopyFrame()
	frame.title:SetText(self.COLOR .. "Lodestar|r — " .. (title or "Ctrl+C to copy, Escape to close"))
	frame.edit:SetText(text or "")
	frame:Show()
	frame.edit:SetFocus()
	frame.edit:HighlightText()
end

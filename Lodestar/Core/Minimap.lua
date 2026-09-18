-- Lodestar core: minimap button (LibDataBroker launcher + LibDBIcon) and addon compartment entry.
local Lodestar = _G.Lodestar
local L = Lodestar.L

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

local function fillTooltip(tooltip)
	tooltip:AddDoubleLine(Lodestar.COLOR .. "Lodestar|r", "|cffaaaaaa" .. Lodestar.version .. "|r")
	for _, fn in ipairs(Lodestar.tooltipProviders) do
		local ok, err = pcall(fn, tooltip)
		if not ok then Lodestar:Debug("tooltip provider failed: %s", tostring(err)) end
	end
	tooltip:AddLine(" ")
	tooltip:AddLine("|cffaaaaaa" .. L["Left-click: settings"] .. "|r")
	tooltip:AddLine("|cffaaaaaa" .. L["Right-click: module toggles"] .. "|r")
end

local function onClick(_, button)
	if button == "RightButton" then
		Lodestar:ShowModuleMenu()
	else
		Lodestar:OpenConfig()
	end
end

function Lodestar:SetupMinimap()
	if self.ldb then return end
	self.ldb = LDB:NewDataObject("Lodestar", {
		type = "launcher",
		text = "Lodestar",
		icon = "Interface\\Icons\\INV_Misc_Map_01",
		OnClick = onClick,
		OnTooltipShow = fillTooltip,
	})
	DBIcon:Register("Lodestar", self.ldb, self.db.profile.minimap)
	self:UpdateMinimapButton()
end

function Lodestar:UpdateMinimapButton()
	if not self.ldb then return end
	DBIcon:Refresh("Lodestar", self.db.profile.minimap)
	if self.db.profile.minimap.hide then DBIcon:Hide("Lodestar") else DBIcon:Show("Lodestar") end
end

-- Right-click menu: one checkbox per module. Uses the modern Menu API (12.x) when present.
function Lodestar:ShowModuleMenu()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		self:OpenConfig()
		return
	end
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Lodestar " .. L["Modules"])
		for _, module in ipairs(self.moduleList) do
			root:CreateCheckbox(module.displayName,
				function() return self:IsModuleEnabled(module.key) end,
				function() self:SetModuleEnabled(module.key, not self:IsModuleEnabled(module.key)) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Open settings"], function() self:OpenConfig() end)
	end)
end

-- Addon compartment (the drop-down next to the minimap) -----------------------------

function _G.Lodestar_OnAddonCompartmentClick(_, buttonName)
	onClick(nil, buttonName)
end

function _G.Lodestar_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	fillTooltip(GameTooltip)
	GameTooltip:Show()
end

function _G.Lodestar_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

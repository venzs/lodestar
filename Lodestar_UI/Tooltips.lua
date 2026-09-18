-- Lodestar_UI: tooltip extras — IDs, target of target, class colors, guild rank, item level.
local Lodestar = _G.Lodestar
local UI = Lodestar:GetModule("UI")

local hooked = false
local GREY = { 0.6, 0.6, 0.6 }

local function cfg() return UI.db.profile.tooltip end

local function leftLine(tooltip, i)
	local name = tooltip:GetName()
	return name and _G[name .. "TextLeft" .. i]
end

local function addID(tooltip, label, id)
	if id then
		tooltip:AddDoubleLine(label, tostring(id), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	end
end

-- Units ----------------------------------------------------------------------------

local function decorateUnit(tooltip)
	local c = cfg()
	local _, unit = TooltipUtil.GetDisplayedUnit(tooltip)
	if not unit or not UnitExists(unit) then return end
	local isPlayer = UnitIsPlayer(unit)

	if isPlayer and c.classColors then
		local _, classFile = UnitClass(unit)
		local line = leftLine(tooltip, 1)
		if line and classFile then
			local color = Lodestar.ClassColor(classFile)
			line:SetTextColor(color.r, color.g, color.b)
		end
	end

	if isPlayer and c.guild then
		local guildName, rankName = GetGuildInfo(unit)
		if guildName and rankName then
			for i = 2, 3 do
				local line = leftLine(tooltip, i)
				local text = line and line:GetText()
				if text and (text == guildName or text == ("<%s>"):format(guildName)) then
					line:SetText(("<%s> %s"):format(guildName, rankName))
					break
				end
			end
		end
	end

	if c.targetOfTarget and UnitExists(unit .. "target") then
		local target = unit .. "target"
		local name
		if UnitIsUnit(target, "player") then
			name = "|cffff4040<< YOU >>|r"
		elseif UnitIsPlayer(target) then
			local _, classFile = UnitClass(target)
			name = Lodestar.ClassColorText(UnitName(target) or "?", classFile)
		else
			name = UnitName(target) or "?"
		end
		tooltip:AddDoubleLine("Targeting", name, GREY[1], GREY[2], GREY[3], 1, 1, 1)
	end

	if c.ids and not isPlayer then
		addID(tooltip, "NPC ID", Lodestar.NpcIDFromGUID(UnitGUID(unit)))
	end
end

local function onUnitTooltip(tooltip)
	if not UI:IsEnabled() or tooltip ~= GameTooltip then return end
	local ok, err = pcall(decorateUnit, tooltip)
	if not ok then Lodestar:Debug("unit tooltip: %s", tostring(err)) end
end

-- Items ----------------------------------------------------------------------------

local function decorateItem(tooltip, data)
	local c = cfg()
	local _, link, itemID = TooltipUtil.GetDisplayedItem(tooltip)
	itemID = itemID or (data and data.id)
	if c.itemLevel and link then
		-- GetItemInfoInstant returns itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID.
		local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
		if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_BAG" then
			local ilvl = C_Item.GetDetailedItemLevelInfo(link)
			if ilvl and ilvl > 0 then
				tooltip:AddDoubleLine("Item level", tostring(ilvl), GREY[1], GREY[2], GREY[3], 1, 1, 1)
			end
		end
	end
	if c.ids then addID(tooltip, "Item ID", itemID) end
end

local function onItemTooltip(tooltip, data)
	if not UI:IsEnabled() then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local ok, err = pcall(decorateItem, tooltip, data)
	if not ok then Lodestar:Debug("item tooltip: %s", tostring(err)) end
end

-- Spells ---------------------------------------------------------------------------

local function onSpellTooltip(tooltip, data)
	if not UI:IsEnabled() or not cfg().ids then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local id = data and data.id
	if not id then
		local _, spellID = TooltipUtil.GetDisplayedSpell(tooltip)
		id = spellID
	end
	pcall(addID, tooltip, "Spell ID", id)
end

function UI:EnableTooltips()
	if hooked then return end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then
		Lodestar:Debug("TooltipDataProcessor unavailable; tooltip extras disabled")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onSpellTooltip)
	hooked = true
end

function UI:DisableTooltips()
	-- Post-calls cannot be removed; the callbacks check IsEnabled().
end

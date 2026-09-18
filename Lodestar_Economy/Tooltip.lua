-- Lodestar_Economy: vendor and auction prices in item tooltips (TooltipDataProcessor API).
local Lodestar = _G.Lodestar
local Economy = Lodestar:GetModule("Economy")

local FormatMoney, FormatDuration = Lodestar.FormatMoney, Lodestar.FormatDuration

local hooked = false

local function stackCountFor(tooltip)
	local owner = tooltip:GetOwner()
	if not owner then return 1 end
	local ok, count = pcall(function()
		if owner.GetBagID and owner.GetID then
			local info = C_Container.GetContainerItemInfo(owner:GetBagID(), owner:GetID())
			return info and info.stackCount
		end
		if owner.count and type(owner.count) == "number" then return owner.count end
	end)
	if ok and type(count) == "number" and count > 1 then return count end
	return 1
end

local function ageText(epoch)
	local age = time() - (epoch or 0)
	if age < 60 then return "just now" end
	return FormatDuration(age) .. " ago"
end

local function onItemTooltip(tooltip, data)
	if not Economy:IsEnabled() then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip and tooltip ~= _G.ShoppingTooltip1 and tooltip ~= _G.ShoppingTooltip2 then return end
	local cfg = Economy.db.profile.tooltip
	local _, link, itemID = TooltipUtil.GetDisplayedItem(tooltip)
	itemID = itemID or (data and data.id)
	if not itemID then return end

	if cfg.vendorPrice and not (MerchantFrame and MerchantFrame:IsShown()) then
		local sellPrice = select(11, C_Item.GetItemInfo(link or itemID))
		if sellPrice and sellPrice > 0 then
			local count = cfg.stackTotals and stackCountFor(tooltip) or 1
			if count > 1 then
				tooltip:AddDoubleLine("Vendor", ("%s (%d = %s)"):format(FormatMoney(sellPrice), count, FormatMoney(sellPrice * count)), 0.6, 0.6, 0.6, 1, 1, 1)
			else
				tooltip:AddDoubleLine("Vendor", FormatMoney(sellPrice), 0.6, 0.6, 0.6, 1, 1, 1)
			end
		end
	end

	if cfg.ahPrice then
		local price = Economy:GetAHPrice(itemID)
		if price then
			local count = cfg.stackTotals and stackCountFor(tooltip) or 1
			local text = FormatMoney(price.p)
			if count > 1 then text = ("%s (%d = %s)"):format(text, count, FormatMoney(price.p * count)) end
			tooltip:AddDoubleLine("Auction (" .. ageText(price.t) .. ")", text, 0.6, 0.6, 0.6, 1, 1, 1)
		end
	end
end

function Economy:EnableTooltip()
	if hooked then return end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
		hooked = true
	else
		Lodestar:Debug("TooltipDataProcessor unavailable; vendor prices in tooltips disabled")
	end
end

function Economy:DisableTooltip()
	-- Post-calls cannot be removed; onItemTooltip checks IsEnabled().
end

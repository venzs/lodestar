-- Lodestar_Economy: auto-sell junk and auto-repair at vendors.
local Lodestar = _G.Lodestar
local Economy = Lodestar:GetModule("Economy")

local FormatMoney = Lodestar.FormatMoney

local SELL_INTERVAL = 0.15 -- seconds between sells; the server rejects a burst of UseContainerItem calls
local queue = {}
local sellTimer, soldCount, soldValue
-- Tracked from MERCHANT_SHOW/CLOSED rather than MerchantFrame:IsShown(): on this client the panel is opened
-- by the interaction manager, not by MERCHANT_SHOW, so the frame is still hidden while we handle the event.
local merchantOpen = false

local function numBags()
	return _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4
end

local function sellPriceOf(link)
	if not link then return 0 end
	local price = select(11, C_Item.GetItemInfo(link))
	return tonumber(price) or 0
end

local function isJunk(info)
	if not info or not info.hyperlink then return false end
	if info.quality ~= Enum.ItemQuality.Poor then return false end
	if info.hasNoValue or info.isLocked then return false end
	if Economy.db.profile.merchant.keep[info.itemID] then return false end
	return true
end

local function sellNext()
	local entry = tremove(queue, 1)
	if not entry then
		if sellTimer then Economy:CancelTimer(sellTimer) sellTimer = nil end
		if soldCount > 0 and Economy.db.profile.merchant.announce then
			Lodestar:Msg("Sold %d junk item%s for %s.", soldCount, soldCount == 1 and "" or "s", FormatMoney(soldValue))
		end
		return
	end
	if not merchantOpen then
		wipe(queue)
		return sellNext()
	end
	local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
	if isJunk(info) and info.itemID == entry.itemID then
		C_Container.UseContainerItem(entry.bag, entry.slot)
		soldCount = soldCount + 1
		soldValue = soldValue + sellPriceOf(info.hyperlink) * (info.stackCount or 1)
	end
end

function Economy:SellJunk()
	-- A second MERCHANT_SHOW while a queue is draining must not orphan the running timer.
	if sellTimer then self:CancelTimer(sellTimer) sellTimer = nil end
	wipe(queue)
	soldCount, soldValue = 0, 0
	for bag = 0, numBags() do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if isJunk(info) then
				tinsert(queue, { bag = bag, slot = slot, itemID = info.itemID })
			end
		end
	end
	if #queue == 0 then return end
	sellNext()
	-- Always schedule: with a single item the first tick finds the queue empty, prints the summary and cancels itself.
	sellTimer = self:ScheduleRepeatingTimer(sellNext, SELL_INTERVAL)
end

function Economy:AutoRepair()
	if not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	local cfg = self.db.profile.merchant
	local guildPart = 0
	if cfg.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
		-- Mirror Blizzard's guild-repair button: the usable amount is the bank balance capped by the daily
		-- withdraw limit (-1 = unlimited); the server bills anything beyond that to the player's own gold.
		local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or -1
		local bank = GetGuildBankMoney and GetGuildBankMoney() or 0
		local guildAvail = (limit == -1) and bank or math.min(limit, bank)
		guildPart = math.max(0, math.min(cost, guildAvail))
	end
	local personal = cost - guildPart
	if personal > 0 and GetMoney() < personal then
		if cfg.announce then Lodestar:Msg("Repairs cost %s — not enough gold.", FormatMoney(cost)) end
		return
	end
	RepairAllItems(guildPart > 0)
	if cfg.announce then
		local how = ""
		if guildPart >= cost then
			how = " (guild funds)"
		elseif guildPart > 0 then
			how = (" (%s guild funds, %s personal)"):format(FormatMoney(guildPart), FormatMoney(personal))
		end
		Lodestar:Msg("Repaired for %s%s.", FormatMoney(cost), how)
	end
end

function Economy:MERCHANT_SHOW()
	merchantOpen = true
	if IsShiftKeyDown() then return end
	local cfg = self.db.profile.merchant
	-- Learn the copper-per-durability-point rate from this vendor's quoted cost BEFORE repairing:
	-- afterwards nothing is missing and there is nothing left to measure. This runs whether or not
	-- auto-repair is on, because the estimate is useful to anyone who repairs by hand.
	if self.CalibrateRepair then self:CalibrateRepair() end
	-- Repair first so the repair cost is not affected by the junk we are about to sell (it isn't, but
	-- the order keeps chat readable: repair line, then the sale line).
	if cfg.repair then self:AutoRepair() end
	if cfg.sellJunk then self:SellJunk() end
end

function Economy:MERCHANT_CLOSED()
	merchantOpen = false
	wipe(queue)
	if sellTimer then self:CancelTimer(sellTimer) sellTimer = nil end
end

--- /lode keep [item link] toggles an item's protection from auto-sell; no argument lists them.
local function handleKeep(rest)
	local keep = Economy.db.profile.merchant.keep
	local itemID = tonumber(rest) or (rest and tonumber(rest:match("item:(%d+)")))
	if not itemID then
		local list = {}
		for id in pairs(keep) do
			local name = C_Item.GetItemNameByID(id)
			tinsert(list, (name or tostring(id)))
		end
		Lodestar:Say("Protected from auto-sell: %s", #list > 0 and table.concat(list, ", ") or "nothing")
		return
	end
	local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	if keep[itemID] then
		keep[itemID] = nil
		Lodestar:Say("%s will be auto-sold again.", name)
	else
		keep[itemID] = true
		Lodestar:Say("%s is protected from auto-sell.", name)
	end
end

function Economy:EnableMerchant()
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("MERCHANT_CLOSED")
	if not self.keepSlash then
		self.keepSlash = true
		Lodestar:RegisterSlashVerb("keep", handleKeep, "protect an item from auto-sell: /lode keep [item link]")
	end
end

function Economy:DisableMerchant()
	self:UnregisterEvent("MERCHANT_SHOW")
	self:UnregisterEvent("MERCHANT_CLOSED")
	self:MERCHANT_CLOSED()
end

-- Lodestar_Economy: what is in the bags and what repairs will cost.
--
-- Two questions a Classic leveller asks constantly and the default UI answers for neither: "is it
-- worth walking back to a vendor yet" and "can I afford to repair when I get there". The first
-- needs the vendor value sitting in the bags, the second needs a cost you can see BEFORE you are
-- standing at the merchant -- GetRepairAllCost only answers while a repair-capable vendor is open,
-- which is exactly when you no longer need to plan.
--
-- So the repair estimate calibrates itself. Every time a real repair cost is seen at a vendor it is
-- divided by the durability points actually missing, and that copper-per-point rate is remembered.
-- After one repair the estimate is the player's own gear at the player's own level, which beats any
-- table we could ship -- and until then nothing is claimed at all.
local Lodestar = _G.Lodestar
local Economy = Lodestar:GetModule("Economy")

local EQUIP_SLOTS = 18          -- head .. ranged: every slot that can carry durability
local RATE_SAMPLES = 10         -- repairs averaged into the copper-per-point rate
local MIN_POINTS = 20           -- below this a repair is too small to calibrate from

local function readable(v)
	return v ~= nil and (canaccessvalue == nil or canaccessvalue(v))
end

local function num(v)
	return (readable(v) and type(v) == "number") and v or nil
end

local function numBags()
	return _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4
end

-- Bags ------------------------------------------------------------------------------

--- Vendor value of one stack, or 0 when the item has none or the client will not say.
local function stackValue(info)
	if type(info) ~= "table" or not info.hyperlink or info.hasNoValue then return 0 end
	local price = select(11, C_Item.GetItemInfo(info.hyperlink))
	price = num(price) or 0
	return price * (num(info.stackCount) or 1)
end

--- Everything worth knowing about the bags in one walk:
---   { free, used, slots, value, junkValue, junkCount, cheapest = { bag, slot, link, value } }
--- `value` counts only what a vendor would actually pay, so quest items and soulbound junk with no
--- sell price contribute nothing rather than inflating the number.
function Economy:ScanBags()
	local C = C_Container
	local out = { free = 0, used = 0, slots = 0, value = 0, junkValue = 0, junkCount = 0 }
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
	local poor = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
	for bag = 0, numBags() do
		local slots = num(C.GetContainerNumSlots(bag))
		if slots then
			out.slots = out.slots + slots
			for slot = 1, slots do
				local info = C.GetContainerItemInfo(bag, slot)
				if type(info) ~= "table" or not info.hyperlink then
					out.free = out.free + 1
				else
					out.used = out.used + 1
					local value = stackValue(info)
					out.value = out.value + value
					if info.quality == poor and not info.hasNoValue then
						out.junkValue = out.junkValue + value
						out.junkCount = out.junkCount + 1
					end
					-- The cheapest sellable stack is the one to drop when the bags are full and
					-- something better just dropped. Worthless items are not candidates: destroying
					-- them frees a slot but the player may be carrying them on purpose.
					if value > 0 and (not out.cheapest or value < out.cheapest.value) then
						out.cheapest = { bag = bag, slot = slot, link = info.hyperlink, value = value }
					end
				end
			end
		end
	end
	return out
end

-- Repairs ---------------------------------------------------------------------------

--- Durability points missing across every equipped slot, and the lowest percentage. nil when the
--- client does not expose durability at all.
function Economy:MissingDurability()
	local get = _G.GetInventoryItemDurability
	if type(get) ~= "function" then return nil end
	local missing, lowest = 0, nil
	for slot = 1, EQUIP_SLOTS do
		local cur, max = get(slot)
		cur, max = num(cur), num(max)
		if cur and max and max > 0 then
			missing = missing + (max - cur)
			local pct = cur / max * 100
			if not lowest or pct < lowest then lowest = pct end
		end
	end
	return missing, lowest
end

--- Learn from a real repair: cost per durability point, averaged over the last few repairs. Tiny
--- repairs are ignored -- the server rounds, so a 3-point repair gives a rate that is mostly
--- rounding error and would drag the average somewhere useless.
function Economy:NoteRepairCost(cost, missing)
	cost, missing = num(cost), num(missing)
	if not (cost and missing) or missing < MIN_POINTS or cost <= 0 then return end
	local store = self.db.global.repair
	store.samples = type(store.samples) == "table" and store.samples or {}
	tinsert(store.samples, cost / missing)
	while #store.samples > RATE_SAMPLES do tremove(store.samples, 1) end
	local sum = 0
	for _, v in ipairs(store.samples) do sum = sum + v end
	store.perPoint = sum / #store.samples
	store.at = time()
end

--- What a full repair would cost right now, in copper, or nil when nothing has been learned yet.
--- Deliberately nil rather than a guess: "about 40 silver" from a made-up rate is worse than saying
--- nothing, because the player will plan around it.
function Economy:EstimatedRepairCost()
	local perPoint = num(self.db.global.repair.perPoint)
	if not perPoint then return nil end
	local missing = self:MissingDurability()
	if not missing or missing <= 0 then return 0 end
	return math.floor(missing * perPoint)
end

--- Called from the merchant handler while a repair-capable vendor is open, before repairing.
function Economy:CalibrateRepair()
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost = GetRepairAllCost and GetRepairAllCost()
	local missing = self:MissingDurability()
	self:NoteRepairCost(cost, missing)
end

-- Reporting -------------------------------------------------------------------------

--- `/lode bags`: free slots, what the bags are worth, and what a repair would cost.
function Economy:PrintBagReport()
	local b = self:ScanBags()
	Lodestar:Say("Bags: %d of %d slots free.", b.free, b.slots)
	if b.value > 0 then
		Lodestar:Say("  vendor value: %s (greys: %s in %d item%s)",
			Lodestar.FormatMoney(b.value), Lodestar.FormatMoney(b.junkValue), b.junkCount, b.junkCount == 1 and "" or "s")
	else
		Lodestar:Say("  nothing a vendor would pay for")
	end
	local missing, lowest = self:MissingDurability()
	local estimate = self:EstimatedRepairCost()
	if missing and missing > 0 then
		if estimate then
			Lodestar:Say("  repairs: about %s (%d points missing, lowest slot %d%%)",
				Lodestar.FormatMoney(estimate), missing, math.floor(lowest or 0))
		else
			Lodestar:Say("  repairs: %d durability points missing -- the cost is learned at your first vendor repair", missing)
		end
	elseif missing then
		Lodestar:Say("  gear is fully repaired")
	end
	if b.free <= 1 and b.cheapest then
		Lodestar:Say("  cheapest sellable stack: %s (%s)", b.cheapest.link, Lodestar.FormatMoney(b.cheapest.value))
	end
end

--- One line on the minimap tooltip, and only when there is something to say.
local function tooltipLine(tooltip)
	if not Economy:IsEnabled() or not Economy.db.profile.bags.minimapLine then return end
	local b = Economy:ScanBags()
	if b.slots == 0 then return end
	tooltip:AddDoubleLine("Bags", ("%d free · %s"):format(b.free, Lodestar.FormatMoney(b.value)), 1, 1, 1, 1, 1, 1)
	local estimate = Economy:EstimatedRepairCost()
	if estimate and estimate > 0 then
		tooltip:AddDoubleLine("Repairs", ("about %s"):format(Lodestar.FormatMoney(estimate)), 1, 1, 1, 1, 0.8, 0.4)
	end
end

function Economy:EnableBags()
	if not Economy.bagsReady then
		Economy.bagsReady = true
		Lodestar:RegisterSlashVerb("bags", function() Economy:PrintBagReport() end,
			"bag space, vendor value and the repair estimate")
		Lodestar:RegisterTooltipProvider(tooltipLine)
	end
end

function Economy:DisableBags()
	-- The slash verb and the tooltip provider both check IsEnabled(); there is nothing to tear down.
end

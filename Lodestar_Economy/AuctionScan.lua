-- Lodestar_Economy: learn auction prices while browsing, plus an optional full scan.
--
-- Everything is guarded on the retail-style C_AuctionHouse API (browse/commodity/item search and
-- ReplicateItems). If the Forever auction house turns out to use a different API surface, the
-- module simply learns nothing and the tooltip line stays hidden.
local Lodestar = _G.Lodestar
local Economy = Lodestar:GetModule("Economy")

local FormatMoney = Lodestar.FormatMoney

local REPLICATE_BATCH = 400 -- rows per frame while digesting a full scan
local replicateCursor, replicateTotal, replicateTicker

local function prices() return Economy.db.factionrealm.prices end

local function record(itemID, unitPrice, quantity)
	if not itemID or not unitPrice or unitPrice <= 0 then return end
	local entry = prices()[itemID]
	local now = time()
	-- Keep the lowest price seen in the last scan window; a fresh observation always wins if older than 30 min.
	if not entry or (now - (entry.t or 0)) > 1800 or unitPrice < entry.p then
		prices()[itemID] = { p = unitPrice, t = now, q = quantity or 0 }
	else
		entry.t = now
		entry.q = quantity or entry.q
	end
end

function Economy:GetAHPrice(itemID)
	return prices()[itemID]
end

-- Browse results: one row per item key with the lowest price. -------------------------

function Economy:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
	if not C_AuctionHouse.GetBrowseResults then return end
	for _, row in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		if row.itemKey and row.minPrice then
			record(row.itemKey.itemID, row.minPrice, row.totalQuantity)
		end
	end
end

function Economy:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
	if not (itemID and C_AuctionHouse.GetNumCommoditySearchResults) then return end
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
	if n and n > 0 then
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
		if info and info.unitPrice then
			record(itemID, info.unitPrice, C_AuctionHouse.GetCommoditySearchResultsQuantity and C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) or info.quantity)
		end
	end
end

function Economy:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
	if not (itemKey and C_AuctionHouse.GetNumItemSearchResults) then return end
	local n = C_AuctionHouse.GetNumItemSearchResults(itemKey)
	local best
	-- Walk every row: the list is sorted by the user's persisted column choice, so the first rows
	-- are not necessarily the cheapest. The results are already resident and the call is cheap.
	for i = 1, n or 0 do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		local buyout = info and info.buyoutAmount
		if buyout and buyout > 0 and (not best or buyout < best) then best = buyout end
	end
	if best then record(itemKey.itemID, best, n) end
end

-- Full scan via ReplicateItems ---------------------------------------------------------

local function digestReplicate()
	local n = replicateTotal
	local stop = math.min(n, replicateCursor + REPLICATE_BATCH - 1)
	for i = replicateCursor, stop do
		-- name, texture, count, quality, usable, level, levelColHeader, minBid, minIncrement,
		-- buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i - 1)
		if itemID and buyout and buyout > 0 and count and count > 0 then
			record(itemID, math.floor(buyout / count), count)
		end
	end
	replicateCursor = stop + 1
	if replicateCursor > n then
		if replicateTicker then Economy:CancelTimer(replicateTicker) replicateTicker = nil end
		Economy.db.factionrealm.lastScan = time()
		Lodestar:Msg("Auction scan finished: %d listings read.", n)
	end
end

function Economy:REPLICATE_ITEM_LIST_UPDATE()
	if not C_AuctionHouse.GetNumReplicateItems then return end
	replicateTotal = C_AuctionHouse.GetNumReplicateItems() or 0
	replicateCursor = 1
	if replicateTotal == 0 then
		Lodestar:Msg("Auction scan returned nothing.")
		return
	end
	if replicateTicker then self:CancelTimer(replicateTicker) end
	replicateTicker = self:ScheduleRepeatingTimer(digestReplicate, 0.05)
end

function Economy:StartFullScan()
	if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
		Lodestar:Say("Full auction scans aren't available on this client.")
		return
	end
	if not (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown()) then
		Lodestar:Say("Open the auction house first.")
		return
	end
	Lodestar:Msg("Requesting a full auction listing...")
	C_AuctionHouse.ReplicateItems()
end

local function handleAH(rest)
	rest = strtrim(rest or "")
	if rest == "scan" then
		Economy:StartFullScan()
		return
	end
	local itemID = tonumber(rest) or tonumber(rest:match("item:(%d+)"))
	if not itemID then
		local n = 0
		for _ in pairs(prices()) do n = n + 1 end
		local last = Economy.db.factionrealm.lastScan or 0
		Lodestar:Say("Auction memory: %d items on this realm%s. Usage: /lode ah [item link] | scan", n,
			last > 0 and (", last full scan " .. date("%Y-%m-%d %H:%M", last)) or "")
		return
	end
	local price = Economy:GetAHPrice(itemID)
	local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	if price then
		Lodestar:Say("%s: lowest seen %s (%s)", name, FormatMoney(price.p), date("%Y-%m-%d %H:%M", price.t))
	else
		Lodestar:Say("%s: no auction price recorded yet.", name)
	end
end

function Economy:EnableAuctionScan()
	if C_AuctionHouse then
		self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
		self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
		self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	end
	if not self.ahSlash then
		self.ahSlash = true
		Lodestar:RegisterSlashVerb("ah", handleAH, "auction price memory: /lode ah [item link] | scan")
	end
end

function Economy:DisableAuctionScan()
	self:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	self:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
	self:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
	self:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
	self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	if replicateTicker then self:CancelTimer(replicateTicker) replicateTicker = nil end
end

-- Lodestar_Economy: module definition, defaults and settings page.
local Lodestar = _G.Lodestar

local Economy = Lodestar:NewModule("Economy", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
Economy.displayName = "Economy"
Economy.description = "Auto-sell junk, auto-repair, gold ledger, vendor and auction prices in tooltips."
Economy.order = 20

Economy.defaults = {
	profile = {
		merchant = {
			sellJunk = true,
			repair = true,
			guildRepair = false,
			announce = true,
			keep = {},          -- [itemID] = true: never auto-sell
		},
		tooltip = {
			vendorPrice = true,
			ahPrice = true,
			stackTotals = true,
		},
		gold = {
			sessionInTooltip = true,
		},
		bags = {
			minimapLine = true, -- free slots and vendor value on the minimap button tooltip
		},
	},
	global = {
		chars = {},             -- [realm][name] = { money, class, faction, updated }
		repair = {},            -- { perPoint = copper per durability point, samples = {...}, at = epoch }
	},
	factionrealm = {
		prices = {},            -- [itemID] = { p = unit copper, t = epoch, q = quantity seen }
		lastScan = 0,
	},
}

Economy.options = {
	merchantHeader = { type = "header", order = 10, name = "Vendors" },
	sellJunk = {
		type = "toggle", order = 11, name = "Auto-sell grey items",
		desc = "Sells poor-quality items when you open a vendor. Hold Shift while opening the vendor to skip. Use /lode keep [item link] to protect an item.",
		get = function() return Economy.db.profile.merchant.sellJunk end,
		set = function(_, v) Economy.db.profile.merchant.sellJunk = v end,
	},
	repair = {
		type = "toggle", order = 12, name = "Auto-repair",
		get = function() return Economy.db.profile.merchant.repair end,
		set = function(_, v) Economy.db.profile.merchant.repair = v end,
	},
	guildRepair = {
		type = "toggle", order = 13, name = "Use guild funds when allowed",
		get = function() return Economy.db.profile.merchant.guildRepair end,
		set = function(_, v) Economy.db.profile.merchant.guildRepair = v end,
	},
	merchantAnnounce = {
		type = "toggle", order = 14, name = "Announce sales and repairs",
		get = function() return Economy.db.profile.merchant.announce end,
		set = function(_, v) Economy.db.profile.merchant.announce = v end,
	},

	tooltipHeader = { type = "header", order = 20, name = "Tooltips" },
	vendorPrice = {
		type = "toggle", order = 21, name = "Vendor sell price",
		desc = "Shows what a vendor pays for the item (Blizzard only shows this while a vendor is open).",
		get = function() return Economy.db.profile.tooltip.vendorPrice end,
		set = function(_, v) Economy.db.profile.tooltip.vendorPrice = v end,
	},
	stackTotals = {
		type = "toggle", order = 22, name = "Stack totals",
		desc = "When hovering a stack in your bags, also show the value of the whole stack.",
		get = function() return Economy.db.profile.tooltip.stackTotals end,
		set = function(_, v) Economy.db.profile.tooltip.stackTotals = v end,
	},
	ahPrice = {
		type = "toggle", order = 23, name = "Auction price",
		desc = "Shows the lowest auction price Lodestar has seen for the item on this realm (learned while you browse the auction house or run /lode ah scan).",
		get = function() return Economy.db.profile.tooltip.ahPrice end,
		set = function(_, v) Economy.db.profile.tooltip.ahPrice = v end,
	},

	bagsHeader = { type = "header", order = 25, name = "Bags and repairs" },
	bagsDesc = {
		type = "description", order = 25.1, fontSize = "medium",
		name = "|cffffff7f/lode bags|r prints free slots, what a vendor would pay for what you are carrying, and what a full repair would cost. The repair figure is learned from your own repairs -- the client only reports a cost while a repair vendor is open, so nothing is claimed until you have used one.\n",
	},
	bagsMinimapLine = {
		type = "toggle", order = 25.2, name = "Bag line on the minimap tooltip",
		get = function() return Economy.db.profile.bags.minimapLine end,
		set = function(_, v) Economy.db.profile.bags.minimapLine = v end,
	},

	goldHeader = { type = "header", order = 30, name = "Gold" },
	goldDesc = {
		type = "description", order = 31, fontSize = "medium",
		name = "|cffffff7f/lode gold|r lists every character's gold on this account. The minimap tooltip shows this session's change.\n",
	},
	goldClear = {
		type = "execute", order = 32, name = "Forget other characters",
		confirm = true,
		func = function() wipe(Economy.db.global.chars); Economy:RecordGold() end,
	},

	ahHeader = { type = "header", order = 40, name = "Auction house" },
	ahDesc = {
		type = "description", order = 41, fontSize = "medium",
		name = "Prices are learned automatically while you browse. |cffffff7f/lode ah scan|r requests a full listing when the auction house is open (the server allows this every few minutes). |cffffff7f/lode ah [item]|r prints what Lodestar knows.\n",
	},
	ahClear = {
		type = "execute", order = 42, name = "Clear price memory",
		confirm = true,
		func = function() wipe(Economy.db.factionrealm.prices); Lodestar:Say("Auction price memory cleared.") end,
	},
}

function Economy:OnEnable()
	self:EnableMerchant()
	self:EnableGold()
	self:EnableTooltip()
	self:EnableAuctionScan()
	self:EnableBags()
end

function Economy:OnDisable()
	self:DisableMerchant()
	self:DisableGold()
	self:DisableTooltip()
	self:DisableAuctionScan()
	self:DisableBags()
end

Lodestar:RegisterModule(Economy)

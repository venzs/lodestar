-- Lodestar_Leveling: camp — the things that decide whether you can keep going or have to walk back
-- to town. How long your buffs have left, how much food and drink is in the bags, and whether you
-- are actually resting.
--
-- Classic leveling is paced by consumables in a way retail is not: a Well Fed buff that lapses
-- mid-pull costs more than it looks, and running out of drink four zones from a vendor costs a
-- corpse run. Both are knowable well in advance and neither is surfaced anywhere in the default UI
-- -- the buff frame shows an icon that only starts flashing in the last thirty seconds, and nothing
-- counts your food at all.
--
-- Sources: player HELPFUL auras through AuraUtil.ForEachAura or C_UnitAuras.GetAuraDataByIndex
-- (expirationTime is in GetTime() units; 0 means the aura has no duration), the bag walk through
-- C_Container.GetContainerNumSlots / GetContainerItemID / GetContainerItemInfo, and item classes
-- through C_Item.GetItemInfoInstant. Everything degrades to "unknown" rather than guessing: a value
-- this client will not hand over is simply not shown.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local MAX_AURAS = 80            -- upper bound for the index walk when AuraUtil is missing
local WARN_AGAIN = 60           -- seconds before the same buff may warn again
local SOON_SECONDS = 60         -- "about to drop": a second, louder warning
local BAG_SLOTS = NUM_BAG_SLOTS or 4

-- Consumable / Food & Drink. The enums are used when the client exposes them and the raw numbers
-- otherwise, because Classic's values for these two have never moved.
local CLASS_CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local SUBCLASS_FOOD_DRINK = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink) or 5

local ORANGE, RED, GREEN, WHITE = "|cffff9933", "|cffff4040", "|cff7fff7f", "|cffffffff"

local state = {
	buffs = {},        -- [lowercase name] = { name, remaining (seconds, nil when endless), stacks }
	food = nil,        -- total Food & Drink items in the bags, nil when the client will not say
	foodStacks = 0,    -- how many bag slots they occupy
}
local lastWarn = {}    -- [lowercase name] = GetTime() of the last warning

local function readable(v)
	return v ~= nil and (canaccessvalue == nil or canaccessvalue(v))
end

local function num(v)
	return (readable(v) and type(v) == "number") and v or nil
end

-- Buffs -----------------------------------------------------------------------------

--- Seconds left on an aura, nil when it never expires or the client will not say. WoW reports
--- expirationTime on the GetTime() clock and uses 0 for "no duration", which is not the same as
--- "expires now" -- treating it as a number here is how a permanent buff ends up warning forever.
local function remainingFrom(aura)
	if type(aura) ~= "table" then return nil end
	local expires = num(aura.expirationTime)
	if not expires or expires <= 0 then return nil end
	local left = expires - GetTime()
	return left > 0 and left or 0
end

local function visit(found, aura)
	local name = type(aura) == "table" and aura.name or aura
	if not (readable(name) and type(name) == "string") then return end
	found[name:lower()] = {
		name = name,
		remaining = remainingFrom(aura),
		stacks = type(aura) == "table" and num(aura.applications) or nil,
	}
end

--- Every HELPFUL aura on the player, keyed by lower-cased name.
local function scanAuras()
	local found = {}
	if AuraUtil and AuraUtil.ForEachAura then
		AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura) visit(found, aura) end, true)
	elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, MAX_AURAS do
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then break end
			visit(found, aura)
		end
	end
	return found
end

--- What is on the player right now, keyed by lower-cased name. Shared with the status strip so the
--- auras are walked once per refresh rather than once per consumer.
function Leveling:CampAuras()
	return state.buffs
end

--- Seconds left on a buff by name, nil when it is missing, endless, or the client will not say.
function Leveling:BuffRemaining(name)
	local entry = type(name) == "string" and state.buffs[name:lower()]
	return entry and entry.remaining or nil
end

-- Bags ------------------------------------------------------------------------------

--- Food and drink carried, as (items, stacks). nil when the container API is unavailable -- which
--- is different from zero, and is why the caller must not treat nil as "you are out of food".
local function countProvisions()
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return nil, 0 end
	local items, stacks = 0, 0
	for bag = 0, BAG_SLOTS do
		local slots = C.GetContainerNumSlots(bag)
		if readable(slots) and type(slots) == "number" then
			for slot = 1, slots do
				local id = C.GetContainerItemID(bag, slot)
				if readable(id) and type(id) == "number" then
					local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
					if classID == CLASS_CONSUMABLE and subclassID == SUBCLASS_FOOD_DRINK then
						local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
						local count = (type(info) == "table" and num(info.stackCount)) or 1
						items = items + count
						stacks = stacks + 1
					end
				end
			end
		end
	end
	return items, stacks
end

-- Refresh ---------------------------------------------------------------------------

local function collect()
	state.buffs = scanAuras()
	state.food, state.foodStacks = countProvisions()
end

--- The watched buff names from the status-strip setting, lower-cased.
local function watched()
	local cfg = Leveling.db.profile.xp.strip
	local list = {}
	for name in tostring(cfg.buffs or ""):gmatch("[^,]+") do
		name = strtrim(name)
		if name ~= "" then list[#list + 1] = name:lower() end
	end
	return list
end

local function warn(key, text, ...)
	local now = GetTime()
	if (lastWarn[key] or -math.huge) + WARN_AGAIN > now then return end
	lastWarn[key] = now
	Lodestar:Msg(text, ...)
end

--- Say something once when a watched buff is close to lapsing, and again when it is nearly gone.
--- The point is to catch it while there is still time to eat, not to narrate the last five seconds.
local function checkBuffs(cfg)
	if not cfg.warnExpiring then return end
	local limit = (cfg.warnMinutes or 5) * 60
	for _, key in ipairs(watched()) do
		local entry = state.buffs[key]
		local left = entry and entry.remaining
		if left then
			if left <= SOON_SECONDS then
				warn(key .. ":soon", "%s%s drops in %d seconds.|r", RED, entry.name, math.floor(left))
			elseif left <= limit then
				warn(key, "%s%s has %d minutes left.|r", ORANGE, entry.name, math.max(1, math.floor(left / 60)))
			else
				lastWarn[key], lastWarn[key .. ":soon"] = nil, nil
			end
		else
			lastWarn[key], lastWarn[key .. ":soon"] = nil, nil
		end
	end
end

--- Running low and running out are separate warnings on separate keys. Sharing one key means the
--- "you have none left" line is swallowed by the rate limit on the "getting low" line that fired a
--- minute earlier -- which is exactly the moment it was worth saying.
local function checkProvisions(cfg)
	if not cfg.warnFood then return end
	local low = cfg.foodLow or 5
	if not state.food or state.food > low then
		lastWarn.food, lastWarn["food:none"] = nil, nil
		return
	end
	if state.food <= 0 then
		warn("food:none", "%sNo food or drink in your bags.|r", RED)
	else
		lastWarn["food:none"] = nil
		warn("food", "%sFood and drink: %d left.|r", ORANGE, state.food)
	end
end

--- Recompute the camp state and say anything that is due. Called from the status strip's refresh,
--- which is already throttled, so this does no throttling of its own.
function Leveling:RefreshCamp()
	if not self:IsEnabled() then return end
	local cfg = self.db.profile.camp
	if not cfg.enabled then
		state.buffs, state.food, state.foodStacks = {}, nil, 0
		return
	end
	local ok, err = pcall(collect)
	if not ok then Lodestar:Debug("camp: %s", tostring(err)) return end
	checkBuffs(cfg)
	checkProvisions(cfg)
end

-- Display ---------------------------------------------------------------------------

--- "24m", "45s", or nil when there is nothing useful to say.
function Leveling:FormatRemaining(seconds)
	if type(seconds) ~= "number" then return nil end
	if seconds >= 3600 then return ("%dh"):format(math.floor(seconds / 3600)) end
	if seconds >= 60 then return ("%dm"):format(math.floor(seconds / 60)) end
	return ("%ds"):format(math.floor(seconds))
end

local function foodColor(cfg, n)
	if n <= 0 then return RED end
	if n <= (cfg.foodLow or 5) then return ORANGE end
	return WHITE
end

--- Food and drink carried, as (items, stacks). items is nil when the client would not say.
function Leveling:CampProvisions()
	return state.food, state.foodStacks
end

--- Strip parts contributed by camp: the food count, when the player asked for it.
function Leveling:CampStripParts()
	local cfg = self.db.profile.camp
	if not (cfg.enabled and cfg.showStock) or not state.food then return {} end
	return { ("food %s%d|r"):format(foodColor(cfg, state.food), state.food) }
end

function Leveling:AddCampTooltipLines(tooltip)
	local cfg = self.db.profile.camp
	if not cfg.enabled then return end
	if state.food then
		local detail = state.foodStacks > 0
			and ("%d (%d stack%s)"):format(state.food, state.foodStacks, state.foodStacks == 1 and "" or "s")
			or tostring(state.food)
		tooltip:AddDoubleLine("Food and drink", detail, 1, 1, 1, 1, 1, 1)
	end
	for _, key in ipairs(watched()) do
		local entry = state.buffs[key]
		if entry then
			local left = self:FormatRemaining(entry.remaining)
			tooltip:AddDoubleLine(entry.name, left or "no timer", 0.5, 1, 0.5, 1, 1, 1)
		end
	end
end

function Leveling:EnableCamp()
	if not Leveling.campSlashReady then
		Leveling.campSlashReady = true
		Lodestar:RegisterSlashVerb("camp", function() Leveling:PrintCampReport() end,
			"buff timers, food and drink, rested state")
	end
	self:RefreshCamp()
end

function Leveling:DisableCamp()
	-- The events belong to the status strip; there is nothing of our own to unregister. Clearing
	-- the state matters though: a stale food count outliving the module would show on the strip.
	state.buffs, state.food, state.foodStacks = {}, nil, 0
	wipe(lastWarn)
end

--- `/lode camp`: everything that decides whether you can stay out, in one place.
function Leveling:PrintCampReport()
	local cfg = self.db.profile.camp
	if not cfg.enabled then
		Lodestar:Say("Camp tracking is off. Turn it on in the Leveling settings.")
		return
	end
	self:RefreshCamp()
	Lodestar:Say("Camp:")
	if state.food then
		Lodestar:Say("  food and drink: %s%d|r item%s in %d stack%s",
			foodColor(cfg, state.food), state.food, state.food == 1 and "" or "s",
			state.foodStacks, state.foodStacks == 1 and "" or "s")
	else
		Lodestar:Say("  food and drink: the client did not hand over your bag contents")
	end

	local names = watched()
	if #names == 0 then
		Lodestar:Say("  no buffs watched -- list them in the Leveling settings")
	end
	for _, key in ipairs(names) do
		local entry = state.buffs[key]
		if not entry then
			Lodestar:Say("  %s%s|r: missing", ORANGE, key)
		else
			local left = self:FormatRemaining(entry.remaining)
			Lodestar:Say("  %s%s|r: %s", GREEN, entry.name, left and (left .. " left") or "active")
		end
	end

	local resting = IsResting and IsResting()
	local rested = GetXPExhaustion and GetXPExhaustion()
	local xpMax = UnitXPMax and UnitXPMax("player")
	if type(rested) == "number" and type(xpMax) == "number" and xpMax > 0 then
		Lodestar:Say("  rested: %d%% of a level%s", math.floor(rested / xpMax * 100), resting and " (resting)" or "")
	elseif resting then
		Lodestar:Say("  resting")
	end
end

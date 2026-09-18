-- Lodestar_Leveling: the status strip under the XP readout — free bag slots, lowest durability,
-- rested XP as a share of the level, resting state and watched buffs — plus the bag-space and
-- repair nags that ride on the same data.
--
-- Sources: C_Container.GetContainerNumFreeSlots (general-purpose bags only), the undocumented but
-- present GetInventoryItemDurability (slots 1-18), GetXPExhaustion / UnitXPMax, IsResting, and
-- player HELPFUL auras by name through AuraUtil.ForEachAura or C_UnitAuras.GetAuraDataByIndex.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local BAG_NAG_SLOTS = 2      -- nag at this many free slots or fewer
local DUR_NAG_PCT = 20       -- nag at this durability % or lower
local DUR_BAD_PCT = 10       -- red below this
local NAG_INTERVAL = 5 * 60  -- seconds between repeats of the same nag
local REFRESH_DELAY = 1      -- events within a second coalesce into one refresh
local EQUIP_SLOTS = 18       -- head .. ranged: every slot that can carry durability
local MAX_AURAS = 80         -- upper bound for the index walk when AuraUtil is missing

local SEP = "  |cff666666·|r  "
local WHITE, ORANGE, RED, BLUE, GREEN = "|cffffffff", "|cffff9933", "|cffff4040", "|cff6b9eff", "|cff7fff7f"

local state = { bags = nil, durability = nil, rested = 0, resting = false, buffs = {} }
local lastNag = { bags = -math.huge, durability = -math.huge }
local refreshTimer

local function readable(v)
	return v ~= nil and (canaccessvalue == nil or canaccessvalue(v))
end

--- Free general-purpose bag slots (bagFamily 0). Quivers, ammo pouches and soul bags are skipped:
--- their free slots do not take loot.
local function freeBagSlots()
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
	local free = 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local n, family = C_Container.GetContainerNumFreeSlots(bag)
		if readable(n) and type(n) == "number" and (family == nil or family == 0) then free = free + n end
	end
	return free
end

--- Lowest durability % across the equipped slots, nil when nothing equipped has durability.
local function lowestDurability()
	local getDurability = _G.GetInventoryItemDurability
	if type(getDurability) ~= "function" then return nil end
	local lowest
	for slot = 1, EQUIP_SLOTS do
		local cur, max = getDurability(slot)
		if readable(cur) and readable(max) and type(cur) == "number" and type(max) == "number" and max > 0 then
			local pct = cur / max * 100
			if not lowest or pct < lowest then lowest = pct end
		end
	end
	return lowest
end

--- Rested XP as a percentage of the current level.
local function restedPercent()
	local rested = GetXPExhaustion and GetXPExhaustion()
	local xpMax = UnitXPMax("player")
	if type(rested) ~= "number" or rested <= 0 or type(xpMax) ~= "number" or xpMax <= 0 then return 0 end
	return rested / xpMax * 100
end

--- The configured buff names, lower-cased, in the order the user wrote them.
local function watchList(cfg)
	local list, seen = {}, {}
	for name in tostring(cfg.buffs or ""):gmatch("[^,]+") do
		name = strtrim(name)
		if name ~= "" and not seen[name:lower()] then
			seen[name:lower()] = true
			tinsert(list, name)
		end
	end
	return list
end

--- Watched buffs currently on the player, in the configured order.
local function activeBuffs(cfg)
	local wanted = watchList(cfg)
	if #wanted == 0 then return {} end
	local present = {}
	local function visit(name)
		if readable(name) and type(name) == "string" then present[name:lower()] = true end
	end
	if AuraUtil and AuraUtil.ForEachAura then
		AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
			visit(type(aura) == "table" and aura.name or aura)
		end, true)
	elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, MAX_AURAS do
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then break end
			visit(aura.name)
		end
	end
	local found = {}
	for _, name in ipairs(wanted) do
		if present[name:lower()] then tinsert(found, name) end
	end
	return found
end

local function collect(cfg)
	state.bags = freeBagSlots()
	state.durability = lowestDurability()
	state.rested = restedPercent()
	state.resting = IsResting and IsResting() and true or false
	state.buffs = activeBuffs(cfg)
end

-- Nags ----------------------------------------------------------------------------

local function nag(kind, text, ...)
	local now = GetTime()
	if now - lastNag[kind] < NAG_INTERVAL then return end
	lastNag[kind] = now
	Lodestar:Msg(text, ...)
end

local function checkNags(cfg)
	if cfg.nagBags and state.bags and state.bags <= BAG_NAG_SLOTS then
		if state.bags <= 0 then
			nag("bags", "%sBags are full.|r Sell, mail or destroy something before the next drop.", RED)
		else
			nag("bags", "%sBags: only %d slot%s free.|r", ORANGE, state.bags, state.bags == 1 and "" or "s")
		end
	end
	if cfg.nagDurability and state.durability and state.durability <= DUR_NAG_PCT then
		nag("durability", "%sDurability at %d%%|r — find a repair vendor.", state.durability <= DUR_BAD_PCT and RED or ORANGE, math.floor(state.durability))
	end
end

-- Text ----------------------------------------------------------------------------

local function bagColor(free)
	if free <= 0 then return RED end
	if free <= BAG_NAG_SLOTS then return ORANGE end
	return WHITE
end

local function durabilityColor(pct)
	if pct <= DUR_BAD_PCT then return RED end
	if pct <= DUR_NAG_PCT then return ORANGE end
	return WHITE
end

--- Snapshot of the last refresh: { bags, durability, rested, resting, buffs }.
function Leveling:GetStripState()
	return state
end

--- One line, e.g. "bags 3 free · dur 62% · rested 17% · Well Fed". Empty when nothing is known yet.
function Leveling:BuildStripText()
	local parts = {}
	if state.bags then
		tinsert(parts, ("bags %s%d|r free"):format(bagColor(state.bags), state.bags))
	end
	if state.durability then
		tinsert(parts, ("dur %s%d%%|r"):format(durabilityColor(state.durability), math.floor(state.durability)))
	end
	if state.rested and state.rested > 0 then
		tinsert(parts, ("rested %s%d%%|r"):format(BLUE, math.floor(state.rested)))
	end
	if state.resting then
		tinsert(parts, BLUE .. "Resting|r")
	end
	for _, name in ipairs(state.buffs or {}) do
		-- Camp knows how long each one has left; without it this stays a bare name, as before.
		local left = self.BuffRemaining and self:BuffRemaining(name)
		local text = left and self.FormatRemaining and self:FormatRemaining(left)
		tinsert(parts, GREEN .. name .. (text and (" " .. text) or "") .. "|r")
	end
	for _, extra in ipairs((self.CampStripParts and self:CampStripParts()) or {}) do
		tinsert(parts, extra)
	end
	for _, extra in ipairs((self.ProfessionStripParts and self:ProfessionStripParts()) or {}) do
		tinsert(parts, extra)
	end
	return table.concat(parts, SEP)
end

--- Lines for the XP frame tooltip.
function Leveling:AddStripTooltipLines(tooltip)
	if state.bags then
		tooltip:AddDoubleLine("Bag slots free", tostring(state.bags), 1, 1, 1, 1, 1, 1)
	end
	if state.durability then
		tooltip:AddDoubleLine("Lowest durability", ("%d%%"):format(math.floor(state.durability)), 1, 1, 1, 1, 1, 1)
	end
	local buffs = state.buffs or {}
	if #buffs > 0 then
		tooltip:AddDoubleLine("Buffs", table.concat(buffs, ", "), 1, 1, 1, 0.5, 1, 0.5)
	end
	if self.AddCampTooltipLines then self:AddCampTooltipLines(tooltip) end
	if self.AddProfessionTooltipLines then self:AddProfessionTooltipLines(tooltip) end
end

-- Refresh + events -----------------------------------------------------------------

--- Recompute everything, print any due nags and redraw the readout. Runs even while the XP frame is
--- hidden (max level, tracker off): the nags are their own feature.
function Leveling:RefreshStrip()
	if not self:IsEnabled() then return end
	local cfg = self.db.profile.xp.strip
	local ok, err = pcall(collect, cfg)
	if not ok then Lodestar:Debug("status strip: %s", tostring(err)) end
	checkNags(cfg)
	-- Camp and professions ride on the same throttled refresh rather than each running its own
	-- timer: every source they read changes on events this frame already listens for.
	if self.RefreshCamp then self:RefreshCamp() end
	if self.RefreshProfessions then self:RefreshProfessions() end
	self:RefreshXPText()
end

--- Event entry point: at most one refresh per REFRESH_DELAY seconds, however many events arrive.
function Leveling:QueueStripRefresh()
	if refreshTimer then return end
	refreshTimer = self:ScheduleTimer(function()
		refreshTimer = nil
		self:RefreshStrip()
	end, REFRESH_DELAY)
end

function Leveling:UNIT_AURA(_, unit)
	if unit == "player" then self:QueueStripRefresh() end
end

function Leveling:EnableStatusStrip()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "QueueStripRefresh")
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "QueueStripRefresh")
	self:RegisterEvent("PLAYER_UPDATE_RESTING", "QueueStripRefresh")
	self:RegisterEvent("UNIT_AURA")
	-- UPDATE_EXHAUSTION belongs to the XP tracker, which forwards it here.
	self:RefreshStrip()
end

function Leveling:DisableStatusStrip()
	self:UnregisterEvent("BAG_UPDATE_DELAYED")
	self:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
	self:UnregisterEvent("PLAYER_UPDATE_RESTING")
	self:UnregisterEvent("UNIT_AURA")
	if refreshTimer then self:CancelTimer(refreshTimer) refreshTimer = nil end
end

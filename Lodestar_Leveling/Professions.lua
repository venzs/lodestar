-- Lodestar_Leveling: professions — rank, cap, and the moment a trainer becomes worth the detour.
--
-- Classic's tradeskills stop dead at a tier boundary: Apprentice caps at 75, Journeyman at 150,
-- Expert at 225, Artisan at 300, and until a trainer raises the cap every gather and every craft
-- gives nothing. The default UI shows the bar filling but says nothing when it fills, so the usual
-- way to find out is to skin twenty more beasts and wonder why the number stopped moving.
--
-- Sources: GetProfessions() -> up to six slot indices (two primary, then archaeology, fishing,
-- cooking, first aid) and GetProfessionInfo(index) -> name, icon, rank, maxRank, numAbilities,
-- spellOffset, skillLine, skillModifier. Both are undocumented globals on this client but present
-- and used by Blizzard's own spellbook code. Nothing here needs C_TradeSkillUI, so no tradeskill
-- window has to be open.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

-- Keyed by the cap you are stuck at, holding the rank that lifts it and the character level that
-- rank needs. Artisan and above are trained in the world rather than from any trainer for some
-- professions, which is why the message says "a trainer" rather than naming one. A cap that is not
-- in this table gets no suggestion at all -- Forever is free to add its own tiers, and inventing a
-- next rank for an unknown cap would be a confident lie.
local TIERS = {
	[75] = { name = "Journeyman", cap = 150, level = 10 },
	[150] = { name = "Expert", cap = 225, level = 20 },
	[225] = { name = "Artisan", cap = 300, level = 35 },
}

local NEAR_CAP = 10          -- points from the cap before the strip starts showing it
local NAG_INTERVAL = 10 * 60 -- seconds between repeats of the same cap nag
local TRAINER_YARDS = 300    -- "a trainer is right here" range for the cap nag

local ORANGE, GREEN, WHITE, GREY = "|cffff9933", "|cff7fff7f", "|cffffffff", "|cff999999"

local state = { list = {} }  -- { { name, rank, maxRank, skillLine, capped, toCap } }
local lastNag = {}

local function readable(v)
	return v ~= nil and (canaccessvalue == nil or canaccessvalue(v))
end

local function num(v)
	return (readable(v) and type(v) == "number") and v or nil
end

--- The rank that lifts this cap, or nil when the cap is not one Classic uses.
local function nextTier(maxRank)
	return maxRank and TIERS[maxRank] or nil
end

-- Scan -------------------------------------------------------------------------------

--- Every profession the character knows. Empty when the client has no profession API at all, which
--- is not the same as "knows none" -- callers that would nag must check IsAvailable first.
local function scan()
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local out = {}
	local slots = { GetProfessions() }
	for i = 1, 6 do
		local index = slots[i]
		if index then
			local name, _, rank, maxRank, _, _, skillLine, modifier = GetProfessionInfo(index)
			if readable(name) and type(name) == "string" then
				rank, maxRank = num(rank), num(maxRank)
				out[#out + 1] = {
					name = name,
					rank = rank,
					maxRank = maxRank,
					modifier = num(modifier) or 0,
					skillLine = num(skillLine),
					secondary = i >= 3,
					capped = (rank and maxRank and maxRank > 0 and rank >= maxRank) or false,
					toCap = (rank and maxRank) and (maxRank - rank) or nil,
				}
			end
		end
	end
	return out
end

--- True when this client exposes professions at all.
function Leveling:ProfessionsAvailable()
	return (GetProfessions and GetProfessionInfo) and true or false
end

--- The last scan: a list of { name, rank, maxRank, capped, toCap, secondary, skillLine }.
function Leveling:Professions()
	return state.list
end

-- Skill-ups and nags -------------------------------------------------------------------

--- Remember each rank so a later scan can say what moved. Kept per character: two characters
--- sharing a profile still level their skills separately.
local function recordRanks()
	local store = Leveling.db.char.professions
	for _, p in ipairs(state.list) do
		local prev = store[p.name]
		if type(prev) ~= "table" then
			store[p.name] = { rank = p.rank, maxRank = p.maxRank, first = p.rank, at = time() }
		else
			if p.rank and prev.rank and p.rank > prev.rank then
				prev.gained = (prev.gained or 0) + (p.rank - prev.rank)
			end
			-- A raised cap resets nothing: the session total is about points earned, not the tier.
			prev.rank, prev.maxRank, prev.at = p.rank, p.maxRank, time()
		end
	end
end

local function nag(key, text, ...)
	local now = GetTime()
	if (lastNag[key] or -math.huge) + NAG_INTERVAL > now then return end
	lastNag[key] = now
	Lodestar:Msg(text, ...)
end

--- A trainer's name and distance when one is close enough to be worth mentioning, else nil. The
--- Guide module owns the harvested NPC positions, and it is an optional dependency, so this asks
--- for it at call time and does without when it is not loaded.
local function trainerHint()
	local Guide = Lodestar.GetModule and Lodestar:GetModule("Guide", true)
	if not (Guide and Guide.NearestTradeskillTrainer) then return nil end
	local ok, found = pcall(Guide.NearestTradeskillTrainer, Guide, TRAINER_YARDS)
	if ok and type(found) == "table" and found.name then return found end
	return nil
end

local function checkCaps()
	local cfg = Leveling.db.profile.professions
	if not cfg.nagCap then return end
	for _, p in ipairs(state.list) do
		if p.capped then
			local after = nextTier(p.maxRank)
			local level = UnitLevel and UnitLevel("player") or 0
			local where = trainerHint()
			-- Name both the new cap and the level that gates it: which one matters depends on where
			-- the character is, and a message that gives only one of them sends half the players to
			-- a trainer who will not talk to them.
			local suffix = ""
			if after and level > 0 and level < after.level then
				suffix = (" %s(%s raises it to %d, at level %d -- you are %d)|r")
					:format(GREY, after.name, after.cap, after.level, level)
			elseif after then
				suffix = (" %s(%s raises it to %d)|r"):format(GREY, after.name, after.cap)
			end
			if where then
				suffix = suffix .. (" %s-- %s is %d yd away|r"):format(GREY, where.name, math.floor(where.dist or 0))
			end
			nag("cap:" .. p.name, "%s%s is capped at %d.|r A trainer can raise it.%s",
				ORANGE, p.name, p.maxRank, suffix)
		end
	end
end

-- Display -----------------------------------------------------------------------------

local function rankColor(p)
	if p.capped then return ORANGE end
	if p.toCap and p.toCap <= NEAR_CAP then return WHITE end
	return WHITE
end

--- Strip parts: only professions that are at or near their cap. A skill sitting at 43/75 is not
--- news, and the strip is one line.
function Leveling:ProfessionStripParts()
	local cfg = self.db.profile.professions
	if not cfg.showOnStrip then return {} end
	local parts = {}
	for _, p in ipairs(state.list) do
		if p.rank and p.maxRank and (p.capped or (p.toCap and p.toCap <= NEAR_CAP)) then
			parts[#parts + 1] = ("%s%s %d/%d|r"):format(rankColor(p), p.name, p.rank, p.maxRank)
		end
	end
	return parts
end

function Leveling:AddProfessionTooltipLines(tooltip)
	for _, p in ipairs(state.list) do
		if p.rank and p.maxRank then
			local text = ("%d/%d"):format(p.rank, p.maxRank)
			if p.modifier and p.modifier > 0 then text = text .. (" +%d"):format(p.modifier) end
			if p.capped then
				tooltip:AddDoubleLine(p.name, text .. " (capped)", 1, 1, 1, 1, 0.6, 0.2)
			else
				tooltip:AddDoubleLine(p.name, text, 1, 1, 1, 1, 1, 1)
			end
		end
	end
end

--- `/lode prof`: every profession, how far it is from its cap, and what this character has gained.
function Leveling:PrintProfessionReport()
	if not self:ProfessionsAvailable() then
		Lodestar:Say("This client does not expose professions to addons.")
		return
	end
	self:RefreshProfessions()
	if #state.list == 0 then
		Lodestar:Say("No professions learned yet.")
		return
	end
	Lodestar:Say("Professions:")
	local store = self.db.char.professions
	for _, p in ipairs(state.list) do
		local line
		if not (p.rank and p.maxRank) then
			line = ("  %s%s|r: the client did not hand over a rank"):format(WHITE, p.name)
		elseif p.capped then
			local after = nextTier(p.maxRank)
			local tail = after and (" -- %s raises it to %d (level %d)"):format(after.name, after.cap, after.level) or ""
			line = ("  %s%s %d/%d|r capped%s"):format(ORANGE, p.name, p.rank, p.maxRank, tail)
		else
			line = ("  %s%s %d/%d|r (%d to the cap)"):format(GREEN, p.name, p.rank, p.maxRank, p.toCap or 0)
		end
		local seen = store[p.name]
		if seen and seen.gained and seen.gained > 0 then
			line = line .. (" %s+%d since Lodestar started watching|r"):format(GREY, seen.gained)
		end
		Lodestar:Say(line)
	end
	local where = trainerHint()
	if where then
		Lodestar:Say("  nearest tradeskill trainer: %s, %d yd", where.name, math.floor(where.dist or 0))
	end
end

-- Refresh + events ----------------------------------------------------------------------

--- Recompute and say anything due. SKILL_LINES_CHANGED fires on every point gained, so this has to
--- stay cheap: six GetProfessionInfo calls and a table walk.
function Leveling:RefreshProfessions()
	if not self:IsEnabled() then return end
	if not self.db.profile.professions.enabled then state.list = {} return end
	local ok, list = pcall(scan)
	if not ok then Lodestar:Debug("professions: %s", tostring(list)) return end
	state.list = list or {}
	recordRanks()
	checkCaps()
end

function Leveling:EnableProfessions()
	if not Leveling.profSlashReady then
		Leveling.profSlashReady = true
		Lodestar:RegisterSlashVerb("prof", function() Leveling:PrintProfessionReport() end,
			"profession ranks, caps and what you have gained")
	end
	-- SKILL_LINES_CHANGED is the only documented event that fires on a rank change, and it fires on
	-- every point. TRADE_SKILL_UPDATE does not exist on this client; registering an event the client
	-- does not know throws, so there is nothing to add here "just in case".
	self:RegisterEvent("SKILL_LINES_CHANGED", "QueueProfessionRefresh")
	self:RefreshProfessions()
end

function Leveling:DisableProfessions()
	self:UnregisterEvent("SKILL_LINES_CHANGED")
	state.list = {}
end

--- Skill points arrive one event at a time during a gathering spree; fold them into the strip's
--- existing refresh rather than redrawing per point.
function Leveling:QueueProfessionRefresh()
	self:QueueStripRefresh()
end

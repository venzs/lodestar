-- Lodestar_Character: the stat rows.
--
-- Every row has an `update(statFrame, unit)` with the same contract Blizzard's PAPERDOLL_STATINFO
-- updateFuncs use: it fills the row through Stats.SetLabelAndText (our own stand-in for Blizzard's
-- PaperDollFrame_SetLabelAndText, same signature), sets statFrame.tooltip / tooltip2 / tooltip3 and
-- returns the numeric value. Returning nil means "not applicable, hide the row". The statFrame is one of
-- our panel's rows — we never call into Blizzard's stats pane; Panel.lua says why. Formulas and constants
-- come from Blizzard's own camelot files (PaperDollFrameStats.lua, SkillsFrame.lua, PaperDollFrame.lua).
local Lodestar = _G.Lodestar
local Character = Lodestar:GetModule("Character")

local Stats = {}
Character.Stats = Stats

-- Constants ----------------------------------------------------------------------------------------

local MELEE_MISS = { 5.0, 5.2, 5.4, 9.0 }   -- vs +0, +1, +2, +3 (CharacterHitFrame_OnEnter)
local SPELL_MISS = { 4.0, 5.0, 6.0, 17.0 }
local SPELL_MISS_FLOOR = 1.0               -- spells keep a 1% chance to miss
local DUAL_WIELD_MISS = 19.0               -- auto-attack penalty (DUAL_WIELD_HIT_PENALTY)
local SKILL_PER_LEVEL = 5
local SPIRIT_STANDING_PENALTY = 0.75       -- PaperDollFrameStats applies this before display (assume standing)
local BASE_ENEMY_MISS, BASE_ENEMY_CRIT, CRUSH_MIN_DIFF = 5.0, 5.0, 15
local HOLY_SCHOOL, LAST_SCHOOL = 2, 7      -- GetSpellBonusDamage school indices (MAX_SPELL_SCHOOLS)
local SCHOOL_NAMES = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost", [6] = "Shadow", [7] = "Arcane" }
local UNARMED_SKILL, FERAL_SKILL = 162, 3014
local LEGACY_FACTION, LEGACY_TREE = 2802, 1187 -- Constants.LegacyConsts (all three Legacy trees share one currency)
local PVP_RANK_FACTION = 2800
local SLOT_MAINHAND, SLOT_OFFHAND, SLOT_RANGED = 16, 17, 18
local SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[9] = "Wrist", [10] = "Hands", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
	[16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [19] = "Tabard",
}

-- Helpers ------------------------------------------------------------------------------------------

local HL = HIGHLIGHT_FONT_COLOR_CODE or "|cffffffff"
local CLOSE = FONT_COLOR_CODE_CLOSE or "|r"

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function pct(v) return ("%.1f%%"):format(v) end
local function signedPct(v)
	if math.abs(v) < 0.005 then v = 0 end
	return (v > 0 and "+" or "") .. ("%.2f%%"):format(v)
end
local function num(v) return BreakUpLargeNumbers(math.floor((tonumber(v) or 0) + 0.5)) end

--- Call fn(...) if it is a function, in protected mode. Returns nothing on error or when absent.
local function safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
	return nil
end

local function classFile() return (select(2, UnitClass("player"))) end
local function usesRangedHit()
	local c = classFile()
	return c == "WARRIOR" or c == "HUNTER" or c == "ROGUE"
end
local function playerLevel() return UnitLevel("player") or 1 end
local function tooltipFormat() return _G.PAPERDOLLFRAME_TOOLTIP_FORMAT or "%s" end
local function schoolName(i) return _G["DAMAGE_SCHOOL" .. i] or SCHOOL_NAMES[i] or ("School " .. i) end

--- "Level 60" / "Level 63 (boss)" for a +N target.
local function levelLabel(offset)
	local level = playerLevel() + offset
	return offset == 3 and ("Level %d (boss)"):format(level) or ("Level %d"):format(level)
end

--- Fill a row the way Blizzard's updateFuncs do, but into a row frame of ours: same fields
--- PaperDollFrame_SetLabelAndText would set, without calling Blizzard's function.
function Stats.SetLabelAndText(statFrame, label, text, numericValue)
	if statFrame.Label then statFrame.Label:SetText((_G.STAT_FORMAT or "%s:"):format(label)) end
	if statFrame.Value then statFrame.Value:SetText(text) end
	statFrame.numericValue = numericValue
end

--- Blizzard-style row header for the tooltip: "|cffffffffMelee hit 5.0%|r".
local function header(label, valueText)
	return HL .. tooltipFormat():format(label) .. " " .. tostring(valueText) .. CLOSE
end

--- Set label, value and the three tooltip slots in one go; returns the numeric value.
local function fill(statFrame, label, text, numeric, tooltip2, tooltip3)
	Stats.SetLabelAndText(statFrame, label, text, numeric)
	statFrame.tooltip = header(label, text)
	statFrame.tooltip2 = tooltip2
	statFrame.tooltip3 = tooltip3
	return numeric
end

--- Mirrors XPTracker: the realm/phase cap clamped by the expansion cap; XP-disabled counts as capped.
local function atMaxLevel()
	if safe(_G.IsXPUserDisabled) then return true end
	local max
	if GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer then
		max = safe(GameRulesUtil.GetEffectiveMaxLevelForPlayer)
	end
	if type(max) ~= "number" then
		local expansionMax = safe(GetMaxLevelForPlayerExpansion) or 60
		max = math.min(expansionMax, safe(GetMaxPlayerLevel) or expansionMax)
	end
	return playerLevel() >= max
end

-- Weapon skills --------------------------------------------------------------------------------------

local subclassToSkill
local function weaponSubclassSkills()
	if subclassToSkill then return subclassToSkill end
	local E = Enum.ItemWeaponSubclass
	subclassToSkill = {
		[E.Sword1H] = 43, [E.Axe1H] = 44, [E.Bows] = 45, [E.Guns] = 46, [E.Mace1H] = 54, [E.Sword2H] = 55,
		[E.Staff] = 136, [E.Mace2H] = 160, [E.Axe2H] = 172, [E.Dagger] = 173, [E.Thrown] = 176,
		[E.Crossbow] = 226, [E.Wand] = 228, [E.Polearm] = 229, [E.Unarmed] = 162,
	}
	return subclassToSkill
end

--- Skill line for the weapon in a slot (PaperDollFrame_GetEquippedWeaponSkillID): Feral Combat for a
--- shapeshifted druid, Unarmed for an empty main hand, nil for shields / empty off-hand / no ranged.
function Stats.WeaponSkillIDForSlot(slot)
	if slot == SLOT_MAINHAND and classFile() == "DRUID" then
		local form = safe(_G.GetShapeshiftForm)
		if form and form ~= 0 then return FERAL_SKILL end
	end
	local itemID = safe(_G.GetInventoryItemID, "player", slot)
	if not itemID then
		return slot == SLOT_MAINHAND and UNARMED_SKILL or nil
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if classID ~= Enum.ItemClass.Weapon then return nil end
	return weaponSubclassSkills()[subclassID]
end

--- SkillLineAttributes (name, rank, maxRank, modifier) for the weapon in a slot, plus the skill id.
function Stats.WeaponSkillInfo(slot)
	local id = Stats.WeaponSkillIDForSlot(slot)
	if not id then return nil end
	local info = safe(C_SkillInfo.GetSkillLineInfoByID, id)
	if type(info) ~= "table" or type(info.rank) ~= "number" then return nil end
	return info, id
end

--- Effective weapon skill (rank + modifier) for a slot, defaulting to the level cap when unknown.
local function weaponSkill(slot)
	local info = Stats.WeaponSkillInfo(slot)
	if info then return info.rank + (info.modifier or 0), info end
	return playerLevel() * SKILL_PER_LEVEL, nil
end

--- "287/300", plus a coloured "+5" / "-3" when a modifier applies. Panel columns are ~135 px wide, so the value stays short.
local function skillText(info)
	local mod = info.modifier or 0
	local text = ("%d/%d"):format(info.rank, info.maxRank)
	if mod > 0 then return text .. " " .. (GREEN_FONT_COLOR_CODE or "|cff20ff20") .. "+" .. mod .. CLOSE end
	if mod < 0 then return text .. " " .. (RED_FONT_COLOR_CODE or "|cffff2020") .. mod .. CLOSE end
	return text
end

--- Row label for a skill line; "Two-Handed Swords" becomes "2H Swords" so the row fits next to its value.
local function skillLabel(info, fallback)
	local name = info.name or fallback
	return (name:gsub("^Two%-Handed ", "2H "))
end

-- Skills-tab formulas (SkillsFrame.lua): deltas vs a target `offset` levels above the player.
local function skillDiff(offset, skill) return (playerLevel() + offset) * SKILL_PER_LEVEL - skill end
local function hitDelta(offset, skill) return skillDiff(offset, skill) * -0.04 end
local function critDelta(offset, skill) return skillDiff(offset, skill) * -0.04 end
local function glancingChance(offset, skill)
	skill = math.min(playerLevel() * SKILL_PER_LEVEL, skill)
	return clamp((0.02 * skillDiff(offset, skill) + 0.1) * 100, -100, 100)
end
local function glancingPenalty(offset, skill)
	local diff = skillDiff(offset, skill)
	local low = 1.30 - 0.05 * diff
	if diff > 10 then low = low + 0.1 end
	low = clamp(low, 0.01, 0.91)
	local high = 1.20 - 0.03 * diff
	if diff > 10 then high = high + 0.1 end
	high = clamp(high, 0.20, 0.99)
	return 100 - clamp((low + high) / 2, 0, 1) * 100
end

-- Hit / crit / haste ---------------------------------------------------------------------------------

function Stats.MeleeHit() return GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier() end
function Stats.RangedHit() return GetCombatRatingBonus(CR_HIT_RANGED) + GetRangedHitModifier() end
function Stats.SpellHit() return GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier() end

--- Miss chances vs +0..+3 for a base table, after `hit`. The tables already assume a weapon skill at the
--- level cap, so only the skill's distance from that cap (0.04% per point) is applied on top.
function Stats.MissTable(base, hit, skill, floor)
	local delta = skill and hitDelta(0, skill) or 0
	local out = {}
	for i = 1, 4 do
		out[i] = clamp(base[i] - hit - delta, floor or 0, 100)
	end
	return out
end

local function missLines(base, hit, skill, floor)
	local misses = Stats.MissTable(base, hit, skill, floor)
	local lines = {}
	for i = 1, 4 do
		lines[i] = ("%s: %s"):format(levelLabel(i - 1), pct(misses[i]))
	end
	return table.concat(lines, "\n")
end

local function meleeHitRow(statFrame)
	local hit = Stats.MeleeHit()
	local skill, info = weaponSkill(SLOT_MAINHAND)
	local lines = "Chance to miss with the main hand:\n" .. missLines(MELEE_MISS, hit, skill)
	if info then lines = lines .. ("\n\n%s %s"):format(info.name, skillText(info)) end
	if IsDualWielding() then
		lines = lines .. ("\nDual wielding adds %d%% miss to auto-attacks."):format(DUAL_WIELD_MISS)
	end
	return fill(statFrame, "Melee hit", pct(hit), hit, lines)
end

local function rangedHitRow(statFrame)
	local hit = Stats.RangedHit()
	local skill, info = weaponSkill(SLOT_RANGED)
	local lines = "Chance to miss with the ranged weapon:\n" .. missLines(MELEE_MISS, hit, info and skill or nil)
	if info then lines = lines .. ("\n\n%s %s"):format(info.name, skillText(info)) end
	return fill(statFrame, "Ranged hit", pct(hit), hit, lines)
end

local function spellHitRow(statFrame)
	local hit = Stats.SpellHit()
	local lines = "Chance for a spell to miss (resist):\n" .. missLines(SPELL_MISS, hit, nil, SPELL_MISS_FLOOR)
		.. ("\n\nSpells keep a %d%% minimum chance to miss."):format(SPELL_MISS_FLOOR)
	return fill(statFrame, "Spell hit", pct(hit), hit, lines)
end

local function critLines(crit, skill)
	local lines = { "Against a target of:" }
	for offset = 0, 3 do
		lines[#lines + 1] = ("%s: %s"):format(levelLabel(offset), pct(clamp(crit + critDelta(offset, skill), 0, 100)))
	end
	return table.concat(lines, "\n")
end

local function meleeCritRow(statFrame)
	local crit = GetCritChance()
	return fill(statFrame, "Melee crit", pct(crit), crit, critLines(crit, (weaponSkill(SLOT_MAINHAND))))
end

local function rangedCritRow(statFrame)
	local crit = GetRangedCritChance()
	local skill, info = weaponSkill(SLOT_RANGED)
	return fill(statFrame, "Ranged crit", pct(crit), crit, info and critLines(crit, skill) or nil)
end

local function spellCritRow(statFrame)
	local crit = GetSpellCritChance()
	return fill(statFrame, "Spell crit", pct(crit), crit, "Applies to every school; per-school crit is not exposed by the client.")
end

local function meleeHasteRow(statFrame)
	local haste = GetMeleeHaste()
	return fill(statFrame, "Melee haste", pct(haste), haste, "Speeds up melee auto-attacks.")
end

local function rangedHasteRow(statFrame)
	local base, quiver = GetRangedHaste()
	local haste = (base or 0) + (quiver or 0)
	local lines = ("Base: %s\nQuiver / ammo pouch: %s"):format(pct(base or 0), pct(quiver or 0))
	return fill(statFrame, "Ranged haste", pct(haste), haste, lines)
end

local function spellHasteRow(statFrame)
	local haste = UnitSpellHaste("player")
	return fill(statFrame, "Spell haste", pct(haste), haste, "Reduces cast times.")
end

-- Attack speed / DPS ---------------------------------------------------------------------------------

local function dps(minDamage, maxDamage, speed)
	if not speed or speed <= 0 then return 0 end
	return ((minDamage or 0) + (maxDamage or 0)) / (2 * speed)
end

local function attackSpeedRow(statFrame)
	local mh, oh = UnitAttackSpeed("player")
	if not mh then return nil end
	local text = ("%.2f"):format(mh)
	local lines = ("Main hand: %.2f s"):format(mh)
	if oh then
		text = text .. (" / %.2f"):format(oh)
		lines = lines .. ("\nOff hand: %.2f s"):format(oh)
	end
	lines = lines .. ("\nMelee haste: %s"):format(pct(GetMeleeHaste()))
	return fill(statFrame, "Attack speed", text, mh, lines)
end

local function meleeDPSRow(statFrame)
	local mh, oh = UnitAttackSpeed("player")
	local minDamage, maxDamage, ohMin, ohMax = UnitDamage("player")
	if not (mh and minDamage) then return nil end
	local main = dps(minDamage, maxDamage, mh)
	local text = ("%.1f"):format(main)
	local lines = ("Main hand: %s - %s at %.2f s"):format(num(minDamage), num(maxDamage), mh)
	if oh and ohMin and ohMax and ohMax > 0 then
		text = text .. (" / %.1f"):format(dps(ohMin, ohMax, oh))
		lines = lines .. ("\nOff hand: %s - %s at %.2f s"):format(num(ohMin), num(ohMax), oh)
	end
	return fill(statFrame, "Melee DPS", text, main, lines)
end

local function rangedSpeedRow(statFrame)
	local speed = UnitRangedDamage("player")
	if not speed or speed <= 0 then return nil end
	local baseHaste = GetRangedHaste()
	local lines = ("Ranged haste: %s"):format(pct(baseHaste or 0))
	return fill(statFrame, "Ranged speed", ("%.2f"):format(speed), speed, lines)
end

local function rangedDPSRow(statFrame)
	local speed, minDamage, maxDamage = UnitRangedDamage("player")
	if not speed or speed <= 0 then return nil end
	local value = dps(minDamage, maxDamage, speed)
	local lines = ("%s - %s at %.2f s"):format(num(minDamage), num(maxDamage), speed)
	return fill(statFrame, "Ranged DPS", ("%.1f"):format(value), value, lines)
end

-- Spell power per school -----------------------------------------------------------------------------

--- Bonus damage for every school plus the minimum across them (Blizzard's "Spell power").
function Stats.SchoolDamage()
	local schools, minimum = {}, nil
	for i = HOLY_SCHOOL, LAST_SCHOOL do
		local v = GetSpellBonusDamage(i) or 0
		schools[i] = v
		if not minimum or v < minimum then minimum = v end
	end
	return schools, minimum or 0
end

local function schoolRow(school)
	return function(statFrame)
		local schools, minimum = Stats.SchoolDamage()
		local v = schools[school] or 0
		if v <= 0 or v == minimum then return nil end -- nothing school-specific: Blizzard's Spell power row covers it
		local label = schoolName(school) .. " damage"
		local lines = ("%s above the %s spell power Blizzard shows for every school."):format(num(v - minimum), num(minimum))
		return fill(statFrame, label, num(v), v, lines)
	end
end

-- Regeneration ---------------------------------------------------------------------------------------

local function hasMana()
	local max = safe(UnitPowerMax, "player", Enum.PowerType.Mana)
	return (max or 0) > 0
end

local function mp5Row(statFrame)
	if not hasMana() then return nil end
	local base, casting = GetManaRegen()
	base, casting = math.floor((base or 0) * 5), math.floor((casting or 0) * 5)
	local spiritBase, spiritCasting = safe(GetManaRegenFromSpirit)
	local lines = ("Out of combat: %s\nWhile casting: %s"):format(num(base), num(casting))
	if spiritBase then
		lines = lines .. ("\n\nFrom spirit: %s / %s"):format(num(spiritBase * 5), num((spiritCasting or 0) * 5))
	end
	return fill(statFrame, "Mana per 5 s", num(base) .. " / " .. num(casting), base, lines)
end

local function hp5Row(statFrame)
	local base, combat = GetHealthRegen()
	base, combat = math.floor((base or 0) * 5), math.floor((combat or 0) * 5)
	local spirit = safe(GetHealthRegenFromSpirit)
	local lines = ("Out of combat: %s\nIn combat: %s"):format(num(base), num(combat))
	if spirit then
		-- Blizzard's Spirit tooltip applies the standing penalty before display; show its number
		-- first so this row agrees with the Spirit tooltip on the same sheet.
		lines = lines .. ("\n\nFrom spirit: %s while standing (%s before the x%.2f standing penalty)")
			:format(num(spirit * SPIRIT_STANDING_PENALTY * 5), num(spirit * 5), SPIRIT_STANDING_PENALTY)
	end
	return fill(statFrame, "Health per 5 s", num(base) .. " / " .. num(combat), base, lines)
end

-- Defense detail -------------------------------------------------------------------------------------

--- Effective defense skill (base + modifier), base, modifier.
function Stats.Defense()
	local base, modifier = UnitDefenseSkill("player")
	base, modifier = base or 0, modifier or 0
	return math.max(0, base + modifier), base, modifier
end

-- PaperDollFrameStats.lua: enemy skill = (level + offset) * 5, 0.04% per point of difference.
local function enemyDiff(offset, defense) return (playerLevel() + offset) * SKILL_PER_LEVEL - defense end
function Stats.EnemyMiss(offset, defense) return clamp(BASE_ENEMY_MISS - enemyDiff(offset, defense) * 0.04, 0, 100) end
function Stats.EnemyCrit(offset, defense) return clamp(BASE_ENEMY_CRIT + enemyDiff(offset, defense) * 0.04, 0, 100) end
function Stats.EnemyCrush(offset, defense)
	local diff = enemyDiff(offset, math.min(defense, playerLevel() * SKILL_PER_LEVEL))
	if diff < CRUSH_MIN_DIFF then return 0 end
	return clamp(diff * 2 - 15, 0, 100)
end

local function defenseTable(fn, defense)
	local lines = { "Attacker level:" }
	for offset = 0, 3 do
		lines[#lines + 1] = ("%s: %s"):format(levelLabel(offset), pct(fn(offset, defense)))
	end
	return table.concat(lines, "\n")
end

local function defenseRow(label, fn, note)
	return function(statFrame)
		local defense, base, modifier = Stats.Defense()
		local value = fn(3, defense)
		local lines = defenseTable(fn, defense)
		local tail = ("Defense %d"):format(defense)
		if modifier ~= 0 then tail = tail .. (" (%d %s%d)"):format(base, modifier > 0 and "+" or "", modifier) end
		return fill(statFrame, label, pct(value), value, lines, note .. "\n" .. tail)
	end
end

local enemyMissRow = defenseRow("Enemy miss (+3)", Stats.EnemyMiss, "Chance for a melee attacker to miss you.")
local enemyCritRow = defenseRow("Enemy crit (+3)", Stats.EnemyCrit, "Chance for a melee attacker to crit you.")
local crushRow = defenseRow("Crushing blow (+3)", Stats.EnemyCrush, "Chance for a higher-level mob to crush you (150% damage); needs 15+ skill points over your defense.")

local function blockValueRow(statFrame)
	local value = GetShieldBlock() or 0
	local chance = GetBlockChance() or 0
	local lines = ("Block chance: %s\nA block absorbs %s damage from a melee hit."):format(pct(chance), num(value))
	return fill(statFrame, "Block value", num(value), value, lines)
end

--- Camelot's PaperDollFrameStats.lua multiplies GetDodgeChanceFromAttribute by 100 (a fraction) where retail
--- uses it as a percent; trust the camelot reading unless it exceeds the total, which a part never can.
local function attributeShare(fromAttribute, total)
	local raw = fromAttribute or 0
	local scaled = raw * 100
	if total and scaled > total + 0.05 then return raw end
	return scaled
end

local function dodgeFromAgilityRow(statFrame)
	local total = GetDodgeChance() or 0
	local v = attributeShare(GetDodgeChanceFromAttribute(), total)
	return fill(statFrame, "Dodge from agility", pct(v), v, ("Total dodge: %s"):format(pct(total)))
end

local function parryFromStrengthRow(statFrame)
	local total = GetParryChance() or 0
	local v = attributeShare(GetParryChanceFromAttribute(), total)
	return fill(statFrame, "Parry from strength", pct(v), v, ("Total parry: %s"):format(pct(total)))
end

local function armorReductionRow(statFrame)
	local base, effective, _, bonus = UnitArmor("player")
	effective = effective or 0
	local level = safe(UnitEffectiveLevel, "player") or playerLevel()
	local same = (safe(C_PaperDollInfo.GetArmorEffectiveness, effective, level) or 0) * 100
	local boss = (safe(C_PaperDollInfo.GetArmorEffectiveness, effective, level + 3) or 0) * 100
	local lines = ("Physical damage reduced by %s against %s, %s against %s."):format(pct(same), levelLabel(0), pct(boss), levelLabel(3))
	local target = safe(C_PaperDollInfo.GetArmorEffectivenessAgainstTarget, effective)
	if target then lines = lines .. ("\nAgainst your target: %s"):format(pct(target * 100)) end
	local detail = ("Armor %s"):format(num(effective))
	if (bonus or 0) ~= 0 then detail = detail .. (" (%s from items, %s%s from buffs)"):format(num(base or 0), bonus > 0 and "+" or "", num(bonus)) end
	return fill(statFrame, "Armor reduction", pct(same), same, lines, detail)
end

local function holyResistRow(statFrame)
	-- the camelot pane displays the second return (CharacterFrame.lua); the docs call the third "effective"
	local _, real, effective = UnitResistance("player", Enum.Damageclass.Holy)
	effective = real or effective or 0
	if effective == 0 then return nil end
	local function expected(casterLevel) return math.floor(0.75 * effective / (casterLevel * SKILL_PER_LEVEL) * 100) end
	local lines = ("Average Holy damage resisted: %d%% vs %s, %d%% vs %s."):format(expected(playerLevel()), levelLabel(0), expected(playerLevel() + 3), levelLabel(3))
	return fill(statFrame, "Holy resistance", num(effective), effective, lines)
end

-- Weapon skill rows ----------------------------------------------------------------------------------

local function weaponSkillRow(slot, slotLabel)
	return function(statFrame)
		local info = Stats.WeaponSkillInfo(slot)
		if not info then return nil end
		if slot == SLOT_OFFHAND then
			local main = Stats.WeaponSkillInfo(SLOT_MAINHAND)
			if main and main.skillID == info.skillID then return nil end -- same skill as the main hand: one row
		end
		local skill = info.rank + (info.modifier or 0)
		local lines = { slotLabel .. " weapon skill." }
		lines[#lines + 1] = ("vs %s: hit %s, crit %s"):format(levelLabel(0), signedPct(hitDelta(0, skill)), signedPct(critDelta(0, skill)))
		lines[#lines + 1] = ("vs %s: hit %s, crit %s"):format(levelLabel(3), signedPct(hitDelta(3, skill)), signedPct(critDelta(3, skill)))
		if slot ~= SLOT_RANGED then
			lines[#lines + 1] = ("Glancing blows vs %s: %s of hits for %s less damage"):format(levelLabel(3), pct(glancingChance(3, skill)), pct(glancingPenalty(3, skill)))
		end
		return fill(statFrame, skillLabel(info, slotLabel), skillText(info), skill, table.concat(lines, "\n"))
	end
end

-- Gear -----------------------------------------------------------------------------------------------

local function itemLevelRow(statFrame)
	local overall, equipped = safe(_G.GetAverageItemLevel)
	if type(equipped) ~= "number" then return nil end
	local minimum = safe(C_PaperDollInfo.GetMinItemLevel)
	local shown = math.floor(math.max(minimum or 0, equipped))
	local lines = ("Equipped: %.1f\nIncluding bags: %.1f"):format(equipped, overall or equipped)
	return fill(statFrame, "Item level (equipped)", tostring(shown), shown, lines)
end

--- Lowest and average durability across equipped slots (percent), plus the lowest slot's name; nil when nothing has durability.
function Stats.Durability()
	local fn = _G.GetInventoryItemDurability
	if type(fn) ~= "function" then return nil end
	local lowest, lowestSlot, total, count = nil, nil, 0, 0
	for slot = 1, 18 do
		local ok, cur, max = pcall(fn, slot)
		if ok and type(cur) == "number" and type(max) == "number" and max > 0 then
			local p = cur / max * 100
			total, count = total + p, count + 1
			if not lowest or p < lowest then lowest, lowestSlot = p, slot end
		end
	end
	if count == 0 then return nil end
	return lowest, total / count, lowestSlot, count
end

local function durabilityRow(statFrame)
	local lowest, average, lowestSlot, count = Stats.Durability()
	if not lowest then return nil end
	local shown = math.floor(lowest)
	local text = shown .. "%"
	if lowest < 20 then text = (RED_FONT_COLOR_CODE or "|cffff2020") .. text .. CLOSE
	elseif lowest < 50 then text = "|cffffd200" .. text .. CLOSE end
	local lines = ("Lowest: %s at %d%%\nAverage over %d items: %d%%"):format(SLOT_NAMES[lowestSlot] or ("Slot " .. lowestSlot), shown, count, math.floor(average))
	return fill(statFrame, "Durability", text, shown, lines)
end

local function swimSpeedRow(statFrame)
	local _, run, _, swim = GetUnitSpeed("player")
	if not (run and swim) then return nil end
	local base = BASE_MOVEMENT_SPEED or 7
	local runPct, swimPct = run / base * 100, swim / base * 100
	if math.floor(runPct + 0.5) == math.floor(swimPct + 0.5) then return nil end -- Blizzard's Movement speed row already says it
	return fill(statFrame, "Swim speed", ("%d%%"):format(swimPct + 0.5), swimPct, ("Run speed: %d%%"):format(runPct + 0.5))
end

-- Progress -------------------------------------------------------------------------------------------

local function xpRow(statFrame)
	if atMaxLevel() then return nil end
	local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 0
	if xpMax <= 0 then return nil end
	local p = xp / xpMax * 100
	local lines = ("%s / %s\n%s to level %d"):format(num(xp), num(xpMax), num(xpMax - xp), playerLevel() + 1)
	return fill(statFrame, "Experience", pct(p), p, lines)
end

local function restedRow(statFrame)
	if atMaxLevel() then return nil end
	local rested = GetXPExhaustion() or 0
	local xpMax = UnitXPMax("player") or 0
	local share = xpMax > 0 and rested / xpMax * 100 or 0
	local text = rested > 0 and ("%s (%d%%)"):format(num(rested), math.floor(share + 0.5)) or "0"
	local lines = "Rested XP is earned at double rate."
	local _, stateName, factor = safe(GetRestState)
	if stateName then lines = lines .. ("\nRest state: %s (x%s)"):format(tostring(stateName), tostring(factor or "?")) end
	if safe(IsResting) then lines = lines .. "\nYou are resting." end
	return fill(statFrame, "Rested XP", text, rested, lines)
end

--- Unspent talent points: the trait-tree currency Forever's own talent frame shows, with the
--- undocumented legacy Classic global only as a fallback when the trait path yields nothing.
function Stats.UnspentTalents()
	local configID = safe(C_ClassTalents.GetActiveConfigID)
	if configID then
		local config = safe(C_Traits.GetConfigInfo, configID)
		local treeID = type(config) == "table" and type(config.treeIDs) == "table" and config.treeIDs[1]
		if treeID then
			local currencies = safe(C_Traits.GetTreeCurrencyInfo, configID, treeID, true)
			local first = type(currencies) == "table" and currencies[1]
			if type(first) == "table" and type(first.quantity) == "number" then return first.quantity end
		end
	end
	local n = safe(_G.GetNumUnspentTalents) -- legacy client global, only if the trait path gave nothing
	return type(n) == "number" and n or nil
end

local function talentsRow(statFrame)
	local n = Stats.UnspentTalents()
	if n == nil then return nil end
	return fill(statFrame, "Unspent talents", tostring(n), n, n > 0 and "Visit the talent pane to spend them." or "All talent points spent.")
end

--- Legacy points: earned (renown level of the Legacy track), spent and unspent across the Legacy trees.
function Stats.Legacy()
	local consts = Constants and Constants.LegacyConsts
	local faction = consts and consts.LEGACY_REWARD_TRACK_FACTION_ID or LEGACY_FACTION
	local tree = consts and consts.LEGACY_TREE_PROFESSIONS_ID or LEGACY_TREE
	local earned = safe(C_MajorFactions.GetCurrentRenownLevel, faction)
	if type(earned) ~= "number" or earned <= 0 then return nil end -- system not unlocked yet: Blizzard's own UI errors below renown 1
	local spent, unspent
	local configID = safe(C_Traits.GetConfigIDByTreeID, tree)
	if configID then
		local currencies = safe(C_Traits.GetTreeCurrencyInfo, configID, tree, true)
		local first = type(currencies) == "table" and currencies[1]
		if type(first) == "table" then spent, unspent = first.spent, first.quantity end
	end
	return earned, spent, unspent
end

local function legacyRow(statFrame)
	local earned, spent, unspent = Stats.Legacy()
	if not earned then return nil end
	local text = tostring(earned)
	if unspent and unspent > 0 then text = ("%d (%d free)"):format(earned, unspent) end
	local lines = ("Earned: %d"):format(earned)
	if spent then lines = lines .. ("\nSpent: %d\nUnspent: %d"):format(spent, unspent or 0) end
	return fill(statFrame, "Legacy points", text, earned, lines)
end

--- PvP rank number and title (PVPRankFrame.lua); nil when unranked.
function Stats.PvPRank()
	local info = safe(C_MajorFactions.GetMajorFactionProgressionInfo, PVP_RANK_FACTION)
	local rank = type(info) == "table" and info.renownLevel or nil
	if type(rank) ~= "number" or rank <= 0 then return nil end
	local title
	local first = Enum.PvPRanks and Enum.PvPRanks.Rank_1
	if first then
		local faction01 = UnitFactionGroup("player") == "Alliance" and 1 or 0
		title = safe(GetText, "PVP_RANK_" .. (first + rank - 1) .. "_" .. faction01, safe(UnitSex, "player"))
	end
	return rank, title, info.renownReputationEarned, info.renownLevelThreshold
end

local function pvpRankRow(statFrame)
	local rank, title, points, threshold = Stats.PvPRank()
	if not rank then return nil end
	local text = (type(title) == "string" and title ~= "") and title or ("Rank %d"):format(rank)
	local lines = ("Rank %d"):format(rank)
	if type(points) == "number" and type(threshold) == "number" and threshold > 0 then
		lines = lines .. ("\n%s / %s points to the next rank"):format(num(points), num(threshold))
	end
	return fill(statFrame, "PvP rank", text, rank, lines)
end

-- Category / row table --------------------------------------------------------------------------------
--
-- Row fields: stat (our own key, used by the panel and the tests), label, update, and optionally
-- hideAt (always applied), hideZero (default true: hidden at 0 when the option is on), showFunc.

local function shieldEquipped() return safe(C_PaperDollInfo.OffhandHasShield) and true or false end
local function rangedEquipped() return safe(IsRangedWeapon) and true or false end

Stats.categories = {
	{
		key = "melee", name = "Melee",
		rows = {
			{ stat = "LODESTAR_MELEE_HIT", label = "Melee hit", update = meleeHitRow },
			{ stat = "LODESTAR_MELEE_CRIT", label = "Melee crit", update = meleeCritRow },
			{ stat = "LODESTAR_MELEE_HASTE", label = "Melee haste", update = meleeHasteRow },
			{ stat = "LODESTAR_ATTACK_SPEED", label = "Attack speed", update = attackSpeedRow, hideZero = false },
			{ stat = "LODESTAR_MELEE_DPS", label = "Melee DPS", update = meleeDPSRow, hideZero = false },
		},
	},
	{
		key = "ranged", name = "Ranged",
		rows = {
			{ stat = "LODESTAR_RANGED_HIT", label = "Ranged hit", update = rangedHitRow, showFunc = usesRangedHit },
			{ stat = "LODESTAR_RANGED_CRIT", label = "Ranged crit", update = rangedCritRow, showFunc = usesRangedHit },
			{ stat = "LODESTAR_RANGED_HASTE", label = "Ranged haste", update = rangedHasteRow, showFunc = usesRangedHit },
			{ stat = "LODESTAR_RANGED_SPEED", label = "Ranged speed", update = rangedSpeedRow, showFunc = rangedEquipped, hideZero = false },
			{ stat = "LODESTAR_RANGED_DPS", label = "Ranged DPS", update = rangedDPSRow, showFunc = rangedEquipped, hideZero = false },
		},
	},
	{
		key = "spell", name = "Spell",
		rows = {
			{ stat = "LODESTAR_SPELL_HIT", label = "Spell hit", update = spellHitRow },
			{ stat = "LODESTAR_SPELL_CRIT", label = "Spell crit", update = spellCritRow },
			{ stat = "LODESTAR_SPELL_HASTE", label = "Spell haste", update = spellHasteRow },
			{ stat = "LODESTAR_SPELL_HOLY", label = "Holy damage", update = schoolRow(2), hideAt = 0 },
			{ stat = "LODESTAR_SPELL_FIRE", label = "Fire damage", update = schoolRow(3), hideAt = 0 },
			{ stat = "LODESTAR_SPELL_NATURE", label = "Nature damage", update = schoolRow(4), hideAt = 0 },
			{ stat = "LODESTAR_SPELL_FROST", label = "Frost damage", update = schoolRow(5), hideAt = 0 },
			{ stat = "LODESTAR_SPELL_SHADOW", label = "Shadow damage", update = schoolRow(6), hideAt = 0 },
			{ stat = "LODESTAR_SPELL_ARCANE", label = "Arcane damage", update = schoolRow(7), hideAt = 0 },
		},
	},
	{
		key = "regen", name = "Regeneration",
		rows = {
			{ stat = "LODESTAR_MP5", label = "Mana per 5 s", update = mp5Row, showFunc = hasMana },
			{ stat = "LODESTAR_HP5", label = "Health per 5 s", update = hp5Row },
		},
	},
	{
		key = "defense", name = "Defense detail",
		rows = {
			{ stat = "LODESTAR_ENEMY_MISS", label = "Enemy miss (+3)", update = enemyMissRow, hideZero = false },
			{ stat = "LODESTAR_ENEMY_CRIT", label = "Enemy crit (+3)", update = enemyCritRow, hideZero = false },
			{ stat = "LODESTAR_CRUSH", label = "Crushing blow (+3)", update = crushRow },
			{ stat = "LODESTAR_BLOCK_VALUE", label = "Block value", update = blockValueRow, showFunc = shieldEquipped },
			{ stat = "LODESTAR_DODGE_AGI", label = "Dodge from agility", update = dodgeFromAgilityRow },
			{ stat = "LODESTAR_PARRY_STR", label = "Parry from strength", update = parryFromStrengthRow },
			{ stat = "LODESTAR_ARMOR_REDUCTION", label = "Armor reduction", update = armorReductionRow },
			{ stat = "LODESTAR_HOLY_RESIST", label = "Holy resistance", update = holyResistRow, hideAt = 0 },
		},
	},
	{
		key = "weaponSkills", name = "Weapon skills",
		rows = {
			{ stat = "LODESTAR_WEAPON_SKILL_MH", label = "Main hand", update = weaponSkillRow(SLOT_MAINHAND, "Main-hand"), hideZero = false },
			{ stat = "LODESTAR_WEAPON_SKILL_OH", label = "Off hand", update = weaponSkillRow(SLOT_OFFHAND, "Off-hand"), hideZero = false },
			{ stat = "LODESTAR_WEAPON_SKILL_RANGED", label = "Ranged", update = weaponSkillRow(SLOT_RANGED, "Ranged"), hideZero = false },
		},
	},
	{
		key = "gear", name = "Gear",
		rows = {
			{ stat = "LODESTAR_ITEM_LEVEL", label = "Item level (equipped)", update = itemLevelRow },
			{ stat = "LODESTAR_DURABILITY", label = "Durability", update = durabilityRow, hideZero = false },
			{ stat = "LODESTAR_SWIM_SPEED", label = "Swim speed", update = swimSpeedRow, hideZero = false },
		},
	},
	{
		key = "progress", name = "Progress",
		rows = {
			{ stat = "LODESTAR_XP", label = "Experience", update = xpRow, hideZero = false },
			{ stat = "LODESTAR_RESTED", label = "Rested XP", update = restedRow },
			{ stat = "LODESTAR_TALENTS", label = "Unspent talents", update = talentsRow },
			{ stat = "LODESTAR_LEGACY", label = "Legacy points", update = legacyRow },
			{ stat = "LODESTAR_PVP_RANK", label = "PvP rank", update = pvpRankRow },
		},
	},
}

Stats.rowByStat = {}
for _, category in ipairs(Stats.categories) do
	for _, row in ipairs(category.rows) do
		row.category = category.key
		Stats.rowByStat[row.stat] = row
	end
end

-- Lodestar_Character: module definition, defaults and settings page.
--
-- Blizzard's Forever character sheet renders its stats pane from two global tables
-- (PAPERDOLL_STATCATEGORIES / PAPERDOLL_STATINFO). This module adds categories of its own to those
-- tables so the hidden numbers (melee/ranged/spell hit split with miss tables, crit and haste split,
-- spell power per school, MP5/HP5, attack speed and DPS, weapon skills, defense detail, block value,
-- armor reduction, item level, durability, XP/rested, talent and Legacy points) show up as ordinary
-- rows with Blizzard's own headers, striping, tooltips and gamepad navigation.
local Lodestar = _G.Lodestar

local Character = Lodestar:NewModule("Character", "AceEvent-3.0", "AceTimer-3.0")
Character.displayName = "Character"
Character.description = "Hidden character-sheet stats (hit/crit/haste split, spell power per school, regen, DPS, weapon skills, defense detail, item level, durability, XP, talents) inside the standard stats pane."
Character.order = 35

Character.defaults = {
	profile = {
		categories = {
			melee = true,
			ranged = true,
			spell = true,
			regen = true,
			defense = true,
			weaponSkills = true,
			gear = true,
			progress = true,
		},
		hideZero = true,
		replaceBlizzardMaxRows = false,
	},
}

local function categoryToggle(order, key, name, desc)
	return {
		type = "toggle", order = order, name = name, desc = desc,
		get = function() return Character.db.profile.categories[key] end,
		set = function(_, v) Character.db.profile.categories[key] = v; Character:RefreshInjection() end,
	}
end

Character.options = {
	desc = {
		type = "description", order = 1, fontSize = "medium",
		name = "Extra categories in the character sheet's stats pane. Hover a row for the details (miss tables against +0..+3 targets, per-school spell power, sources).\n",
	},
	catHeader = { type = "header", order = 10, name = "Categories" },
	catMelee = categoryToggle(11, "melee", "Melee", "Melee hit with miss chances vs +0..+3, melee crit, melee haste, attack speed, DPS."),
	catRanged = categoryToggle(12, "ranged", "Ranged", "Ranged hit and crit (warriors, hunters, rogues), ranged haste, ranged speed and DPS."),
	catSpell = categoryToggle(13, "spell", "Spell", "Spell hit with miss chances vs +0..+3, spell crit, spell haste, spell power per school."),
	catRegen = categoryToggle(14, "regen", "Regeneration", "Mana per 5 s (out of combat / while casting) and health per 5 s."),
	catDefense = categoryToggle(15, "defense", "Defense detail", "Chance for enemies to miss, crit and crush you vs +0..+3, block value, dodge from agility, armor reduction, Holy resistance."),
	catWeaponSkills = categoryToggle(16, "weaponSkills", "Weapon skills", "Skill for the equipped main-hand, off-hand and ranged weapons with hit/crit/glancing deltas."),
	catGear = categoryToggle(17, "gear", "Gear", "Average item level, durability, swim speed."),
	catProgress = categoryToggle(18, "progress", "Progress", "XP and rested XP, unspent talent points, Legacy points, PvP rank."),

	displayHeader = { type = "header", order = 20, name = "Display" },
	hideZero = {
		type = "toggle", order = 21, name = "Hide rows that are zero", width = "full",
		desc = "Like Blizzard's own hit/crit/haste rows: a stat you don't have is left out instead of showing 0.",
		get = function() return Character.db.profile.hideZero end,
		set = function(_, v) Character.db.profile.hideZero = v; Character:RefreshInjection() end,
	},
	replaceMax = {
		type = "toggle", order = 22, name = "Replace Blizzard's Hit / Crit / Haste rows", width = "full",
		desc = "Blizzard's Modifiers category shows only the highest of melee, ranged and spell for each. Hide those three rows while the split rows above are on.",
		get = function() return Character.db.profile.replaceBlizzardMaxRows end,
		set = function(_, v) Character.db.profile.replaceBlizzardMaxRows = v; Character:RefreshInjection() end,
	},
	refresh = {
		type = "execute", order = 30, name = "Refresh stats pane",
		func = function() Character:RequestStatsUpdate(true) end,
	},
}

function Character:OnEnable()
	self:EnableInjection()
end

function Character:OnDisable()
	self:DisableInjection()
end

function Character:OnProfileChanged()
	if self:IsEnabled() then self:RefreshInjection() end
end

Lodestar:RegisterModule(Character)

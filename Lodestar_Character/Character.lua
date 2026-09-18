-- Lodestar_Character: module definition, defaults and settings page.
--
-- The numbers Blizzard's Forever character sheet hides (melee/ranged/spell hit with miss tables, crit
-- and haste split, spell power per school, MP5/HP5, attack speed and DPS, weapon skills, defense detail,
-- block value, armor reduction, item level, durability, XP/rested, talent and Legacy points) are drawn
-- in a panel of our own next to the character sheet. Panel.lua explains why they are NOT put into
-- Blizzard's own stats pane.
local Lodestar = _G.Lodestar

local Character = Lodestar:NewModule("Character", "AceEvent-3.0", "AceTimer-3.0")
Character.displayName = "Character"
Character.description = "Hidden character-sheet stats (hit/crit/haste split, spell power per school, regen, DPS, weapon skills, defense detail, item level, durability, XP, talents) in a panel beside the character sheet."
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
		show = true,
		locked = false,
		-- pos: set once the panel is dragged; nil means "docked to the character sheet".
	},
}

local function categoryToggle(order, key, name, desc)
	return {
		type = "toggle", order = order, name = name, desc = desc,
		get = function() return Character.db.profile.categories[key] end,
		set = function(_, v) Character.db.profile.categories[key] = v; Character:RefreshPanel() end,
	}
end

Character.options = {
	desc = {
		type = "description", order = 1, fontSize = "medium",
		name = "A stats panel beside the character sheet with the numbers the sheet leaves out. Hover a row for the details (miss tables against +0..+3 targets, per-school spell power, sources); right-click the panel for the category toggles.\n",
	},
	show = {
		type = "toggle", order = 2, name = "Show the panel with the character sheet", width = "full",
		desc = "The panel opens and closes with the character sheet. /lode character toggles it.",
		get = function() return Character.db.profile.show end,
		set = function(_, v) Character.db.profile.show = v; Character:UpdatePanel() end,
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
		set = function(_, v) Character.db.profile.hideZero = v; Character:RefreshPanel() end,
	},
	locked = {
		type = "toggle", order = 22, name = "Lock the panel in place", width = "full",
		desc = "While unlocked the panel can be dragged anywhere; its position is saved in this profile.",
		get = function() return Character.db.profile.locked end,
		set = function(_, v) Character.db.profile.locked = v; Character:UpdatePanel() end,
	},
	resetPos = {
		type = "execute", order = 23, name = "Dock it back to the character sheet",
		func = function() Character:ResetPanelPosition() end,
	},
	refresh = {
		type = "execute", order = 30, name = "Refresh the panel",
		func = function() Character:RequestStatsUpdate(true) end,
	},
}

function Character:OnEnable()
	self:EnablePanel()
end

function Character:OnDisable()
	self:DisablePanel()
end

function Character:OnProfileChanged()
	if self:IsEnabled() then self:UpdatePanel() end
end

Lodestar:RegisterModule(Character)

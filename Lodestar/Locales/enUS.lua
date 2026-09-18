-- Lodestar enUS locale (default). Other locales copy this file and translate the right-hand side.
local L = LibStub("AceLocale-3.0"):NewLocale("Lodestar", "enUS", true)
if not L then return end

-- Core
L["Lodestar"] = true
L["Modules"] = true
L["General"] = true
L["Profiles"] = true
L["Enable"] = true
L["Enabled"] = true
L["Disabled"] = true
L["Enable %s"] = true
L["Enable or disable this module. Changes take effect after /reload."] = true
L["Minimap button"] = true
L["Show the Lodestar button on the minimap."] = true
L["Chat messages"] = true
L["Print Lodestar messages to chat (sold junk, repairs, level-ups, ...)."] = true
L["Version notices"] = true
L["Tell me once per session when a guild or party member runs a newer Lodestar."] = true
L["Left-click: settings"] = true
L["Right-click: module toggles"] = true
L["Open settings"] = true
L["A newer Lodestar (%s) is available — you have %s."] = true
L["Loaded modules: %s"] = true
L["No modules loaded. Install Lodestar_Leveling, Lodestar_Economy, Lodestar_UI or Lodestar_Guild."] = true
L["Usage: /lode [config|modules|probe|version|debug]"] = true
L["Module %s not found."] = true
L["Module %s %s. /reload to apply."] = true
L["Probe written to LodestarProbes (%d symbols checked, %d missing). Log out or /reload to flush it to disk."] = true
L["Debug output %s."] = true
L["on"] = true
L["off"] = true

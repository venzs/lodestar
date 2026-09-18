-- Lodestar core: module registry.
--
-- A module is a separate addon (Lodestar_Leveling, ...) that does:
--
--   local Lodestar = _G.Lodestar
--   local M = Lodestar:NewModule("Leveling", "AceEvent-3.0", "AceHook-3.0")
--   M.displayName = "Leveling"           -- shown in settings
--   M.description = "..."                -- shown under the module toggle
--   M.defaults    = { profile = {...} }  -- AceDB namespace defaults
--   M.options     = { ... }              -- AceConfig 'args' table for the module's settings page
--   Lodestar:RegisterModule(M)
--
-- The registry gives the module its own AceDB namespace (M.db), a settings page and an
-- enable toggle that persists per profile. Modules use AceAddon's OnEnable/OnDisable.
local Lodestar = _G.Lodestar

function Lodestar:SetupModuleRegistry()
	self.moduleList = {}
	self.moduleByKey = {}
	self:SetDefaultModuleState(true)
end

--- Register a module created with Lodestar:NewModule.
function Lodestar:RegisterModule(module)
	local key = module.moduleName
	if not key or self.moduleByKey[key] then return end
	module.key = key
	module.displayName = module.displayName or key
	module.db = self.db:RegisterNamespace(key, module.defaults or { profile = {} })
	module.order = module.order or (#self.moduleList + 10)
	tinsert(self.moduleList, module)
	self.moduleByKey[key] = module
	table.sort(self.moduleList, function(a, b) return a.order < b.order end)

	if self.configReady then
		self:AddModuleToBlizOptions(module)
		self:RefreshConfig()
	end
	self:Debug("registered module %s", key)
end

function Lodestar:IsModuleEnabled(key)
	local state = self.db.profile.modules[key]
	if state == nil then return true end
	return state and true or false
end

--- Persist and apply a module's enabled state.
function Lodestar:SetModuleEnabled(key, enabled)
	local module = self.moduleByKey[key]
	if not module then return false end
	self.db.profile.modules[key] = enabled and true or false
	module:SetEnabledState(enabled)
	if self.enabledState then -- core already enabled: toggle live
		if enabled and not module:IsEnabled() then
			module:Enable()
		elseif not enabled and module:IsEnabled() then
			module:Disable()
		end
	end
	return true
end

--- Called from OnEnable / profile change: set the enabled state of every module from the profile.
function Lodestar:ApplyModuleStates()
	for _, module in ipairs(self.moduleList) do
		local enabled = self:IsModuleEnabled(module.key)
		module:SetEnabledState(enabled)
		if self.enabledState then
			if enabled and not module:IsEnabled() then
				module:Enable()
			elseif not enabled and module:IsEnabled() then
				module:Disable()
			end
		end
	end
end

function Lodestar:GetModuleSummary()
	local parts = {}
	for _, module in ipairs(self.moduleList) do
		local color = module:IsEnabled() and "|cff7fff7f" or "|cff888888"
		tinsert(parts, color .. module.displayName .. "|r")
	end
	return table.concat(parts, ", ")
end

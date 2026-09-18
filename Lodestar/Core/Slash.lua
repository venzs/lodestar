-- Lodestar core: /lode and /lodestar.
-- Modules add their own verbs with Lodestar:RegisterSlashVerb("xp", handler, "description").
local Lodestar = _G.Lodestar
local L = Lodestar.L

local verbs = {}
local verbOrder = {}

function Lodestar:RegisterSlashVerb(verb, handler, help)
	verb = verb:lower()
	if not verbs[verb] then tinsert(verbOrder, verb) end
	verbs[verb] = { handler = handler, help = help }
end

local function printHelp()
	Lodestar:Say(L["Usage: /lode [config|modules|probe|version|debug]"])
	for _, verb in ipairs(verbOrder) do
		local v = verbs[verb]
		if v.help then Lodestar:Say("  |cffffff7f/lode %s|r — %s", verb, v.help) end
	end
end

function Lodestar:SetupSlash()
	self:RegisterChatCommand("lode", "HandleSlash")
	self:RegisterChatCommand("lodestar", "HandleSlash")

	self:RegisterSlashVerb("config", function() self:OpenConfig() end, "open settings")
	self:RegisterSlashVerb("modules", function(rest)
		local name, state = strsplit(" ", rest or "", 2)
		if name and name ~= "" then
			local module
			for _, m in ipairs(self.moduleList) do
				if m.key:lower() == name:lower() then module = m end
			end
			if not module then self:Say(L["Module %s not found."], name) return end
			local enabled = state ~= "off" and state ~= "disable"
			if state == nil or state == "" then enabled = not self:IsModuleEnabled(module.key) end
			self:SetModuleEnabled(module.key, enabled)
			self:Say("%s: %s.", module.displayName, enabled and L["Enabled"] or L["Disabled"])
		else
			self:Say(L["Loaded modules: %s"], self:GetModuleSummary())
		end
	end, "list modules, or /lode modules <name> [on|off]")
	self:RegisterSlashVerb("probe", function() self:RunProbe() end, "record API availability to LodestarProbeDB")
	self:RegisterSlashVerb("version", function()
		local _, build, _, toc = GetBuildInfo()
		self:Say("Lodestar %s on client %s (toc %s)%s", self.version, tostring(build), tostring(toc), self.IsForever and " — Forever" or "")
	end, "show version")
	self:RegisterSlashVerb("errors", function(rest)
		if rest == "clear" then
			local hidden = #self:GetRecordedErrors()
			self:ClearRecordedErrors()
			self:Say("Cleared: %d recorded Lodestar error(s) hidden. Blizzard's own list still holds them until /reload.", hidden)
			return
		end
		self:PrintErrors()
	end, "list Lodestar Lua errors and blocked calls (or /lode errors clear)")
	self:RegisterSlashVerb("debug", function()
		self.db.global.debug = not self.db.global.debug
		self:Say(L["Debug output %s."], self.db.global.debug and L["on"] or L["off"])
	end, "toggle debug output")
end

function Lodestar:HandleSlash(input)
	local verb, rest = self:GetArgs(input or "", 1)
	if not verb or verb == "" then
		self:OpenConfig()
		return
	end
	local entry = verbs[verb:lower()]
	if not entry then
		printHelp()
		return
	end
	local remainder = input:sub((rest or 1))
	entry.handler(strtrim(remainder or ""))
end

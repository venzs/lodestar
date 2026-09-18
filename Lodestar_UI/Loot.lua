-- Lodestar_UI: fast auto-loot — grab every slot as soon as the loot window is ready.
local Lodestar = _G.Lodestar
local UI = Lodestar:GetModule("UI")

local lastLoot = 0

function UI:LOOT_READY(_, autoLoot)
	if not self.db.profile.loot.fast then return end
	local auto = autoLoot
	if auto == nil then
		auto = GetCVarBool("autoLootDefault")
		if IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
	end
	if not auto then return end
	local now = GetTime()
	if now - lastLoot < 0.3 then return end
	lastLoot = now
	local n = GetNumLootItems()
	for i = n, 1, -1 do
		LootSlot(i)
	end
end

function UI:EnableLoot()
	self:RegisterEvent("LOOT_READY")
end

function UI:DisableLoot()
	self:UnregisterEvent("LOOT_READY")
end

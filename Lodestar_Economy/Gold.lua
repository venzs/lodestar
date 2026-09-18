-- Lodestar_Economy: account-wide gold ledger and session tracking.
local Lodestar = _G.Lodestar
local Economy = Lodestar:GetModule("Economy")

local FormatMoney, ClassColorText = Lodestar.FormatMoney, Lodestar.ClassColorText

local sessionStart

function Economy:RecordGold()
	local chars = self.db.global.chars
	local realm, name = Lodestar.player.realm, Lodestar.player.name
	-- Early builds keyed by the normalized realm name; fold those entries into the display name.
	local normalized = Lodestar.player.realmNormalized
	if normalized and normalized ~= realm and chars[normalized] then
		chars[realm] = chars[realm] or {}
		for n, entry in pairs(chars[normalized]) do chars[realm][n] = chars[realm][n] or entry end
		chars[normalized] = nil
	end
	chars[realm] = chars[realm] or {}
	chars[realm][name] = {
		money = GetMoney(),
		class = Lodestar.player.class,
		faction = Lodestar.player.faction,
		updated = time(),
	}
end

function Economy:PLAYER_MONEY()
	self:RecordGold()
end

function Economy:GetSessionGoldDelta()
	if not sessionStart then return 0 end
	return GetMoney() - sessionStart
end

function Economy:PrintGold()
	local chars = self.db.global.chars
	local grand = 0
	local realms = {}
	for realm in pairs(chars) do tinsert(realms, realm) end
	table.sort(realms, function(a, b)
		if a == Lodestar.player.realm then return true end
		if b == Lodestar.player.realm then return false end
		return a < b
	end)
	for _, realm in ipairs(realms) do
		local list = {}
		local realmTotal = 0
		for name, entry in pairs(chars[realm]) do
			tinsert(list, { name = name, entry = entry })
			realmTotal = realmTotal + (entry.money or 0)
		end
		table.sort(list, function(a, b) return (a.entry.money or 0) > (b.entry.money or 0) end)
		Lodestar:Say("|cffffd700%s|r — %s", realm, FormatMoney(realmTotal))
		for _, item in ipairs(list) do
			Lodestar:Say("  %s  %s", ClassColorText(item.name, item.entry.class), FormatMoney(item.entry.money or 0))
		end
		grand = grand + realmTotal
	end
	if #realms > 1 then Lodestar:Say("Total: %s", FormatMoney(grand)) end
	local delta = self:GetSessionGoldDelta()
	Lodestar:Say("This session: %s%s", delta >= 0 and "+" or "", FormatMoney(delta))
end

function Economy:EnableGold()
	sessionStart = sessionStart or GetMoney()
	self:RegisterEvent("PLAYER_MONEY")
	self:RegisterEvent("PLAYER_LOGOUT", "RecordGold")
	self:RecordGold()
	if not self.goldSlash then
		self.goldSlash = true
		Lodestar:RegisterSlashVerb("gold", function() self:PrintGold() end, "gold on every character")
		Lodestar:RegisterTooltipProvider(function(tooltip)
			if not self:IsEnabled() or not self.db.profile.gold.sessionInTooltip then return end
			local delta = self:GetSessionGoldDelta()
			tooltip:AddDoubleLine("Gold", FormatMoney(GetMoney()), 1, 0.82, 0, 1, 1, 1)
			tooltip:AddDoubleLine("This session", (delta >= 0 and "+" or "") .. FormatMoney(delta), 1, 0.82, 0,
				delta >= 0 and 0.5 or 1, delta >= 0 and 1 or 0.5, 0.5)
		end)
	end
end

function Economy:DisableGold()
	self:UnregisterEvent("PLAYER_MONEY")
	self:UnregisterEvent("PLAYER_LOGOUT")
end

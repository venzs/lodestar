-- Lodestar core: shared helpers available to every module as Lodestar.<name> or Lodestar:<method>.
local Lodestar = _G.Lodestar
local L = Lodestar.L

local COLOR, RESET = Lodestar.COLOR, "|r"
local PREFIX = COLOR .. "Lodestar" .. RESET .. ": "

-- Printing -------------------------------------------------------------------

--- Print a user-facing message, honouring the "chat messages" setting.
function Lodestar:Msg(fmt, ...)
	if self.db and not self.db.profile.chatMessages then return end
	local text = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

--- Print regardless of the chat setting (command feedback, errors).
function Lodestar:Say(fmt, ...)
	local text = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

function Lodestar:Debug(fmt, ...)
	if not (self.db and self.db.global.debug) then return end
	local text = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
	DEFAULT_CHAT_FRAME:AddMessage("|cff888888Lodestar[dbg]|r " .. text)
end

-- Formatting -----------------------------------------------------------------

function Lodestar.FormatMoney(copper)
	copper = math.floor(tonumber(copper) or 0)
	local neg = copper < 0
	if neg then copper = -copper end
	local text = C_CurrencyInfo.GetCoinTextureString(copper)
	return neg and ("-" .. text) or text
end

--- Compact money for tight spaces: 12g34s, 45s, 3c (negatives render as -12g34s)
function Lodestar.FormatMoneyShort(copper)
	copper = math.floor(tonumber(copper) or 0)
	-- Lua 5.1's % and integer division both round toward negative infinity, so a negative copper
	-- amount without this produced "0c" -- a silent zero wherever a cost or a loss is shown.
	local neg = copper < 0
	if neg then copper = -copper end
	local sign = neg and "-" or ""
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return sign .. ("|cffffd700%dg|r|cffc7c7cf%02ds|r"):format(g, s) end
	if s > 0 then return sign .. ("|cffc7c7cf%ds|r|cffeda55f%02dc|r"):format(s, c) end
	return sign .. ("|cffeda55f%dc|r"):format(c)
end

--- 1h 12m / 12m 05s / 45s
function Lodestar.FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

--- 12.3k / 1.2m / 950
function Lodestar.FormatNumberShort(n)
	n = tonumber(n) or 0
	local a = math.abs(n)
	if a >= 1e6 then return ("%.1fm"):format(n / 1e6) end
	if a >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	return ("%d"):format(n)
end

function Lodestar.ClassColor(classFile)
	-- The CUSTOM_CLASS_COLORS convention is that the custom palette wins; checking Blizzard's table
	-- first meant colourblind users' class colours never took effect anywhere in the suite.
	local c = classFile and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile]) or RAID_CLASS_COLORS[classFile])
	if c then return c end
	return NORMAL_FONT_COLOR
end

function Lodestar.ClassColorText(text, classFile)
	local c = Lodestar.ClassColor(classFile)
	if c.WrapTextInColorCode then return c:WrapTextInColorCode(text) end
	if c.colorStr then return ("|c%s%s|r"):format(c.colorStr, text) end
	-- %02x truncates a float in Lua 5.1 (0.78 * 255 = 198.9 -> "c6"), so round first.
	return ("|cff%02x%02x%02x%s|r"):format(
		math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), text)
end

local function normalizeRealm(realm)
	return (tostring(realm or ""):gsub("[%s%-]", ""))
end

--- Split "Name-Realm" and fall back to the player's realm (normalized form).
function Lodestar.SplitName(fullName)
	local name, realm = strsplit("-", fullName or "", 2)
	if not realm or realm == "" then realm = Lodestar.player and Lodestar.player.realmNormalized end
	return name, realm
end

--- Short name for display: drops the realm when it matches ours.
function Lodestar.ShortName(fullName)
	local name, realm = Lodestar.SplitName(fullName)
	if normalizeRealm(realm) == normalizeRealm(Lodestar.player.realmNormalized) then return name end
	return name .. "-" .. realm
end

--- A short, stable id for a contributor, derived from "Name-Realm".
---
--- The harvest needs to tell one contributor's sessions apart -- to weight a position seen by three
--- people differently from one seen three times by the same person, and to see whether a zone is
--- genuinely covered or covered by one player twice. A name does that, and so does a hash of one,
--- and the hash is what travels: `/lode share`, the README and the packaged INSTALL.txt can then all
--- say the harvest carries no character name and be plainly true, in the file as well as the paste.
---
--- It is a stable pseudonym, not anonymity. Anyone holding a short list of candidate names can hash
--- them and compare, and nothing here pretends otherwise. What it buys is that a harvest handed
--- around a Discord, or bundled into the shipped database, does not have names sitting in it.
---
--- djb2 in plain arithmetic: Lua 5.1 has no bitwise operators and the `bit` library is not available
--- everywhere this runs. Kept under 2^31 so string.format("%x") is safe.
function Lodestar.ContributorID(fullName)
	if type(fullName) ~= "string" or fullName == "" then return nil end
	local h = 5381
	for i = 1, #fullName do
		h = (h * 33 + fullName:byte(i)) % 2147483647
	end
	return ("%08x"):format(h)
end

--- NPC/creature id from a unit GUID, nil for players.
function Lodestar.NpcIDFromGUID(guid)
	if not guid then return nil end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" or unitType == "GameObject" then
		return tonumber(id)
	end
end

-- Version compare -------------------------------------------------------------

--- Returns -1 / 0 / 1 comparing dotted version strings ("0.3.1" < "0.10.0").
function Lodestar.CompareVersions(a, b)
	if a == b then return 0 end
	if a == "dev" then return 1 end
	if b == "dev" then return -1 end
	local ai, bi = { strsplit(".", a) }, { strsplit(".", b) }
	for i = 1, math.max(#ai, #bi) do
		local x, y = tonumber((ai[i] or "0"):match("%d+")) or 0, tonumber((bi[i] or "0"):match("%d+")) or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	return 0
end

-- Tooltip lines from modules ---------------------------------------------------

Lodestar.tooltipProviders = {}

--- Modules register a function(tooltip) that adds lines to the minimap button tooltip.
function Lodestar:RegisterTooltipProvider(fn)
	tinsert(self.tooltipProviders, fn)
end

-- Safe wrappers ----------------------------------------------------------------

--- Call fn(...) in protected mode; report errors through Debug and return nil.
function Lodestar.Try(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		Lodestar:Debug("error: %s", tostring(a))
		return nil
	end
	return a, b, c, d
end

--- True when the API namespace/function path exists, e.g. Lodestar.HasAPI("C_MerchantFrame.SellAllJunkItems").
function Lodestar.HasAPI(path)
	local node = _G
	for part in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return false end
		node = node[part]
		if node == nil then return false end
	end
	return true
end

Lodestar.L = L

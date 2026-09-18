-- Lodestar_UI: clickable URLs, timestamps (via the game's own CVar), and a copy-chat button.
local Lodestar = _G.Lodestar
local UI = Lodestar:GetModule("UI")

local URL_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SYSTEM", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
}

local LINK_TYPE = "lodeurl"
local copyButton

local function linkify(url)
	return ("|H%s:%s|h|cff4fc3f7[%s]|r|h"):format(LINK_TYPE, url, url)
end

local function urlFilter(_, _, msg, ...)
	if not UI:IsEnabled() or not UI.db.profile.chat.urls then return false end
	if not msg or not msg:find("%w") then return false end
	-- Skip messages that already carry hyperlinks; nesting them breaks rendering.
	if msg:find("|H", 1, true) then return false end
	local changed = false
	msg = msg:gsub("(https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", function(url)
		changed = true
		return linkify(url)
	end)
	if not changed then
		msg = msg:gsub("%f[%w](www%.[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", function(url)
			changed = true
			return linkify(url)
		end)
	end
	if changed then return false, msg, ... end
	return false
end

-- Copy box lives in the core (Lodestar:ShowCopyBox) so other modules can use it.
function UI:ShowCopyBox(text, title)
	Lodestar:ShowCopyBox(text, title)
end

-- The URL is everything after the first colon of the link data (it carries colons of its own).
local function urlFromLink(link, linkData)
	if type(linkData) == "table" and linkData.options then return linkData.options end
	local kind, url = strsplit(":", link or "", 2)
	if kind == LINK_TYPE then return url end
end

-- 12.x link-handler registry entry: runs instead of Blizzard's ItemRefTooltip fallthrough.
local function onLodeUrl(link, _, linkData)
	local url = urlFromLink(link, linkData)
	if UI:IsEnabled() and url and url ~= "" then
		UI:ShowCopyBox(url)
	end
	return LinkProcessorResponse.Handled
end

-- Fallback for clients without LinkUtil.RegisterLinkHandler: a post-hook on SetItemRef.
local function onHyperlink(link)
	if not UI:IsEnabled() then return end
	local url = urlFromLink(link)
	if url and url ~= "" then
		UI:ShowCopyBox(url)
	end
end

-- Copy-chat button ------------------------------------------------------------------------------

local function stripMarkup(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H[^|]-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return text
end

local function copyChat(chatFrame)
	local lines = {}
	local n = chatFrame:GetNumMessages()
	for i = math.max(1, n - 300), n do
		local text = chatFrame:GetMessageInfo(i)
		if text then
			-- Lines received under chat-messaging lockdown (dungeons, raids, PvP) are secret values;
			-- string operations on them raise an error, so placeholder them instead.
			if canaccessvalue(text) then
				tinsert(lines, stripMarkup(text))
			else
				tinsert(lines, "[message hidden by chat restrictions]")
			end
		end
	end
	UI:ShowCopyBox(table.concat(lines, "\n"))
end

function UI:UpdateCopyButton()
	local want = self:IsEnabled() and self.db.profile.chat.copyButton
	if want and not copyButton and ChatFrame1 then
		copyButton = CreateFrame("Button", "LodestarCopyChatButton", ChatFrame1)
		copyButton:SetSize(18, 18)
		copyButton:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", 2, 4)
		copyButton:SetAlpha(0.4)
		copyButton:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
		copyButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		copyButton:SetScript("OnClick", function() copyChat(ChatFrame1) end)
		copyButton:SetScript("OnEnter", function(btn)
			btn:SetAlpha(1)
			GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
			GameTooltip:SetText("Copy chat")
			GameTooltip:Show()
		end)
		copyButton:SetScript("OnLeave", function(btn) btn:SetAlpha(0.4) GameTooltip:Hide() end)
	end
	if copyButton then copyButton:SetShown(want and true or false) end
end

-- Timestamps ------------------------------------------------------------------------------------

function UI:ApplyTimestamps()
	local c = self.db.profile.chat
	if not self:IsEnabled() then return end
	if c.timestamps then
		local fmt = (c.timestampFormat or "%H:%M") .. " "
		if GetCVar("showTimestamps") ~= fmt then SetCVar("showTimestamps", fmt) end
	elseif self.timestampsApplied and GetCVar("showTimestamps") ~= "none" then
		SetCVar("showTimestamps", "none")
	end
	self.timestampsApplied = c.timestamps
end

-- Lifecycle ---------------------------------------------------------------------------------------

function UI:EnableChat()
	if not self.chatHooked then
		self.chatHooked = true
		-- ChatFrame_AddMessageEventFilter only exists via the deprecation shim (loadDeprecationFallbacks CVar).
		local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
		for _, event in ipairs(URL_EVENTS) do
			addFilter(event, urlFilter)
		end
		if LinkUtil and LinkUtil.RegisterLinkHandler and not LinkUtil.IsLinkHandlerRegistered(LINK_TYPE) then
			LinkUtil.RegisterLinkHandler(LINK_TYPE, onLodeUrl)
		else
			hooksecurefunc("SetItemRef", onHyperlink)
		end
	end
	self:ApplyTimestamps()
	self:UpdateCopyButton()
end

function UI:DisableChat()
	self:UpdateCopyButton()
end

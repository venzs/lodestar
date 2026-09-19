-- Lodestar_Guild: the guild board window (/lode guild).
-- Merges the game's guild roster (C_Club) with the live presence other Lodestar users send.
local Lodestar = _G.Lodestar
local Guild = Lodestar:GetModule("Guild")

local ROWS = 18
local ROW_HEIGHT = 18
local COLS = { name = 150, level = 36, zone = 170, xp = 40, note = 120 }
local PRESENCE_TTL = 20 * 60 -- seconds before a presence entry is considered stale
local HEADER_TOP = 72        -- title, summary and the (optional) restriction notice sit above the columns
local FOOTER = 52            -- column header (18) + its 2px gap, then the hint line and the bottom border inset

local RESTRICTED_NOTICE = "Addon messages are restricted on this realm — showing the guild roster only"
local RESTRICTED_SHORT = "roster only (addon messages restricted)"

local BOARD_ANCHOR = { point = "CENTER", rel = "CENTER", x = 0, y = 0 }

local board
local rows = {}
local offset = 0
local refreshTimer

local function classFileFromID(classID)
	if not classID then return nil end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classID)
		return info and info.classFile
	end
end

--- True while the client hides club member data behind secret values (instances, PvP, encounters).
local function chatLocked()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

--- Build the merged list of guildmates.
function Guild:CollectRows()
	local list, seen = {}, {}
	local now = GetTime()
	local myZone = GetRealZoneText()
	local sameZoneFirst = self.db.profile.board.sameZoneFirst

	-- In chat-messaging lockdown C_Club member info comes back as secret values that tainted code
	-- cannot read, so skip the roster merge and show presence-only rows until it lifts.
	local clubId = not chatLocked() and C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
	if clubId then
		for _, memberId in ipairs(C_Club.GetClubMembers(clubId) or {}) do
			local info = C_Club.GetMemberInfo(clubId, memberId)
			local secret = info and issecretvalue and (issecretvalue(info.name) or issecretvalue(info.presence))
			if info and not secret and info.name and not info.isSelf then
				local online = info.presence ~= Enum.ClubMemberPresence.Offline and info.presence ~= Enum.ClubMemberPresence.Unknown
				if online or self.db.profile.board.showOffline then
					local short = Lodestar.ShortName(info.name)
					local p = self.presence[short]
					local fresh = p and (now - p.t) < PRESENCE_TTL
					seen[short] = true
					tinsert(list, {
						name = short,
						class = (fresh and p.c) or classFileFromID(info.classID),
						level = (fresh and p.l) or info.level or 0,
						zone = (fresh and p.z ~= "" and p.z) or info.zone or "",
						sub = fresh and p.s or nil,
						xp = fresh and p.x or nil,
						note = fresh and p.n or nil,
						online = online,
						lodestar = fresh and true or false,
						rank = info.guildRank,
					})
				end
			end
		end
	end
	-- Presence from people the roster didn't list (roster not loaded yet, or cross-faction guild quirks).
	for name, p in pairs(self.presence) do
		if not seen[name] and (now - p.t) < PRESENCE_TTL then
			tinsert(list, { name = name, class = p.c, level = p.l or 0, zone = p.z or "", sub = p.s, xp = p.x, note = p.n, online = true, lodestar = true })
		end
	end

	table.sort(list, function(a, b)
		if a.online ~= b.online then return a.online end
		if sameZoneFirst and myZone then
			local az, bz = a.zone == myZone, b.zone == myZone
			if az ~= bz then return az end
		end
		if (a.note ~= nil) ~= (b.note ~= nil) then return a.note ~= nil end
		if a.level ~= b.level then return a.level > b.level end
		return a.name < b.name
	end)
	return list
end

-- Window -----------------------------------------------------------------------------------

local function createRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(COLS.name + COLS.level + COLS.zone + COLS.xp + COLS.note + 16, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent.listAnchor, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)
	local x = 4
	for _, key in ipairs({ "name", "level", "zone", "xp", "note" }) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", x, 0)
		fs:SetWidth(COLS[key] - 4)
		fs:SetJustifyH((key == "level" or key == "xp") and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row[key] = fs
		x = x + COLS[key]
	end
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if not self.data then return end
		if button == "RightButton" then
			if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(self.data.name) end
		else
			Guild:DraftChat("/w " .. self.data.name .. " ")
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.data then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Lodestar.ClassColorText(self.data.name, self.data.class))
		if self.data.rank then GameTooltip:AddLine(self.data.rank, 1, 1, 1) end
		if self.data.sub and self.data.sub ~= "" then GameTooltip:AddLine(self.data.zone .. " — " .. self.data.sub, 1, 1, 1) end
		if self.data.note then GameTooltip:AddLine("Looking for: " .. self.data.note, 0.5, 1, 0.5) end
		GameTooltip:AddLine(self.data.lodestar and "|cff4fc3f7Lodestar user|r" or "|cff888888No Lodestar|r")
		GameTooltip:AddLine("|cffaaaaaaLeft-click: whisper · Right-click: invite|r")
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function createBoard()
	board = CreateFrame("Frame", "LodestarGuildBoard", UIParent, "BackdropTemplate")
	board:SetSize(COLS.name + COLS.level + COLS.zone + COLS.xp + COLS.note + 40, ROWS * ROW_HEIGHT + HEADER_TOP + FOOTER)
	board:SetFrameStrata("HIGH")
	board:SetMovable(true)
	board:EnableMouse(true)
	board:SetClampedToScreen(true)
	board:RegisterForDrag("LeftButton")
	board:SetScript("OnDragStart", board.StartMoving)
	board:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- The whole anchor: saving the point without its relativePoint moved the board on every login.
		Lodestar:SaveAnchor(self, Guild.db.profile.board.pos, "CENTER")
	end)
	board:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	board:Hide()
	tinsert(UISpecialFrames, "LodestarGuildBoard")

	board.title = board:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	board.title:SetPoint("TOP", 0, -16)
	board.title:SetText(Lodestar.COLOR .. "Lodestar|r Guild Board")

	-- The scripted UIPanelCloseButton routes through HideUIPanel, which refuses tainted callers in
	-- combat ("Interface action failed because of an AddOn"). Hiding our own frame is always allowed.
	local close = CreateFrame("Button", nil, board, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() board:Hide() end)

	board.summary = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	board.summary:SetPoint("TOP", board.title, "BOTTOM", 0, -4)

	-- Shown while addon messages are restricted: the presence columns stay empty on purpose.
	board.notice = board:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	board.notice:SetPoint("TOP", board.summary, "BOTTOM", 0, -2)
	board.notice:SetTextColor(1, 0.6, 0.2)
	board.notice:SetText(RESTRICTED_NOTICE)
	board.notice:Hide()

	-- Column headers
	local header = CreateFrame("Frame", nil, board)
	header:SetPoint("TOPLEFT", 20, -HEADER_TOP)
	header:SetSize(10, ROW_HEIGHT)
	local x = 4
	for _, key in ipairs({ "name", "level", "zone", "xp", "note" }) do
		local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", header, "LEFT", x, 0)
		fs:SetWidth(COLS[key] - 4)
		fs:SetJustifyH((key == "level" or key == "xp") and "RIGHT" or "LEFT")
		fs:SetText(({ name = "Name", level = "Lvl", zone = "Zone", xp = "XP", note = "Looking for" })[key])
		x = x + COLS[key]
	end

	board.listAnchor = CreateFrame("Frame", nil, board)
	board.listAnchor:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	board.listAnchor:SetSize(10, 10)
	for i = 1, ROWS do rows[i] = createRow(board, i) end

	board:EnableMouseWheel(true)
	board:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		Guild:RefreshBoard(true)
	end)

	board.hint = board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	board.hint:SetPoint("BOTTOM", 0, 16)

	board:SetScript("OnShow", function()
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		Guild:Query()
		Guild:RefreshBoard(true)
	end)
end

local function renderBoard(self)
	local list = self:CollectRows()
	local online, withLodestar = 0, 0
	for _, r in ipairs(list) do
		if r.online then online = online + 1 end
		if r.lodestar then withLodestar = withLodestar + 1 end
	end
	local guildName = GetGuildInfo("player") or "No guild"
	local comms = self:CommsAvailable()
	if comms then
		board.summary:SetText(("%s — %d online, %d running Lodestar"):format(guildName, online, withLodestar))
		board.hint:SetText("/lode lfg <text> to post a group request · scroll for more")
	else
		-- Roster only: the "running Lodestar" count and the presence columns would just read as broken.
		board.summary:SetText(("%s — %d online"):format(guildName, online))
		board.hint:SetText("/lode lfg <text> drafts a guild chat line for you to send · scroll for more")
	end
	board.notice:SetShown(not comms)
	if offset > math.max(0, #list - ROWS) then offset = math.max(0, #list - ROWS) end
	for i = 1, ROWS do
		local row, data = rows[i], list[i + offset]
		row.data = data
		if data then
			row.name:SetText(Lodestar.ClassColorText(data.name, data.class))
			row.level:SetText(data.level > 0 and tostring(data.level) or "")
			row.zone:SetText(data.zone or "")
			row.xp:SetText(data.xp and (data.xp .. "%") or "")
			row.note:SetText(data.note and ("|cff7fff7f" .. data.note .. "|r") or "")
			local alpha = data.online and 1 or 0.4
			row:SetAlpha(alpha)
			row:Show()
		else
			row:Hide()
		end
	end
end

function Guild:RefreshBoard(immediate)
	if not board or not board:IsShown() then return end
	if not immediate then
		-- Track the handle, not a bare flag: AceAddon runs OnDisable before AceTimer cancels our
		-- timers, so a flag set by a queued refresh would never clear and every later RefreshBoard
		-- would return early for the rest of the session.
		if refreshTimer then return end
		refreshTimer = self:ScheduleTimer(function() refreshTimer = nil self:RefreshBoard(true) end, 1)
		return
	end
	-- Protected so one unreadable (secret) roster value cannot take the whole window down.
	Lodestar.Try(renderBoard, self)
end

function Guild:ToggleBoard()
	if not board then createBoard() end
	if board:IsShown() then
		board:Hide()
		return
	end
	Lodestar:ApplyAnchor(board, self.db.profile.board.pos, UIParent, BOARD_ANCHOR)
	offset = 0
	board:Show()
end

function Guild:OnRosterEvent(event, canRequestRosterUpdate)
	-- Level/zone for guild members come from the roster request; the server flags when it is stale.
	if event == "GUILD_ROSTER_UPDATE" and canRequestRosterUpdate and board and board:IsShown()
		and C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
	self:RefreshBoard()
end

function Guild:EnableBoard()
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnRosterEvent")
	self:RegisterEvent("CLUB_MEMBER_UPDATED", "OnRosterEvent")
	self:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED", "OnRosterEvent")
	if not self.boardSlash then
		self.boardSlash = true
		Lodestar:RegisterSlashVerb("guild", function() self:ToggleBoard() end, "open the guild board")
		Lodestar:RegisterTooltipProvider(function(tooltip)
			if not self:IsEnabled() or not IsInGuild() then return end
			if not self:CommsAvailable() then
				tooltip:AddDoubleLine("Guild board", RESTRICTED_SHORT, 1, 0.82, 0, 1, 0.6, 0.2)
				return
			end
			local n = 0
			local now = GetTime()
			for _, p in pairs(self.presence) do if now - p.t < PRESENCE_TTL then n = n + 1 end end
			tooltip:AddDoubleLine("Guildmates with Lodestar", tostring(n), 1, 0.82, 0, 1, 1, 1)
		end)
	end
end

function Guild:DisableBoard()
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self:UnregisterEvent("CLUB_MEMBER_UPDATED")
	self:UnregisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
	if refreshTimer then self:CancelTimer(refreshTimer) refreshTimer = nil end
	if board then board:Hide() end
end

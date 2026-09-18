-- Lodestar_Leveling: quest log hygiene — the twenty-slot cap, and which quests are dead weight.
--
-- Classic caps the quest log at twenty, and the cap is reached constantly while levelling: you pick
-- up a chain in a new zone and the client refuses with "Your quest log is full", with no hint about
-- what is safe to drop. Half the log is usually quests that went grey three zones ago.
--
-- Sources: C_QuestLog.GetNumQuestLogEntries / GetInfo walk the log (headers included, hence the
-- isHeader skip), GetMaxNumQuestsCanAccept gives the real cap rather than a hard-coded 20, and
-- IsQuestTrivial is the client's own grey/not-grey answer, which beats comparing levels ourselves.
--
-- Nothing is abandoned automatically, ever. Abandoning is irreversible and the player may well be
-- keeping a grey quest on purpose -- an escort they mean to come back to, a chain that unlocks
-- something later. `/lode log drop <name>` exists for when they do want it, and it asks first.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local NAG_FREE = 2           -- warn at this many free slots or fewer
local NAG_INTERVAL = 10 * 60 -- seconds between repeats
local DEFAULT_MAX = 20       -- Classic's cap, used only when the client will not say

local ORANGE, RED, GREY, WHITE = "|cffff9933", "|cffff4040", "|cff999999", "|cffffffff"

local lastNag = -math.huge

local function readable(v)
	return v ~= nil and (canaccessvalue == nil or canaccessvalue(v))
end

local function num(v)
	return (readable(v) and type(v) == "number") and v or nil
end

--- The quest log right now: { count, max, free, trivial = { { id, title, level } }, complete = n }.
function Leveling:QuestLogStatus()
	local out = { count = 0, max = DEFAULT_MAX, free = 0, trivial = {}, complete = 0 }
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return out end
	out.max = num(Q.GetMaxNumQuestsCanAccept and Q.GetMaxNumQuestsCanAccept()) or DEFAULT_MAX
	for i = 1, (num(Q.GetNumQuestLogEntries()) or 0) do
		local info = Q.GetInfo(i)
		if info and not info.isHeader and info.questID then
			out.count = out.count + 1
			if Q.IsComplete and Q.IsComplete(info.questID) then out.complete = out.complete + 1 end
			local trivial = Q.IsQuestTrivial and Q.IsQuestTrivial(info.questID)
			if readable(trivial) and trivial then
				out.trivial[#out.trivial + 1] = { id = info.questID, title = info.title or ("quest " .. info.questID), level = num(info.level) }
			end
		end
	end
	out.free = math.max(0, out.max - out.count)
	return out
end

local function titleList(list, limit)
	local parts = {}
	for i, q in ipairs(list) do
		if limit and i > limit then parts[#parts + 1] = ("and %d more"):format(#list - limit) break end
		parts[#parts + 1] = q.title .. (q.level and (" (" .. q.level .. ")") or "")
	end
	return table.concat(parts, ", ")
end

--- Say something when the log is nearly full, and only then. A full log is not news until it stops
--- you accepting something, and the message is only useful if it names what is safe to drop.
function Leveling:CheckQuestLog()
	if not self:IsEnabled() then return end
	local cfg = self.db.profile.questLog
	if not cfg.nagFull then return end
	local s = self:QuestLogStatus()
	if s.free > NAG_FREE then lastNag = -math.huge return end
	local now = GetTime()
	if now - lastNag < NAG_INTERVAL then return end
	lastNag = now
	local color = s.free <= 0 and RED or ORANGE
	if #s.trivial > 0 then
		Lodestar:Msg("%sQuest log %d/%d.|r %d trivial: %s. |cffffff7f/lode log|r lists them.",
			color, s.count, s.max, #s.trivial, titleList(s.trivial, 3))
	else
		Lodestar:Msg("%sQuest log %d/%d|r — nothing in it has gone grey yet.", color, s.count, s.max)
	end
end

--- `/lode log`: the whole picture, and what could go.
function Leveling:PrintQuestLog()
	local s = self:QuestLogStatus()
	Lodestar:Say("Quest log: %s%d of %d|r used, %d complete and ready to turn in.",
		s.free <= NAG_FREE and ORANGE or WHITE, s.count, s.max, s.complete)
	if #s.trivial == 0 then
		Lodestar:Say("  nothing in it has gone grey.")
		return
	end
	Lodestar:Say("  %d trivial:", #s.trivial)
	for _, q in ipairs(s.trivial) do
		Lodestar:Say("    %s%s|r%s", GREY, q.title, q.level and (" (level " .. q.level .. ")") or "")
	end
	Lodestar:Say("  |cffffff7f/lode log drop <part of the name>|r abandons one, after asking.")
end

--- `/lode log drop <text>`: abandon one trivial quest, with a confirmation. Only trivial ones are
--- candidates -- "drop a" should never be able to throw away the chain you are in the middle of.
function Leveling:DropQuest(text)
	text = strtrim(tostring(text or "")):lower()
	if text == "" then
		Lodestar:Say("Usage: /lode log drop <part of the quest name>")
		return
	end
	local s = self:QuestLogStatus()
	local matches = {}
	for _, q in ipairs(s.trivial) do
		if q.title:lower():find(text, 1, true) then matches[#matches + 1] = q end
	end
	if #matches == 0 then
		Lodestar:Say("No trivial quest matches %q. |cffffff7f/lode log|r lists what can be dropped.", text)
		return
	end
	if #matches > 1 then
		Lodestar:Say("%d trivial quests match %q: %s. Be more specific.", #matches, text, titleList(matches))
		return
	end
	local q = matches[1]
	if C_QuestLog.CanAbandonQuest and not C_QuestLog.CanAbandonQuest(q.id) then
		Lodestar:Say("The client will not let go of %s.", q.title)
		return
	end
	Leveling.pendingDrop = q
	if StaticPopup_Show then
		StaticPopup_Show("LODESTAR_ABANDON_QUEST", q.title)
	else
		Lodestar:Say("Cannot show a confirmation on this client; abandon %s from the quest log instead.", q.title)
	end
end

--- Carry out a confirmed abandon. Selecting the quest first is Blizzard's own sequence: SetAbandonQuest
--- reads the selection, and AbandonQuest acts on what SetAbandonQuest staged.
function Leveling:ConfirmDropQuest()
	local q = Leveling.pendingDrop
	Leveling.pendingDrop = nil
	if not q then return end
	if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(q.id) end
	if C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() end
	if C_QuestLog.AbandonQuest then
		C_QuestLog.AbandonQuest()
		Lodestar:Msg("Abandoned %s%s|r.", GREY, q.title)
	end
end

--- Through _G on purpose: StaticPopupDialogs is Blizzard's table and adding a key to it is the
--- documented way to declare a dialog, but the generated API list marks it read-only, and YES / NO
--- are GlobalStrings the extractor does not carry. Going through _G says "yes, I mean this global"
--- rather than silencing the check.
local function installPopup()
	local dialogs = _G.StaticPopupDialogs
	if not dialogs or dialogs["LODESTAR_ABANDON_QUEST"] then return end
	dialogs["LODESTAR_ABANDON_QUEST"] = {
		text = "Abandon %s?\n\nIt has gone grey, but this cannot be undone.",
		button1 = _G.YES or "Yes",
		button2 = _G.NO or "No",
		OnAccept = function() Leveling:ConfirmDropQuest() end,
		OnCancel = function() Leveling.pendingDrop = nil end,
		timeout = 30,
		whileDead = true,
		hideOnEscape = true,
		showAlert = true,
	}
end

function Leveling:EnableQuestLog()
	installPopup()
	if not Leveling.questLogSlash then
		Leveling.questLogSlash = true
		Lodestar:RegisterSlashVerb("log", function(rest)
			rest = strtrim(tostring(rest or ""))
			local verb, arg = rest:match("^(%S+)%s*(.*)$")
			if verb and verb:lower() == "drop" then
				Leveling:DropQuest(arg)
			else
				Leveling:PrintQuestLog()
			end
		end, "quest log: how full it is and what has gone grey")
	end
	-- QUEST_ACCEPTED only. AceEvent keeps ONE handler per event per object, so registering
	-- QUEST_TURNED_IN here would silently replace the XP tracker's handler for it -- the tracker
	-- would stop counting turn-ins and nothing would say so. XPTracker's handler calls us instead.
	self:RegisterEvent("QUEST_ACCEPTED", "CheckQuestLog")
	self:CheckQuestLog()
end

function Leveling:DisableQuestLog()
	self:UnregisterEvent("QUEST_ACCEPTED")
end

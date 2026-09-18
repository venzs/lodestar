-- Lodestar_Leveling: quest auto-accept / auto-turn-in / gossip skipping.
--
-- Flow of the NPC dialog events, and what we do at each step:
--   GOSSIP_SHOW      NPC talk window with optional quest entries -> pick completed quests, then new ones
--   QUEST_GREETING   old-style multi-quest greeting                -> same, using the index APIs
--   QUEST_DETAIL     the "Accept" page                             -> AcceptQuest()
--   QUEST_PROGRESS   the "Continue" page                           -> CompleteQuest() if completable
--   QUEST_COMPLETE   the reward page                               -> GetQuestReward() if 0 or 1 choices
-- Holding the pause modifier skips everything.
local Lodestar = _G.Lodestar
local Leveling = Lodestar:GetModule("Leveling")

local function questCfg() return Leveling.db.profile.quest end

local function isTrivialQuest(questID)
	if not questID then return false end
	if C_QuestLog.IsQuestTrivial then
		local ok, trivial = pcall(C_QuestLog.IsQuestTrivial, questID)
		if ok then return trivial and true or false end
	end
	return false
end

-- GOSSIP_SHOW ---------------------------------------------------------------------

function Leveling:GOSSIP_SHOW()
	local cfg = questCfg()
	if not cfg.autoGossip or self:IsPaused() then return end

	-- Turn-ins first: a completed quest on this NPC.
	if cfg.autoTurnIn then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if quest.isComplete and quest.questID then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end

	-- Then pick up new quests.
	if cfg.autoAccept then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if quest.questID and not (cfg.skipTrivial and quest.isTrivial) and not quest.isIgnored then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
end

-- QUEST_GREETING ------------------------------------------------------------------

function Leveling:QUEST_GREETING()
	local cfg = questCfg()
	if not cfg.autoGossip or self:IsPaused() then return end

	if cfg.autoTurnIn then
		for i = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(i)
			if isComplete then
				SelectActiveQuest(i)
				return
			end
		end
	end

	if cfg.autoAccept then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial = GetAvailableQuestInfo(i)
			if not (cfg.skipTrivial and isTrivial) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

-- QUEST_DETAIL --------------------------------------------------------------------

function Leveling:QUEST_DETAIL(_, questStartItemID)
	local cfg = questCfg()
	if self:IsPaused() then return end
	-- Mirrors QuestFrame_OnEvent's early-outs: item-started quests and area-trigger auto-accepts are
	-- closed by Blizzard (CloseQuest) and re-offered from the objective tracker's OFFER popup, which
	-- fires a fresh QUEST_DETAIL without these flags. Only act when the quest frame is really open.
	if questStartItemID and questStartItemID ~= 0 then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() and QuestIsFromAreaTrigger and QuestIsFromAreaTrigger() then return end
	if QuestFlagsPVP and QuestFlagsPVP() then return end -- let Blizzard's PvP-flag confirmation run

	-- Shared by a party member: the "quest giver" is a player.
	local sharedByPlayer = UnitExists("questnpc") and UnitIsPlayer("questnpc")
	if sharedByPlayer then
		if cfg.acceptShared then AcceptQuest() end
		return
	end

	if not cfg.autoAccept then return end
	if cfg.skipTrivial and isTrivialQuest(GetQuestID()) then return end

	-- Mirrors QuestDetailAcceptButton_OnClick: auto-offered quests are acknowledged, not accepted.
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
	else
		AcceptQuest()
	end
end

function Leveling:QUEST_ACCEPT_CONFIRM(_, name, questTitle)
	local cfg = questCfg()
	if not cfg.acceptEscort or self:IsPaused() then return end
	-- Blizzard already showed its QUEST_ACCEPT (or QUEST_ACCEPT_LOG_FULL) dialog for this event. With a
	-- full log the server would reject the confirm anyway, so leave that dialog to explain it.
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	if (numQuests or 0) >= (MAX_QUESTS or 25) then return end
	ConfirmAcceptQuest()
	if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT") end
	Lodestar:Msg("Accepted %s (started by %s).", tostring(questTitle), tostring(name))
end

-- QUEST_PROGRESS / QUEST_COMPLETE -------------------------------------------------

function Leveling:QUEST_PROGRESS()
	local cfg = questCfg()
	if not cfg.autoTurnIn or self:IsPaused() then return end
	if IsQuestCompletable() then
		CompleteQuest()
	end
end

function Leveling:QUEST_COMPLETE()
	local cfg = questCfg()
	if not cfg.autoTurnIn or self:IsPaused() then return end
	-- Quests that cost money: leave the window open so Blizzard's CONFIRM_COMPLETE_EXPENSIVE_QUEST
	-- prompt runs when the player clicks Complete, instead of paying silently.
	local cost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
	if type(cost) == "number" and cost > 0 then return end
	local choices = GetNumQuestChoices()
	if choices == 0 then
		GetQuestReward(0)
	elseif choices == 1 and cfg.pickSingleReward then
		GetQuestReward(1)
	end
	-- More than one choice: leave the window open for the player.
end

-- Lifecycle --------------------------------------------------------------------------

function Leveling:EnableQuestAutomation()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_GREETING")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_ACCEPT_CONFIRM")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
end

function Leveling:DisableQuestAutomation()
	self:UnregisterEvent("GOSSIP_SHOW")
	self:UnregisterEvent("QUEST_GREETING")
	self:UnregisterEvent("QUEST_DETAIL")
	self:UnregisterEvent("QUEST_ACCEPT_CONFIRM")
	self:UnregisterEvent("QUEST_PROGRESS")
	self:UnregisterEvent("QUEST_COMPLETE")
end

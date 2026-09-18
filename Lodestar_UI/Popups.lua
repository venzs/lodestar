-- Lodestar_UI: popup helpers — fills in the "DELETE" confirmation when destroying a good item.
--
-- Blizzard's DELETE_GOOD_ITEM / DELETE_GOOD_QUEST_ITEM dialogs enable their Yes button only when the edit box
-- holds DELETE_ITEM_CONFIRM_STRING (StaticPopup_StandardConfirmationTextHandler). Setting the text from an
-- addon is allowed; the player still has to click Yes.
local Lodestar = _G.Lodestar
local UI = Lodestar:GetModule("UI")

local DELETE_DIALOGS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local function fillDelete(which)
	if not (UI:IsEnabled() and UI.db.profile.popups and UI.db.profile.popups.fillDelete) then return end
	if not DELETE_DIALOGS[which] then return end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
	if not dialog then return end
	local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
	local expected = _G.DELETE_ITEM_CONFIRM_STRING or "DELETE"
	if editBox and editBox.SetText and editBox:GetText() ~= expected then
		editBox:SetText(expected)
		-- the dialog's OnTextChanged runs from SetText and enables Yes; nothing else to do
	end
end

function UI:EnablePopups()
	if self.popupsHooked then return end
	if not (StaticPopup_Show and hooksecurefunc) then return end
	self.popupsHooked = true
	hooksecurefunc("StaticPopup_Show", function(which)
		if DELETE_DIALOGS[which] then
			-- the edit box is set up after the dialog is shown; let the frame finish first
			C_Timer.After(0, function() fillDelete(which) end)
		end
	end)
end

function UI:DisablePopups()
	-- the hook is permanent; the option and IsEnabled() gate its effect
end

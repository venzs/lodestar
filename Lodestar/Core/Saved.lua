-- Lodestar core: which global a saved variable actually lives in.
--
-- Forever's beta client does not hand back every saved variable it writes. Four probe addons,
-- installed side by side in one account and read across several sessions, split cleanly:
--
--   declared            written at logout   handed back at login
--   ZZTwoA, ZZTwoB      yes                 yes
--   ZZNSA, ZZNSB        yes                 yes
--   ZZMinDB             yes                 NEVER
--   ZZLodeDB            yes                 NEVER
--
-- Lodestar's own four -- LodestarDB, LodestarProbeDB, LodestarScanDB, LodestarShareDB -- behaved
-- like the second group: the client serialised them faithfully on every logout and handed back nil
-- at every login, at file scope and at ADDON_LOADED alike. That is what lost the harvest and reset
-- every frame to its default position on every relog. The variable that separates the two groups is
-- the name: the ones that end in "DB" are the ones that never come back. Length is not it --
-- Blizzard's own DamageMeterPerCharacterSettings is thirty-one characters and persists fine -- and
-- neither is the count, the comma spacing, nor the line endings, all of which were tested and ruled
-- out one at a time.
--
-- Why the client behaves that way is not something an addon can see from the inside, and it may
-- well change before launch. So this does not try to explain it: it keeps the names off the shape
-- that is known to fail, and adopts whatever the old name still holds on the way past, so a player
-- who did get data back loses nothing in the move.
local Lodestar = _G.Lodestar

--- The table for a saved-variable slot, adopting a legacy global if the new one came back empty.
---
--- Call this once, from OnInitialize, BEFORE anything reads the global -- the client populates
--- saved variables after an addon's files run and before its ADDON_LOADED, so file scope is always
--- too early. `legacy` is cleared either way: once its contents have been adopted there is no
--- reason to keep writing a second copy to disk, and leaving it set would make the next login
--- adopt stale data over the real thing.
function Lodestar:AdoptSaved(name, legacy)
	local current = _G[name]
	if type(current) ~= "table" then
		local old = legacy and _G[legacy]
		current = type(old) == "table" and old or {}
		_G[name] = current
		if type(old) == "table" then
			self.adopted = self.adopted or {}
			self.adopted[#self.adopted + 1] = legacy
		end
	end
	if legacy then _G[legacy] = nil end
	return current
end

--- The table for a slot that has no legacy name, created on first use.
function Lodestar:SavedTable(name)
	local t = _G[name]
	if type(t) ~= "table" then t = {} _G[name] = t end
	return t
end

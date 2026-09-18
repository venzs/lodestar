-- Lodestar core: which global a saved variable actually lives in.
--
-- Forever's beta client does not hand back the saved variables it writes. Every session Lodestar's
-- four -- and four standalone probe addons installed alongside them -- were serialised faithfully at
-- logout and came back nil at login, at file scope and at ADDON_LOADED alike. That is what lost the
-- harvest, reset every frame to its default position and restarted guide progress on each relog.
--
-- The first reading of the evidence was that the NAME was the problem: everything that came back
-- had a short name, everything that did not ended in "DB", six addons for six. The next session
-- broke it. ZZTwoA and ZZTwoB, which had been surviving reliably, came back nil as well -- and the
-- sessions where anything had survived turned out to be the ones that began a second or two after
-- the previous one ended. Those are /reloads, where the client can keep the table in memory without
-- reading anything. The sessions that began minutes later, after the game was actually closed, got
-- nothing back whatever the name. So the likeliest explanation now is that this build is not
-- reading addon saved variables from disk at all, and the name was a coincidence of which addons
-- happened to be installed mid-session. ZZNames and ZZOne are deployed to settle it.
--
-- The rename stays either way, and it is cheap: the names it moves away from are the ones that
-- never came back under either theory, nothing depends on the old spellings, and whatever the
-- client turns out to be doing, a saved variable is not more likely to load because it is called
-- LodestarShareDB. What matters more is the adoption below -- on a client that does load from disk,
-- a player upgrading must not have their data quietly replaced by an empty table.
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

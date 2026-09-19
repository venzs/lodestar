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

--- Count this session, and say whether the previous one's count came back.
---
--- Everything written above about what this client does with saved variables is inference from file
--- sizes and from which addons happened to be installed when. This is the measurement instead. It
--- is one integer that nothing in the suite ever resets, written into LodestarProbes at login:
---
---   * it reads 1 on every launch  -> the client is not handing saved variables back from disk
---   * it climbs across /reload but resets after a real quit -> the table only survives in memory
---   * it climbs across a full quit and relaunch -> saved variables work, and any "it forgot where
---     the window was" is a bug in Lodestar, not in the client
---
--- The third case is the one that matters, because it decides whether the frame-anchor and guide
--- progress work is load-bearing or just correct-for-later. `sessionStarts` keeps the last few login
--- times so a relaunch can be told from a /reload by the gap between them, which is the distinction
--- the earlier probes kept getting wrong.
local MAX_STARTS = 12

function Lodestar:CountSession()
	local probes = self:SavedTable("LodestarProbes")
	local previous = tonumber(probes.sessions)
	probes.sessions = (previous or 0) + 1
	probes.sawPreviousSession = previous ~= nil
	probes.sessionStarts = type(probes.sessionStarts) == "table" and probes.sessionStarts or {}
	tinsert(probes.sessionStarts, date and date("%Y-%m-%d %H:%M:%S") or "?")
	while #probes.sessionStarts > MAX_STARTS do tremove(probes.sessionStarts, 1) end
	return probes.sessions, probes.sawPreviousSession
end

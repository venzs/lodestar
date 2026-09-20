-- Lodestar_Guide: curated position fixes. HAND-MAINTAINED — the one data file in Data/ that is.
--
-- Everything else here is generated: Vanilla.lua from pfQuest, ATT.lua from AllTheThings, Forever.lua
-- from player harvests. This file is for positions that none of those three have and that no amount
-- of waiting will produce, because the thing has no spawn table to harvest: an object that only
-- exists once a quest item is used, a mob that is summoned rather than spawned, a location the
-- client only ever describes in quest text.
--
-- RULES
--
--   * Gap-fill only. Merging never overwrites a field another source already filled. That makes an
--     entry here self-expiring: the day pfQuest or a harvest learns the position, this one stops
--     being consulted and can be deleted without changing any behaviour. An overlay that overrides
--     is an overlay you have to remember to revisit; this one is not.
--   * Every entry names its source and the date it was taken. A coordinate with no provenance is
--     indistinguishable from a guess six months later, and this project's standing rule is that a
--     confident wrong arrow is worse than no arrow.
--   * `approx = true` marks a position derived from prose rather than read off a map. It is still
--     better than nothing -- it puts the player in the right corner of the right zone -- but it is
--     not the same claim as a point coordinate, and the two should not be indistinguishable in the
--     file that records them.
--
-- Coordinates use pfQuest area ids, the same namespace as Vanilla.lua: { areaID, x, y }.
local Guide = _G.Lodestar:GetModule("Guide")
local C = { npcs = {}, objs = {}, items = {}, quests = {} }
Guide.CuratedData = C

-- 148 Darkshore, 405 Desolace.

-- The Scrying Bowl does not exist until you use the Phial of Scrying at the Master's Glaive, so it
-- has no spawn row anywhere and never will. It is both the ender of The Master's Glaive (944) and
-- the giver of The Twilight Camp (949), which is why one missing object produced two warnings.
-- source: wowhead.com/forever/quest=944, 2026-09-19
C.objs[10076] = { n = "Scrying Bowl", c = { { 148, 38.55, 86.33 } } }

-- Ghost-o-plasm Round Up: the ghosts are summoned by the Crate of Ghost Magnets, so the item has no
-- drop source with a position and the step has never had an arrow. Wowhead describes the spot as
-- the hill between the two Dead Goliaths in the Valley of Bones, "approximately 63-65, 89-91" --
-- a described area, not a read coordinate, hence approx. The midpoint puts the arrow on the hill.
-- source: wowhead.com/forever/quest=6134, 2026-09-19
C.quests[6134] = { spots = { { { 0, 64.0, 90.0, m = 405, approx = true } } } }

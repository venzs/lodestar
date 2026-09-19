-- Lodestar core: one way to remember where a window was left.
--
-- Every movable frame in the suite had its own copy of "save the position, put it back next login",
-- and two of the five copies were wrong in the same way: they saved the anchor POINT and the offsets
-- but threw away the relativePoint.
--
-- That is not a cosmetic difference. A WoW anchor is four values -- which corner of the frame, which
-- corner of the parent, and the offset between them -- and after a drag the two corners are usually
-- NOT the same one. Save (TOPLEFT, 271, -290) without its relativePoint and the restore has to guess;
-- guessing "the same corner" measures the same offsets against a different origin, so the window
-- reappears somewhere else. The player drags it back, that new spot is saved, and it moves again on
-- the next login. It looks exactly like "the addon doesn't save its position" -- and the saved
-- variables are fine, which is why reading them proves nothing.
--
-- Found in Abhi's own WTF folder: the XP tracker was saved at TOPLEFT (271, -290) in one session and
-- came back the next as (-10, -47) with no point at all.
--
-- So there is one implementation, here, and tools/check_anchors.py fails the build if a frame goes
-- back to rolling its own.
local Lodestar = _G.Lodestar

local CORNERS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true,
	LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function corner(v, fallback)
	return (type(v) == "string" and CORNERS[v]) and v or fallback
end

--- Record `frame`'s current anchor into `store` as { point, rel, x, y }.
---
--- `store` is a saved-variables table and `fallback` the point to assume when the client hands back
--- nothing -- which happens when the frame has no anchor yet, not only in error.
---
--- Returns the table it wrote, so a caller that keeps `pos` as a whole value can assign the result.
function Lodestar:SaveAnchor(frame, store, fallback)
	fallback = corner(fallback, "CENTER")
	if type(store) ~= "table" then return nil end
	local point, _, relativePoint, x, y
	if frame and frame.GetPoint then
		point, _, relativePoint, x, y = frame:GetPoint(1)
	end
	store.point = corner(point, fallback)
	store.rel = corner(relativePoint, store.point)
	store.x = tonumber(x) or 0
	store.y = tonumber(y) or 0
	return store
end

--- Put `frame` back where `store` says, relative to `parent`.
---
--- `default` supplies the four values for a frame that has never been dragged: { point, rel, x, y }.
--- A missing `rel` in either the store or the default falls back to that side's `point`, which is
--- the right answer for a frame that has genuinely never moved -- the damage comes from assuming it
--- for one that HAS, which is why SaveAnchor above always writes the real one.
function Lodestar:ApplyAnchor(frame, store, parent, default)
	if not (frame and frame.SetPoint) then return end
	default = default or {}
	store = type(store) == "table" and store or default
	local point = corner(store.point, corner(default.point, "CENTER"))
	local rel = corner(store.rel, store.point and point or corner(default.rel, point))
	local x = tonumber(store.x) or tonumber(default.x) or 0
	local y = tonumber(store.y) or tonumber(default.y) or 0
	frame:ClearAllPoints()
	frame:SetPoint(point, parent or _G.UIParent, rel, x, y)
	return point, rel, x, y
end

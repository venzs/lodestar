-- Lodestar_Guide: trails — learned walkability and arrow routing.
--
-- A straight-line arrow sends the player into cliffs, walls and water. Zygor and RXP fix that with
-- hand-authored paths; Lodestar learns where the ground is walkable from where the player actually
-- walks, and lets guides carry explicit waypoints where the route matters.
--
--   recorder   once a second the player's map position is quantized to a ~20 yd grid cell and kept
--              per uiMapID in LodestarScanDB.trails (the per-account file, not the shareable one).
--              Consecutive samples in different cells link the two (a traversable edge). Flights,
--              death and teleports (jumps of more than two cells) do not link.
--   storage    trails[mapID] = { nx, ny, n, l, rows = { [cy] = "<x0 hex3><2 hex per cell>" } }
--              nx/ny = cells per axis (~20 yd each from C_Map.GetMapWorldSize, else 250 = 0.4 %).
--              Each cell byte is an 8-neighbour link mask (bit i => linked to NEIGHBOUR i), ".." is a
--              cell inside the row's span that was never walked. About 2 bytes per walked cell on
--              disk, a few tens of KB for a fully explored zone.
--   seed       Data/Trails_Seed.lua (tools/trails/seed_roads.py) holds the main roads in the same
--              format on a fixed 0.4 % grid. It is resampled onto the map's grid on first use and
--              consulted read-only next to the learned cells; nothing is written back.
--   query      Guide:TrailPath runs A* over walked cells + links (8-neighbour, cost in yards, the
--              cells around the start and goal are passable even when unwalked), then string-pulls
--              the result: intermediate cells that stay within one cell of the straight segment are
--              dropped, so the arrow points at the farthest node the walked ground runs straight to.
--   arrow      Guide:TrailNext hands the arrow the node to point at (throttled to once a second or
--              one cell of movement). Guide:TrailTargetOverride turns a guide step's `path` points
--              into forced intermediate targets, advanced when within 12 yd.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local CELL_YARDS = 20            -- target cell size when the map's world size is known
local DEFAULT_AXIS = 250         -- 0.4 % cells when it is not
local MAX_AXIS = 4000            -- packed ids are cx * 4096 + cy
local MAX_CELLS = 10000          -- per map (~25-50 KB on disk); links between existing cells are still recorded past this
local MAX_JUMP = 2               -- cells; a bigger jump between samples is a teleport, not a walk
local MAX_EXPAND = 4000          -- A* expansions before giving up (~20 ms of Lua at the cap)
local HEURISTIC_WEIGHT = 1.5     -- weighted A*: see heuristic()
local CACHE_SECONDS = 2
local FAIL_SECONDS = 5           -- do not re-run a failed search for the same goal cell sooner than this
local PATH_INTERVAL = 1          -- arrow: seconds between path checks
local NEAR_YARDS = 25            -- arrow: closer than this, point straight at the target
local LOOKAHEAD_YARDS = 15       -- arrow: skip path nodes closer than this
local WAYPOINT_YARDS = 12        -- step.path points count as reached within this
local WAYPOINT_RESUME_YARDS = 30 -- start a step's path at a later point only when this close to it

local floor, abs, sqrt, max, min = math.floor, math.abs, math.sqrt, math.max, math.min
local byte, sub, rep, format = string.byte, string.sub, string.rep, string.format

-- Neighbour i: E, SE, S, SW, W, NW, N, NE. Bit i of a cell's mask = linked to neighbour i.
local NDX = { [0] = 1, 1, 0, -1, -1, -1, 0, 1 }
local NDY = { [0] = 0, 1, 1, 1, 0, -1, -1, -1 }
local NBIT = { [0] = 1, 2, 4, 8, 16, 32, 64, 128 }
local NIDX = {}                  -- [(dx + 1) * 3 + dy + 1] = i
for i = 0, 7 do NIDX[(NDX[i] + 1) * 3 + NDY[i] + 1] = i end

local trails                     -- LodestarScanDB.trails
local grids = {}                 -- [mapID] = { nx, ny, w, h, ux, uy }   (runtime only)
local seeds = {}                 -- [mapID] = resampled seed record | false
local enabled = false
local ticker

-- Row encoding ----------------------------------------------------------------------------------------------

local HEX, VAL = {}, {}
for i = 0, 255 do HEX[i] = format("%02x", i) end
for i = 0, 15 do VAL[byte(format("%x", i))] = i end

local function hasBit(mask, bit) return mask % (bit + bit) >= bit end

local function rowX0(row) return VAL[byte(row, 1)] * 256 + VAL[byte(row, 2)] * 16 + VAL[byte(row, 3)] end

--- Link mask of a cell, or nil when never walked. Allocation-free.
local function getMask(rows, cx, cy)
	local row = rows[cy]
	if not row then return nil end
	local k = cx - rowX0(row)
	if k < 0 then return nil end
	local p = 4 + k + k
	local hi = VAL[byte(row, p)]
	if not hi then return nil end
	return hi * 16 + VAL[byte(row, p + 1)]
end

local function setMask(rows, cx, cy, mask)
	local row = rows[cy]
	if not row then
		rows[cy] = format("%03x", cx) .. HEX[mask]
		return
	end
	local x0 = rowX0(row)
	if cx < x0 then
		rows[cy] = format("%03x", cx) .. HEX[mask] .. rep("..", x0 - cx - 1) .. sub(row, 4)
		return
	end
	local k = cx - x0
	local len = (#row - 3) / 2
	if k >= len then
		rows[cy] = row .. rep("..", k - len) .. HEX[mask]
		return
	end
	local p = 4 + k + k
	rows[cy] = sub(row, 1, p - 1) .. HEX[mask] .. sub(row, p + 2)
end

-- Grid --------------------------------------------------------------------------------------------------------

local function store()
	if not trails then
		-- Local-only: where this account walked is no use to anyone else, so it stays out of the
		-- shareable LodestarShareDB and lives in LodestarScanDB next to the census cursor.
		local db = Guide:ScanDB()
		db.trails = db.trails or {}
		trails = db.trails
	end
	return trails
end

--- Map size in yards (width, height) or nil.
local function mapYards(mapID)
	if C_Map.GetMapWorldSize then
		local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
		if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	end
	if C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
		local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
		if a and b then
			local w, h = abs(b.y - a.y), abs(b.x - a.x) -- world x runs north-south (map y), world y west-east (map x)
			if w > 0 and h > 0 then return w, h end
		end
	end
	return nil
end

--- The grid for a map: the saved record's cell counts when it has one (keys must stay stable across
--- sessions), else ~20 yd cells from the world size, else 0.4 %.
local function gridFor(mapID)
	local g = grids[mapID]
	if g then return g end
	local w, h = mapYards(mapID)
	local rec = store()[mapID]
	local nx, ny
	if rec and rec.nx and rec.ny then
		nx, ny = rec.nx, rec.ny
	elseif w then
		nx = max(8, min(MAX_AXIS, floor(w / CELL_YARDS + 0.5)))
		ny = max(8, min(MAX_AXIS, floor(h / CELL_YARDS + 0.5)))
	else
		nx, ny = DEFAULT_AXIS, DEFAULT_AXIS
	end
	w = w or nx * CELL_YARDS
	h = h or ny * CELL_YARDS
	g = { nx = nx, ny = ny, w = w, h = h, ux = w / nx, uy = h / ny }
	grids[mapID] = g
	return g
end

local function cellOf(g, x, y)
	local cx, cy = floor(x * g.nx), floor(y * g.ny)
	if cx < 0 then cx = 0 elseif cx >= g.nx then cx = g.nx - 1 end
	if cy < 0 then cy = 0 elseif cy >= g.ny then cy = g.ny - 1 end
	return cx, cy
end

local function mapRecord(mapID)
	local t = store()
	local rec = t[mapID]
	if not rec then
		local g = gridFor(mapID)
		rec = { nx = g.nx, ny = g.ny, n = 0, l = 0, rows = {} }
		t[mapID] = rec
	end
	return rec
end

-- Writing cells ----------------------------------------------------------------------------------------------

--- Mark a cell walked; returns its mask, or nil when the map is full.
local function markCell(rec, cx, cy, force)
	local mask = getMask(rec.rows, cx, cy)
	if mask then return mask end
	if not force and rec.n >= MAX_CELLS then return nil end
	setMask(rec.rows, cx, cy, 0)
	rec.n = rec.n + 1
	return 0
end

--- Link two adjacent cells (both directions).
local function link(rec, ax, ay, bx, by, force)
	local i = NIDX[(bx - ax + 1) * 3 + by - ay + 1]
	if not i then return end
	local ma = markCell(rec, ax, ay, force)
	local mb = markCell(rec, bx, by, force)
	if not ma or not mb then return end
	local bitA, bitB = NBIT[i], NBIT[(i + 4) % 8]
	if not hasBit(ma, bitA) then
		setMask(rec.rows, ax, ay, ma + bitA)
		rec.l = rec.l + 1
	end
	if not hasBit(mb, bitB) then setMask(rec.rows, bx, by, mb + bitB) end
end

--- Walk the 8-connected line from cell a to cell b, marking and linking every cell on it.
local function linkCells(rec, ax, ay, bx, by, force)
	local dx, dy = abs(bx - ax), abs(by - ay)
	local sx, sy = ax < bx and 1 or -1, ay < by and 1 or -1
	local err = dx - dy
	local x, y = ax, ay
	markCell(rec, x, y, force)
	while x ~= bx or y ~= by do
		local e2 = err + err
		local nx, ny = x, y
		if e2 > -dy then err = err - dy nx = x + sx end
		if e2 < dx then err = err + dx ny = y + sy end
		link(rec, x, y, nx, ny, force)
		x, y = nx, ny
	end
end

-- Seed ------------------------------------------------------------------------------------------------------------

--- The seeded roads for a map, resampled onto its grid (once), or nil.
local function seedFor(mapID)
	local s = seeds[mapID]
	if s ~= nil then return s or nil end
	local src
	if Guide.TrailSeed and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		src = info and info.name and Guide.TrailSeed[info.name]
	end
	if not (src and src.rows) then
		seeds[mapID] = false
		return nil
	end
	local g = gridFor(mapID)
	local cell = src.cell or (1 / DEFAULT_AXIS)
	local rec
	if abs(g.nx * cell - 1) < 1e-9 and abs(g.ny * cell - 1) < 1e-9 then
		rec = { nx = g.nx, ny = g.ny, n = src.n or 0, l = src.l or 0, rows = src.rows } -- same grid: use as is
	else
		rec = { nx = g.nx, ny = g.ny, n = 0, l = 0, rows = {} }
		for cy, row in pairs(src.rows) do
			local x0 = rowX0(row)
			for k = 0, (#row - 3) / 2 - 1 do
				local cx = x0 + k
				local mask = getMask(src.rows, cx, cy)
				if mask then
					local rx, ry = cellOf(g, (cx + 0.5) * cell, (cy + 0.5) * cell)
					markCell(rec, rx, ry, true)
					for i = 0, 7 do
						if hasBit(mask, NBIT[i]) then
							local ox, oy = cellOf(g, (cx + NDX[i] + 0.5) * cell, (cy + NDY[i] + 0.5) * cell)
							linkCells(rec, rx, ry, ox, oy, true)
						end
					end
				end
			end
		end
	end
	seeds[mapID] = rec
	return rec
end

--- Walked cells and links seeded for a map (for status output).
function Guide:TrailSeedFor(mapID) return seedFor(mapID) end

-- Recorder ------------------------------------------------------------------------------------------------------

local lastMap, lastCx, lastCy

-- Profile flags are read defensively: Guide.defaults.trails may be absent, and neither reader may allocate.
local function recording()
	local t = Guide.db and Guide.db.profile.trails
	return not t or t.record ~= false
end

local function tick()
	if not recording() then lastMap = nil return end
	if (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then lastMap = nil return end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then lastMap = nil return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then lastMap = nil return end
	local x, y = pos:GetXY()
	if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then lastMap = nil return end
	if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then lastMap = nil return end
	local g = gridFor(mapID)
	local cx, cy = cellOf(g, x, y)
	if mapID == lastMap and cx == lastCx and cy == lastCy then return end
	local rec = mapRecord(mapID)
	if mapID == lastMap and max(abs(cx - lastCx), abs(cy - lastCy)) <= MAX_JUMP then
		linkCells(rec, lastCx, lastCy, cx, cy)
	else
		markCell(rec, cx, cy)
	end
	lastMap, lastCx, lastCy = mapID, cx, cy
end

-- Path query ---------------------------------------------------------------------------------------------------------

-- A* working set, reused between queries (no per-query allocation beyond the result).
local heapId, heapF, heapN = {}, {}, 0
local gScore, cameFrom, closed = {}, {}, {}
local stepCost = {}              -- [i] = yards for a move to neighbour i on the current grid
local chainX, chainY = {}, {}
local lastExpansions = 0         -- of the last A* run, for /lode trails

local function heapPush(id, f)
	heapN = heapN + 1
	local i = heapN
	while i > 1 do
		local p = floor(i / 2)
		if heapF[p] <= f then break end
		heapId[i], heapF[i] = heapId[p], heapF[p]
		i = p
	end
	heapId[i], heapF[i] = id, f
end

local function heapPop()
	local top = heapId[1]
	local id, f = heapId[heapN], heapF[heapN]
	heapN = heapN - 1
	if heapN > 0 then
		local i = 1
		while true do
			local c = i + i
			if c > heapN then break end
			if c < heapN and heapF[c + 1] < heapF[c] then c = c + 1 end
			if heapF[c] >= f then break end
			heapId[i], heapF[i] = heapId[c], heapF[c]
			i = c
		end
		heapId[i], heapF[i] = id, f
	end
	return top
end

--- Link mask from the learned store and the seed (either may be nil).
local function masks(rec, seed, cx, cy)
	return rec and getMask(rec.rows, cx, cy), seed and getMask(seed.rows, cx, cy)
end

local function walkedNear(rec, seed, cx, cy)
	for dx = -1, 1 do
		for dy = -1, 1 do
			local a, b = masks(rec, seed, cx + dx, cy + dy)
			if a or b then return true end
		end
	end
	return false
end

--- Octile distance (the cheapest 8-connected route on an empty grid) times HEURISTIC_WEIGHT: weighted
--- A*. Learned ground is full of axis-only links and open patches where the plain heuristic floods
--- thousands of cells; with the weight the search stays in the corridor toward the goal (an open
--- 70x70 field: 136 expansions instead of hitting the cap) and the route is at worst 1.5x the
--- shortest, in practice within a percent of it.
local function heuristic(dx, dy, ux, uy, diag)
	if dx < 0 then dx = -dx end
	if dy < 0 then dy = -dy end
	local m = dx < dy and dx or dy
	return (m * diag + (dx - m) * ux + (dy - m) * uy) * HEURISTIC_WEIGHT
end

--- A* from (sx, sy) to (gx, gy); true when cameFrom holds a path, false with `capped` when the search
--- ran out of budget (as opposed to running out of cells).
local function astar(g, rec, seed, sx, sy, gx, gy)
	wipe(gScore) wipe(cameFrom) wipe(closed)
	heapN = 0
	local nx, ny, ux, uy = g.nx, g.ny, g.ux, g.uy
	for i = 0, 7 do stepCost[i] = sqrt(NDX[i] * ux * NDX[i] * ux + NDY[i] * uy * NDY[i] * uy) end
	local diag = stepCost[1]
	local startId, goalId = sx * 4096 + sy, gx * 4096 + gy
	gScore[startId] = 0
	heapPush(startId, heuristic(gx - sx, gy - sy, ux, uy, diag))
	local expansions = 0
	while heapN > 0 do
		local id = heapPop()
		if not closed[id] then
			if id == goalId then return true end
			closed[id] = true
			expansions = expansions + 1
			lastExpansions = expansions
			if expansions > MAX_EXPAND then return false, true end
			local cx = floor(id / 4096)
			local cy = id - cx * 4096
			local a, b = masks(rec, seed, cx, cy)
			local gc = gScore[id]
			for i = 0, 7 do
				local x, y = cx + NDX[i], cy + NDY[i]
				if x >= 0 and y >= 0 and x < nx and y < ny then
					local nid = x * 4096 + y
					if not closed[nid] then
						local bit = NBIT[i]
						local ok = (a and hasBit(a, bit)) or (b and hasBit(b, bit))
							or (abs(x - sx) <= 1 and abs(y - sy) <= 1) or (abs(x - gx) <= 1 and abs(y - gy) <= 1)
						if ok then
							local ng = gc + stepCost[i]
							local old = gScore[nid]
							if not old or ng < old then
								gScore[nid] = ng
								cameFrom[nid] = id
								heapPush(nid, ng + heuristic(gx - x, gy - y, ux, uy, diag))
							end
						end
					end
				end
			end
		end
	end
	return false
end

--- True when every chain cell strictly between i and j lies within one cell of the straight segment
--- i -> j (and projects onto it): the walked ground then runs straight there at the grid's own
--- resolution, so the arrow may skip the cells in between.
local function collinear(g, i, j)
	local ux, uy = g.ux, g.uy
	local ax, ay = chainX[i] * ux, chainY[i] * uy
	local dx, dy = chainX[j] * ux - ax, chainY[j] * uy - ay
	local len = sqrt(dx * dx + dy * dy)
	local tol = min(ux, uy)
	local band = tol * len
	for k = i + 1, j - 1 do
		local px, py = chainX[k] * ux - ax, chainY[k] * uy - ay
		local along = (px * dx + py * dy) / len
		if along < -tol or along > len + tol then return false end
		local cross = px * dy - py * dx
		if cross > band or -cross > band then return false end
	end
	return true
end

local failMap, failG, failAt = nil, nil, -1e9 -- last goal cell a full search could not reach

local function computePath(g, rec, seed, mapID, sx, sy, gx, gy, fromX, fromY, toX, toY)
	if abs(sx - gx) <= 1 and abs(sy - gy) <= 1 then return nil end
	if not walkedNear(rec, seed, sx, sy) or not walkedNear(rec, seed, gx, gy) then return nil end
	local gid = gx * 4096 + gy
	local now = GetTime()
	if failMap == mapID and failG == gid and now - failAt < FAIL_SECONDS then return nil end
	local found = astar(g, rec, seed, sx, sy, gx, gy)
	if not found then
		-- an exhausted or capped search is the expensive case; do not repeat it for every step the player takes
		failMap, failG, failAt = mapID, gid, now
		return nil
	end
	-- cell chain, goal -> start, then reversed
	local n = 0
	local id = gx * 4096 + gy
	while id do
		n = n + 1
		local cx = floor(id / 4096)
		chainX[n], chainY[n] = cx, id - cx * 4096
		id = cameFrom[id]
	end
	for i = 1, floor(n / 2) do
		local j = n + 1 - i
		chainX[i], chainX[j] = chainX[j], chainX[i]
		chainY[i], chainY[j] = chainY[j], chainY[i]
	end
	-- string pull: from each kept node, keep extending while the chain stays within a cell of the segment
	local nodes = { { x = fromX, y = fromY } }
	local i = 1
	while i < n do
		local j = i + 1
		while j < n and collinear(g, i, j + 1) do j = j + 1 end
		if j == n then
			nodes[#nodes + 1] = { x = toX, y = toY }
		else
			nodes[#nodes + 1] = { x = (chainX[j] + 0.5) / g.nx, y = (chainY[j] + 0.5) / g.ny }
		end
		i = j
	end
	-- yards left along the path from each node
	local last = nodes[#nodes]
	last.rest = 0
	for k = #nodes - 1, 1, -1 do
		local a, b = nodes[k], nodes[k + 1]
		local dx, dy = (b.x - a.x) * g.w, (b.y - a.y) * g.h
		a.rest = b.rest + sqrt(dx * dx + dy * dy)
	end
	return nodes
end

local cacheHas, cacheMap, cacheS, cacheG, cacheAt, cacheResult = false

--- Walkable route from (fromX, fromY) to (toX, toY) on a map (0..1 coordinates): a string-pulled list of
--- { x, y, rest } nodes (rest = yards left to the goal from that node), the first node being the start
--- and the last the goal. nil when nothing is known there; the caller then keeps the straight line.
function Guide:TrailPath(mapID, fromX, fromY, toX, toY)
	if not (mapID and fromX and fromY and toX and toY) then return nil end
	local rec = store()[mapID]
	local seed = seedFor(mapID)
	if not rec and not seed then return nil end
	local g = gridFor(mapID)
	local sx, sy = cellOf(g, fromX, fromY)
	local gx, gy = cellOf(g, toX, toY)
	local sid, gid = sx * 4096 + sy, gx * 4096 + gy
	local now = GetTime()
	if cacheHas and cacheMap == mapID and cacheS == sid and cacheG == gid and now - cacheAt < CACHE_SECONDS then
		return cacheResult
	end
	local result = computePath(g, rec, seed, mapID, sx, sy, gx, gy, fromX, fromY, toX, toY)
	cacheHas, cacheMap, cacheS, cacheG, cacheAt, cacheResult = true, mapID, sid, gid, now, result
	return result
end

-- Arrow: next node ------------------------------------------------------------------------------------------------

local pathNodes, pathIndex, pathAt, pathMap, pathTX, pathTY, pathCx, pathCy = nil, 2, -1e9

local function following()
	local t = Guide.db and Guide.db.profile.trails
	return not t or t.follow ~= false
end

local function dropPath()
	pathNodes, pathMap = nil, nil
end

--- The path node the arrow should point at instead of the target, plus the yards left along the
--- path from the player. nil = point straight at the target. Called every arrow update; the path is
--- recomputed at most once a second and only when the player changed cell or the target changed.
function Guide:TrailNext(target, dist)
	if not enabled or not target or not dist or dist <= NEAR_YARDS or not following() then return nil end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or mapID ~= target.mapID then dropPath() return nil end
	local now = GetTime()
	local changed = pathMap ~= mapID or pathTX ~= target.x or pathTY ~= target.y
	if changed or now - pathAt >= PATH_INTERVAL then
		pathAt = now
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		local x, y
		if pos then x, y = pos:GetXY() end
		if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then x = nil end
		if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then
			-- no usable position: remember the target so the next look waits for the interval
			pathNodes, pathMap, pathTX, pathTY, pathCx = nil, mapID, target.x, target.y, nil
			return nil
		end
		local cx, cy = cellOf(gridFor(mapID), x, y)
		if changed or cx ~= pathCx or cy ~= pathCy then
			pathMap, pathTX, pathTY, pathCx, pathCy = mapID, target.x, target.y, cx, cy
			pathNodes = self:TrailPath(mapID, x, y, target.x, target.y)
			pathIndex = 2
			if pathNodes then
				for k = 2, #pathNodes do
					local nd = pathNodes[k]
					if not nd.continent then nd.continent, nd.wx, nd.wy = self:WorldPos(mapID, nd.x, nd.y) end
				end
			end
		end
	end
	if not pathNodes then return nil end
	local n = #pathNodes
	local d
	while pathIndex < n do
		local nd = pathNodes[pathIndex]
		d = nd.continent and self:DistanceToWorld(nd.continent, nd.wx, nd.wy)
		if not d then pathNodes = nil return nil end -- unknown world position: straight line until the next look
		if d >= LOOKAHEAD_YARDS then break end
		pathIndex = pathIndex + 1
	end
	if pathIndex >= n then return nil end -- the last node is the target itself: straight line from here
	local nd = pathNodes[pathIndex]
	return nd, d + nd.rest
end

-- Guide steps with explicit waypoints --------------------------------------------------------------------------------

local wpStep, wpIndex

local function pointXY(p)
	if type(p) ~= "table" then return nil end
	local x, y = p.x or p[1], p.y or p[2]
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

--- Called by the arrow when it picks a target: a guide step with `path` points is walked point by
--- point (each within WAYPOINT_YARDS counts as reached) before the step's own goto.
function Guide:TrailTargetOverride(t)
	if not t or t.kind ~= "guide" or t.waypoint then return t end
	local step = self:CurrentStep()
	local path = step and step.path
	if type(path) ~= "table" or #path == 0 then wpStep = nil return t end
	if wpStep ~= step then
		wpStep, wpIndex = step, 1
		-- resuming mid-route (reload, manual step change): continue from a point the player stands near
		local bestD
		for i, p in ipairs(path) do
			local px, py = pointXY(p)
			local d = px and self:VectorTo(t.mapID, px / 100, py / 100)
			if d and d <= WAYPOINT_RESUME_YARDS and (not bestD or d < bestD) then wpIndex, bestD = i, d end
		end
	end
	while wpIndex <= #path do
		local px, py = pointXY(path[wpIndex])
		local d = px and self:VectorTo(t.mapID, px / 100, py / 100)
		if not d or d > WAYPOINT_YARDS then break end
		wpIndex = wpIndex + 1
	end
	local px, py = pointXY(path[wpIndex])
	if not px then return t end
	return { kind = "guide", mapID = t.mapID, x = px / 100, y = py / 100, title = t.title, radius = WAYPOINT_YARDS,
		subtitle = ("%s · waypoint %d/%d"):format(t.subtitle or "Guide step", wpIndex, #path), waypoint = wpIndex, final = t }
end

--- Called by the arrow when it arrives at a waypoint target: move on to the next point.
function Guide:TrailWaypointReached(target)
	if wpStep and target and target.waypoint and target.waypoint >= (wpIndex or 1) then wpIndex = target.waypoint + 1 end
	self:RetargetArrow()
end

-- Stats / slash -----------------------------------------------------------------------------------------------------

local function recordBytes(rec)
	local bytes = 40
	for _, row in pairs(rec.rows) do bytes = bytes + #row + 14 end
	return bytes
end

--- Numbers for the status line and tests.
function Guide:TrailStats()
	local t = store()
	local out = { maps = 0, cells = 0, links = 0, bytes = 0, recording = recording(), follow = following(), enabled = enabled, lastExpansions = lastExpansions }
	for mapID, rec in pairs(t) do
		out.maps = out.maps + 1
		out.cells = out.cells + (rec.n or 0)
		out.links = out.links + (rec.l or 0)
		out.bytes = out.bytes + recordBytes(rec)
		if not out.largest or rec.n > out.largest then out.largest, out.largestMap = rec.n, mapID end
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	out.mapID = mapID
	local rec = mapID and t[mapID]
	out.mapCells, out.mapLinks, out.mapBytes = rec and rec.n or 0, rec and rec.l or 0, rec and recordBytes(rec) or 0
	local seed = mapID and seedFor(mapID)
	out.seedCells, out.seedLinks = seed and seed.n or 0, seed and seed.l or 0
	return out
end

local function setFlag(key, value)
	local p = Guide.db.profile
	p.trails = p.trails or {}
	p.trails[key] = value
end

local function handleTrails(rest)
	local verb, a = strsplit(" ", strtrim(rest or ""), 2)
	verb = (verb or ""):lower()
	if verb == "" or verb == "status" then
		local s = Guide:TrailStats()
		Lodestar:Say("Trails: %d maps, %d cells, %d links (~%d KB). Recording %s, arrow routing %s.", s.maps, s.cells, s.links,
			floor(s.bytes / 1024 + 0.5), s.recording and "on" or "off", s.follow and "on" or "off")
		if s.mapID then
			Lodestar:Say("  %s: %d cells, %d links learned (~%d KB), %d cells / %d links seeded.", Guide:MapName(s.mapID), s.mapCells, s.mapLinks,
				floor(s.mapBytes / 1024 + 0.5), s.seedCells, s.seedLinks)
		end
	elseif verb == "on" or verb == "off" then
		setFlag("record", verb == "on")
		lastMap = nil
		Lodestar:Say("Trail recording %s.", verb)
	elseif verb == "follow" then
		local v = (a or ""):lower()
		if v == "on" or v == "off" then setFlag("follow", v == "on") else setFlag("follow", not following()) end
		dropPath()
		Lodestar:Say("Arrow routing along trails %s.", following() and "on" or "off")
	elseif verb == "wipe" then
		if a == "confirm" then
			wipe(store())
			wipe(grids)
			wipe(seeds)
			dropPath()
			lastMap = nil
			cacheHas, failMap = false, nil
			Lodestar:Say("Trails wiped.")
		else
			Lodestar:Say("This deletes every walked trail on this account (seeded roads stay). Type /lode trails wipe confirm to do it.")
		end
	else
		Lodestar:Say("Usage: /lode trails [status | on | off | follow [on|off] | wipe confirm]")
	end
end

-- Options (merged into the Guide settings page; Guide.lua holds the defaults) ------------------------------------------

if type(Guide.options) == "table" then
	Guide.options.trailsHeader = { type = "header", order = 18, name = "Trails" }
	Guide.options.trailsRecord = {
		type = "toggle", order = 19, name = "Learn walkable ground",
		desc = "Remembers where you walk (about 2 bytes per 20 yd cell, account-wide) so the arrow can route around cliffs and water.",
		get = function() return recording() end,
		set = function(_, v) setFlag("record", v) lastMap = nil end,
	}
	Guide.options.trailsFollow = {
		type = "toggle", order = 19.5, name = "Route the arrow along known trails",
		desc = "Point at the next bend of a known walkable path instead of straight at the target.",
		get = function() return following() end,
		set = function(_, v) setFlag("follow", v) dropPath() end,
	}
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------

function Guide:EnableTrails()
	store()
	enabled = true
	lastMap = nil
	if not ticker then ticker = self:ScheduleRepeatingTimer(tick, 1) end
	if not self.trailsSlash then
		self.trailsSlash = true
		Lodestar:RegisterSlashVerb("trails", handleTrails, "learned walkable ground: status, on/off, follow, wipe")
	end
end

function Guide:DisableTrails()
	if ticker then self:CancelTimer(ticker) ticker = nil end
	enabled = false
	lastMap = nil
	dropPath()
	wpStep = nil
end

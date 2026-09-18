#!/usr/bin/env python3
"""Turn road polylines into a Lodestar trail seed (Lodestar_Guide/Data/Trails_Seed.lua).

Input: text files with one polyline per line,  `<zone name>|x,y;x,y;...`  in percent map coordinates
(see tools/trails/roads_horde.txt). Output: a Lua file that fills Guide.TrailSeed[zoneName] with the
same cell/link structure Trails.lua records at runtime:

    { cell = 0.004, n = <walked cells>, l = <links>, rows = { [cy] = "<x0 as 3 hex digits><2 hex digits per cell>" } }

Each cell byte is an 8-neighbour link mask (bit i set = linked to neighbour i, see NEIGHBOURS), ".."
marks a cell inside the row's span that is not walked. The grid is CELL (0.4 % of the map by default);
the runtime resamples it onto the map's own ~20 yd grid, so the seed does not need to know map sizes.

Usage:
    python3 tools/trails/seed_roads.py [-o Lodestar_Guide/Data/Trails_Seed.lua] [--cell 0.4] roads.txt [more.txt ...]
"""
import argparse
import os
import sys

# Neighbour order shared with Trails.lua: i -> (dx, dy). Bit i of a cell's mask means "linked to neighbour i".
NEIGHBOURS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
NEIGHBOUR_INDEX = {d: i for i, d in enumerate(NEIGHBOURS)}
MAX_AXIS = 4095  # cell ids are packed as cx * 4096 + cy


class Grid:
    def __init__(self, cells_per_axis):
        self.n = cells_per_axis
        self.mask = {}  # (cx, cy) -> mask
        self.links = 0

    def cell_of(self, x, y):
        """Percent coordinates -> cell (clamped to the grid)."""
        cx = int(x / 100.0 * self.n)
        cy = int(y / 100.0 * self.n)
        return max(0, min(self.n - 1, cx)), max(0, min(self.n - 1, cy))

    def mark(self, cx, cy):
        self.mask.setdefault((cx, cy), 0)

    def link(self, ax, ay, bx, by):
        i = NEIGHBOUR_INDEX.get((bx - ax, by - ay))
        if i is None:
            raise ValueError("link between non-adjacent cells (%d,%d)-(%d,%d)" % (ax, ay, bx, by))
        self.mark(ax, ay)
        self.mark(bx, by)
        bit_a, bit_b = 1 << i, 1 << ((i + 4) % 8)
        if not self.mask[(ax, ay)] & bit_a:
            self.mask[(ax, ay)] |= bit_a
            self.links += 1
        self.mask[(bx, by)] |= bit_b

    def walk(self, ax, ay, bx, by):
        """Bresenham (8-connected) from cell a to cell b, linking consecutive cells. Same walker as Trails.lua."""
        dx, dy = abs(bx - ax), abs(by - ay)
        sx, sy = (1 if ax < bx else -1), (1 if ay < by else -1)
        err = dx - dy
        x, y = ax, ay
        self.mark(x, y)
        while x != bx or y != by:
            e2 = 2 * err
            nx, ny = x, y
            if e2 > -dy:
                err -= dy
                nx = x + sx
            if e2 < dx:
                err += dx
                ny = y + sy
            self.link(x, y, nx, ny)
            x, y = nx, ny

    def rows(self):
        """{cy: encoded row string} in the runtime format."""
        by_row = {}
        for (cx, cy), mask in self.mask.items():
            by_row.setdefault(cy, {})[cx] = mask
        out = {}
        for cy, cells in by_row.items():
            x0, x1 = min(cells), max(cells)
            parts = ["%03x" % x0]
            for cx in range(x0, x1 + 1):
                m = cells.get(cx)
                parts.append(".." if m is None else "%02x" % m)
            out[cy] = "".join(parts)
        return out


def parse_roads(path):
    """Yield (zone, [(x, y), ...]) per polyline line."""
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "|" not in line:
                raise SystemExit("%s:%d: expected 'zone|x,y;x,y;...'" % (path, lineno))
            zone, rest = line.split("|", 1)
            zone = zone.strip()
            points = []
            for chunk in rest.split(";"):
                chunk = chunk.strip()
                if not chunk:
                    continue
                try:
                    x, y = (float(v) for v in chunk.split(","))
                except ValueError:
                    raise SystemExit("%s:%d: bad point %r" % (path, lineno, chunk))
                if not (0 <= x <= 100 and 0 <= y <= 100):
                    raise SystemExit("%s:%d: point %r outside 0-100" % (path, lineno, chunk))
                points.append((x, y))
            if len(points) < 2:
                raise SystemExit("%s:%d: a polyline needs at least two points" % (path, lineno))
            yield zone, points


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="road polyline text files")
    ap.add_argument("-o", "--output", default=os.path.join("Lodestar_Guide", "Data", "Trails_Seed.lua"))
    ap.add_argument("--cell", type=float, default=0.4, help="grid cell size in percent of the map (default 0.4)")
    args = ap.parse_args(argv)

    cells_per_axis = int(round(100.0 / args.cell))
    if cells_per_axis < 8 or cells_per_axis > MAX_AXIS:
        raise SystemExit("--cell must give between 8 and %d cells per axis" % MAX_AXIS)
    cell_fraction = 1.0 / cells_per_axis

    grids = {}
    polylines = 0
    for path in args.inputs:
        for zone, points in parse_roads(path):
            grid = grids.setdefault(zone, Grid(cells_per_axis))
            polylines += 1
            prev = grid.cell_of(*points[0])
            grid.mark(*prev)
            for pt in points[1:]:
                cur = grid.cell_of(*pt)
                grid.walk(prev[0], prev[1], cur[0], cur[1])
                prev = cur

    out = []
    out.append("-- Lodestar_Guide: seeded road trails. GENERATED FILE - do not edit by hand.")
    out.append("--   source: " + ", ".join(args.inputs))
    out.append("--   regenerate: python3 tools/trails/seed_roads.py " + " ".join(args.inputs) + " -o " + args.output)
    out.append("--")
    out.append("-- Same structure Trails.lua keeps in LodestarScanDB.trails, keyed by zone name (resolved to a uiMapID")
    out.append("-- through C_Map.GetMapInfo at runtime) on a fixed %g %% grid: rows[cy] = \"<x0 hex3><2 hex per cell>\"," % args.cell)
    out.append("-- each cell byte an 8-neighbour link mask (bit i = linked to neighbour i: E, SE, S, SW, W, NW, N, NE),")
    out.append("-- \"..\" = not walked. Read-only: the runtime resamples it onto the map's grid and never writes it back.")
    out.append("-- The roads are APPROXIMATE (see the source file); walked ground recorded in game takes precedence.")
    out.append("local Guide = _G.Lodestar:GetModule(\"Guide\")")
    out.append("local S = Guide.TrailSeed or {}")
    out.append("Guide.TrailSeed = S")
    total_cells = total_links = 0
    for zone in sorted(grids):
        grid = grids[zone]
        rows = grid.rows()
        total_cells += len(grid.mask)
        total_links += grid.links
        out.append("S[%s] = { cell = %s, n = %d, l = %d, rows = {" % (lua_string(zone), repr(cell_fraction), len(grid.mask), grid.links))
        for cy in sorted(rows):
            out.append("\t[%d] = %s," % (cy, lua_string(rows[cy])))
        out.append("} }")
    text = "\n".join(out) + "\n"
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("%s: %d zones, %d polylines, %d cells, %d links, %d bytes" % (args.output, len(grids), polylines, total_cells, total_links, len(text)))


if __name__ == "__main__":
    main(sys.argv[1:])

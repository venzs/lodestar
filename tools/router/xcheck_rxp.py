#!/usr/bin/env python3
"""Cross-check our NPC positions against RestedXP's free guides, if that addon is installed.

    python3 tools/router/xcheck_rxp.py [--worst N]

RXP's shipped Guides/Forever/*.lua (CC BY-NC-SA, read only, nothing is copied) write `.goto` as
world yards on a uiMapID, in HereBeDragons order -- (y, x) relative to the client's TaxiNodes and
UiMapAssignment axes -- and name the NPC on the next `.target` line. That is an independent record
of where a few hundred quest givers stand, gathered by a different team with a different method,
which makes it a check on two things at once: the harvest's own positions, and the map-percent to
world-yard conversion in world.MapFrame (580 NPCs to a median of 2 yards on 2026-09-20; the other
axis order puts them 7 km away).

A large residual for one NPC is a lead, not a verdict. It is either a pfQuest position that is
stale, an NPC that patrols or has several spawns (we keep one), or RXP being wrong. The point is to
have the list.

Exits 0 and says so if the addon is not installed; this is a tool, not a gate.
"""
from __future__ import annotations

import argparse
import glob
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, ROOT)

from tools.router.map_frames import AREA_TO_UIMAP, FRAMES        # noqa: E402
from tools.router.model import MapPos                            # noqa: E402
from tools.router.world import MapFrame                          # noqa: E402

CANDIDATES = [
    r"C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/RXPGuides/Guides/Forever",
    os.environ.get("RXP_GUIDES", ""),
]


def rxp_positions() -> dict[str, tuple[int, float, float]]:
    """NPC name -> (uiMapID, world x, world y) in the client's axis order."""
    folder = next((c for c in CANDIDATES if c and os.path.isdir(c)), None)
    if not folder:
        return {}
    out: dict[str, tuple[int, float, float]] = {}
    for f in sorted(glob.glob(os.path.join(folder, "*.lua"))):
        text = open(f, encoding="utf-8", errors="replace").read()
        for step in re.split(r"\nstep", text):
            g = re.search(r"\.goto (\d+)/\d+,(-?[\d.]+),(-?[\d.]+)", step)
            t = re.search(r"\.target ([^\n|]+)", step)
            if g and t:
                # RXP order is (y, x); store as the client's (x, y)
                out.setdefault(t.group(1).strip(), (int(g.group(1)), float(g.group(3)), float(g.group(2))))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--worst", type=int, default=15, help="how many of the largest residuals to list")
    args = ap.parse_args(argv)
    rxp = rxp_positions()
    if not rxp:
        print("RestedXP Forever guides not found; nothing to compare against")
        return 0
    from tools.router.vanilla_catalog import load_vanilla
    data = load_vanilla()
    byname = {}
    for e in data["npcs"].values():
        if e.get("n"):
            byname.setdefault(e["n"], e)
    rows = []
    for name, (ui, wx, wy) in rxp.items():
        e = byname.get(name)
        if not e or ui not in FRAMES:
            continue
        best = None
        for c in e.get("c") or []:
            u = c[0] if c[0] in FRAMES else AREA_TO_UIMAP.get(c[0])
            if u != ui:
                continue
            n, cont, x0, y0, x1, y1 = FRAMES[u]
            px, py = MapFrame(u, x0, y0, x1, y1, cont).to_world(MapPos(u, c[1], c[2]))
            d = math.dist((px, py), (wx, wy))
            if best is None or d < best[0]:
                best = (d, n, c[1], c[2])
        if best:
            rows.append((best[0], name, best[1], best[2], best[3]))
    if not rows:
        print("no NPC appears in both sources")
        return 0
    # per map first: a whole zone drifting together is a frame or map-revision problem, which no
    # amount of per-NPC harvesting fixes, and it hides inside a healthy global median
    import collections, statistics
    per = collections.defaultdict(list)
    for d, name, zone, x, y in rows:
        per[zone].append(d)
    wide = [(statistics.median(v), z, len(v)) for z, v in per.items() if len(v) >= 5 and statistics.median(v) > 25]
    if wide:
        print("zone-wide offsets (median > 25 yd across 5+ NPCs) -- a frame problem, not a harvest one:")
        for med, z, n in sorted(wide, reverse=True):
            print(f"  {med:6.0f} yd median over {n:3d} NPCs  {z}")
    rows.sort()
    ds = [r[0] for r in rows]
    print(f"{len(rows)} NPCs in both sources: median {ds[len(ds)//2]:.0f} yd, p90 {ds[9*len(ds)//10]:.0f}, "
          f"worst {ds[-1]:.0f}; {sum(1 for d in ds if d > 200)} more than 200 yd apart")
    print(f"largest residuals (ours is the pfQuest percent on its map):")
    for d, name, zone, x, y in rows[-args.worst:][::-1]:
        print(f"  {d:6.0f} yd  {name:28s} ours {zone} {x:.1f},{y:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

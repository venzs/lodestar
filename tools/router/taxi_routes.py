"""Turn the client's flight table into the two things a catalog needs: where the nodes are, and how
long it takes to fly between any two of them.

taxi.py is the raw table (world-yard node positions and per-edge flown lengths). Here it becomes:

  nodes(faction)   node id -> (short name, MapPos, world x, world y), only the ones that faction can
                   select, positioned by whichever map_frames rectangle contains them
  route_yards(...) every reachable ordered pair -> yards flown, shortest path over the edge graph

Shortest path matters because most journeys are not one hop. The client routes a flight through
intermediate nodes and charges for the whole chain, so Orgrimmar to Gadgetzan is the sum of several
TaxiPath legs, and a straight line between the endpoints is not close to it.

Continents are not bridged: a boat or zeppelin is not a taxi node the player can pick, so there is
no edge across and route_yards simply has no entry for those pairs.
"""
from __future__ import annotations

import heapq
import math
from typing import Optional

from .map_frames import FRAMES
from .model import MapPos
from .world import MapFrame

# Placeholder until a harvested flight (Harvest.lua's flyStart -> arrival delta) calibrates it.
# world.TAXI_SPEED is the same number; this module works in yards and leaves the division to the
# caller so that a recalibration touches one constant.


def short_name(full: str) -> str:
    """'Orgrimmar, Durotar' -> 'Orgrimmar'. The zone half is there to disambiguate on the flight
    map, where both factions' nodes are listed; within one faction the first half is unique."""
    return full.split(",")[0].strip()


def frame_of(cont: int, x: float, y: float, label: str = "") -> Optional[tuple[int, float, float]]:
    """Which map to express this world point on -> (uiMapID, map x%, map y%).

    Any containing rectangle gives the same distances, because to_world inverts exactly; the choice
    only decides the zone name a `.goto` prints. Smallest-containing alone gets that wrong, because
    a map rectangle is the bounding box of an irregular zone and boxes overlap: Ratchet sits in the
    Barrens but inside Durotar's box, and Durotar's box is smaller.

    So a node's own name is used first. They read "settlement, zone" -- "Ratchet, The Barrens",
    "Orgrimmar, Durotar" -- and either half may name a map, which picks the Barrens for Ratchet and
    the Orgrimmar city map (smaller, and also containing) for Orgrimmar. A point in no rectangle at
    all returns None rather than being forced onto the continent map."""
    named = set()
    for part in (p.strip() for p in label.split(",")):
        if not part:
            continue
        for ui, (n, _c, *_r) in FRAMES.items():
            if n == part or n.startswith(part + " ") or part.startswith(n + " "):
                named.add(ui)
    best = None
    for ui, (_n, c, x0, y0, x1, y1) in FRAMES.items():
        if c != cont:
            continue
        lo_x, hi_x = min(x0, x1), max(x0, x1)
        lo_y, hi_y = min(y0, y1), max(y0, y1)
        if not (lo_x <= x <= hi_x and lo_y <= y <= hi_y):
            continue
        # a rectangle the node names beats any unnamed one, then smaller beats bigger
        rank = (0 if ui in named else 1, (hi_x - lo_x) * (hi_y - lo_y))
        if best is None or rank < best[0]:
            mx, my = MapFrame(ui, x0, y0, x1, y1, c).to_map(x, y)
            best = (rank, ui, mx, my)
    return (best[1], best[2], best[3]) if best else None


def continents() -> dict[int, int]:
    """taxi node id -> continent, for callers matching a world position to a node."""
    from .taxi import NODES
    return {i: v[1] for i, v in NODES.items()}


def nodes(faction: str) -> dict[int, tuple[str, MapPos, float, float]]:
    from .taxi import NODES
    out = {}
    for i, (name, cont, x, y, fac) in NODES.items():
        if fac not in (faction, "Both"):
            continue
        fr = frame_of(cont, x, y, name)
        if fr is None:
            continue
        out[i] = (short_name(name), MapPos(fr[0], fr[1], fr[2]), x, y)
    return out


def route_yards(faction: str) -> dict[tuple[int, int], float]:
    """All-pairs shortest flown distance over the edges both endpoints' faction can use."""
    from .taxi import EDGES
    keep = set(nodes(faction))
    adj: dict[int, list[tuple[int, float]]] = {i: [] for i in keep}
    for (a, b), yards in EDGES.items():
        if a in keep and b in keep:
            adj[a].append((b, yards))
    out: dict[tuple[int, int], float] = {}
    for src in keep:
        dist = {src: 0.0}
        pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist.get(u, math.inf):
                continue
            for v, w in adj[u]:
                nd = d + w
                if nd < dist.get(v, math.inf):
                    dist[v] = nd
                    heapq.heappush(pq, (nd, v))
        for dst, d in dist.items():
            if dst != src:
                out[(src, dst)] = d
    return out

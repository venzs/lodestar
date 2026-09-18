"""World geometry: uiMap percent -> yards, distances, and travel edge costs.

Recorder.lua stores (uiMapID, x%, y%); in-game, C_Map.GetWorldPosFromMapPos does the conversion.
Offline we need each uiMap's world-space rectangle. Two ways to get it:

  1. wago.tools  UiMapAssignment  (Region0..5 columns hold the world bounds per uiMapID) for build 1.60.1
  2. in-game dump: for the current map, log C_Map.GetWorldPosFromMapPos(map, {0,0}) and (map, {1,1})
     once per zone (a 6-line addition to /lode record: "record calib"). This is the ground truth.

Until the table is loaded, a per-map fallback of (width, height) in yards is used; Classic zone maps are
roughly 2-5k yards across, and the sample below is only for the synthetic example.

Travel:
  run    euclidean yards / RUN_SPEED * detour(cell_a, cell_b)     detour default 1.25, learned from laps
  fly    flight_seconds[(a, b)] from recordings (flyStart -> fly delta) or path-length / TAXI_SPEED
  hearth HS_CAST + walk from the inn; only if the cooldown is ready (sim time >= hs_ready_at)
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

from .model import MapPos

RUN_SPEED = 7.0            # yd/s, base run speed (Warcraft Wiki "Speed")
TAXI_SPEED = 32.0          # yd/s along the taxi path; only used when no recorded flight time exists
HS_CAST = 10.0             # seconds
HS_COOLDOWN = 60 * 60.0    # Classic-era hearthstone cooldown; retune from HEARTHSTONE cooldown probe
DEFAULT_DETOUR = 1.25      # straight-line -> real path multiplier before any lap data
CELL_YARDS = 150.0         # detour factors are learned per (cell, cell) pair


@dataclass
class MapFrame:
    map: int
    x0: float   # world x at map (0%, 0%)
    y0: float
    x1: float   # world x at (100%, 100%)
    y1: float
    continent: int = 0

    def to_world(self, p: MapPos) -> tuple[float, float]:
        return (self.x0 + (self.x1 - self.x0) * p.x / 100.0, self.y0 + (self.y1 - self.y0) * p.y / 100.0)


@dataclass
class World:
    frames: dict[int, MapFrame] = field(default_factory=dict)
    detour: dict[tuple[tuple[int, int], tuple[int, int]], tuple[float, int]] = field(default_factory=dict)
    # (cellA, cellB) -> (mean factor, samples); symmetric

    def world(self, p: MapPos) -> tuple[int, float, float]:
        f = self.frames.get(p.map)
        if f is None:
            raise KeyError(f"no MapFrame for uiMapID {p.map}; load UiMapAssignment or a calib dump")
        x, y = f.to_world(p)
        return f.continent, x, y

    def yards(self, a: MapPos, b: MapPos) -> float:
        ca, ax, ay = self.world(a)
        cb, bx, by = self.world(b)
        if ca != cb:
            return math.inf
        return math.hypot(ax - bx, ay - by)

    def cell(self, p: MapPos) -> tuple[int, int]:
        _, x, y = self.world(p)
        return (int(x // CELL_YARDS), int(y // CELL_YARDS))

    def detour_factor(self, a: MapPos, b: MapPos) -> float:
        key = tuple(sorted((self.cell(a), self.cell(b))))
        rec = self.detour.get(key)  # type: ignore[arg-type]
        return rec[0] if rec else DEFAULT_DETOUR

    def run_seconds(self, a: MapPos, b: MapPos, speed: float = RUN_SPEED) -> float:
        d = self.yards(a, b)
        if d == math.inf:
            return math.inf
        return d * self.detour_factor(a, b) / speed

    def observe_leg(self, a: MapPos, b: MapPos, seconds: float, prior_weight: float = 3.0) -> None:
        """Re-weight a run edge from a recorded lap: Bayesian mean with DEFAULT_DETOUR as the prior."""
        d = self.yards(a, b)
        if d < 30 or d == math.inf or seconds <= 0:
            return
        observed = seconds * RUN_SPEED / d
        observed = max(1.0, min(observed, 4.0))     # clamp: AFK / combat during the leg would otherwise poison it
        key = tuple(sorted((self.cell(a), self.cell(b))))
        mean, n = self.detour.get(key, (DEFAULT_DETOUR, 0))  # type: ignore[arg-type]
        new_mean = (mean * (n + prior_weight) + observed) / (n + prior_weight + 1)
        self.detour[key] = (new_mean, n + 1)  # type: ignore[index]


# --- travel edges used by the planner --------------------------------------------------------------

@dataclass
class TravelOption:
    kind: str                    # run | fly | hearth
    seconds: float
    via: Optional[str] = None    # flight destination name / hearth inn name
    legs: list[MapPos] = field(default_factory=list)  # intermediate positions (flightmaster, inn)


def travel_options(world: World, catalog, state, dest: MapPos) -> list[TravelOption]:
    """Every way to get from state.pos to dest, cheapest first. The planner picks options[0] but
    the alternatives are kept so emit() can explain the choice in a comment."""
    opts = [TravelOption("run", world.run_seconds(state.pos, dest))]

    # hearth: cast, appear at the inn, run from there
    if state.bound_inn and state.hs_ready_at <= state.t:
        inn = catalog.flights.get(state.bound_inn) or None
        inn_pos = state.bound_inn_pos
        if inn_pos is not None:
            secs = HS_CAST + world.run_seconds(inn_pos, dest)
            opts.append(TravelOption("hearth", secs, via=state.bound_inn, legs=[inn_pos]))

    # fly: run to the nearest known flightmaster, fly to the one nearest dest, run on
    known = [f for f in catalog.flights.values() if f.name in state.known_flights]
    if len(known) >= 2:
        for src in known:
            to_src = world.run_seconds(state.pos, src.pos)
            for dst in known:
                if dst.name == src.name:
                    continue
                fs = catalog.flight_seconds.get((src.name, dst.name))
                if fs is None:
                    d = world.yards(src.pos, dst.pos)
                    fs = d / TAXI_SPEED if d != math.inf else None
                if fs is None:
                    continue
                secs = to_src + 5.0 + fs + world.run_seconds(dst.pos, dest)
                opts.append(TravelOption("fly", secs, via=dst.name, legs=[src.pos, dst.pos]))

    opts.sort(key=lambda o: o.seconds)
    return opts

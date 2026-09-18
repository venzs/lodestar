"""Recorded laps -> calibration and warm starts.

The raw recording (Guide.db.char.recording.entries, see Recorder.lua `add`) is richer than the text
export: every entry has a timestamp `t`, the player level, a position, and for quests the NPC id,
quest level, XP reward and a "mobs" summary ("Rattlecage Skeleton x4 (lvl 1-2), ...").
Dump it with tools/router/sv2json.lua from the SavedVariables file, then:

    laps = load_entries("recording.json")
    calibrate(laps, catalog, world, cost_model)     # NPC positions, detours, TTK, drop rates, flight times, quest XP
    incumbent = steps_from_lap(laps, catalog)       # the human route as a Step list -> validate.replay scores it

What each field re-weights:
  position + t on hub-to-hub legs        -> world.detour (per cell pair)     "how long that road really takes"
  complete.mobs + dt since previous entry -> cost_model.t0_base / class_factor "how fast this class kills at level L vs mob M"
  complete (collect) kills vs count      -> objective.drop_rate
  turnin.xp                              -> xp.CFG.quest_xp_scale, and a per-quest correction if the catalog is wrong
  flyStart -> fly dt                     -> catalog.flight_seconds[(from, to)]
  accept/turnin npcID + position         -> catalog.npcs[id].pos (running mean)
  level entries                          -> XP-to-level curve check (needs UnitXPMax; see recommendations)
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Optional

from . import xp as XP
from .cost import CostModel
from .model import Catalog, MapPos, NPC, ObjKind, Step, StepKind
from .world import World

MOB_RE = re.compile(r"(.+?) x(\d+) \(lvl (\d+)(?:-(\d+))?\)")


@dataclass
class LapEntry:
    type: str
    t: float
    level: int
    map: Optional[int] = None
    x: Optional[float] = None
    y: Optional[float] = None
    questID: Optional[int] = None
    objective: Optional[int] = None
    npc: Optional[str] = None
    npcID: Optional[int] = None
    questLevel: Optional[int] = None
    xp: Optional[int] = None
    mobs: Optional[str] = None
    name: Optional[str] = None
    title: Optional[str] = None
    text: Optional[str] = None

    @property
    def pos(self) -> Optional[MapPos]:
        if self.map is None or self.x is None or self.y is None:
            return None
        return MapPos(self.map, self.x, self.y)


def load_entries(path: str) -> list[LapEntry]:
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    entries = raw["entries"] if isinstance(raw, dict) else raw
    fields = LapEntry.__dataclass_fields__
    return [LapEntry(**{k: v for k, v in e.items() if k in fields}) for e in entries]


def parse_mobs(summary: str) -> list[tuple[str, int, int, int]]:
    out = []
    for part in summary.split(", "):
        m = MOB_RE.match(part.strip())
        if m:
            name, n, lo, hi = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4) or m.group(3))
            out.append((name, n, lo, hi))
    return out


# --- calibration -----------------------------------------------------------------------------------------

def calibrate(entries: list[LapEntry], cat: Catalog, world: World, cm: CostModel) -> dict:
    stats: dict = {"npc_updates": 0, "legs": 0, "ttk_samples": [], "quest_xp": [], "flights": 0, "drop": []}
    prev: Optional[LapEntry] = None
    fly_start: Optional[LapEntry] = None
    for e in entries:
        # NPC positions (running mean, weighted by samples)
        if e.type in ("accept", "turnin") and e.npcID and e.pos:
            npc = cat.npcs.get(e.npcID)
            if npc is None:
                cat.npcs[e.npcID] = NPC(e.npcID, e.npc or f"npc {e.npcID}", e.pos, {"questgiver"})
            else:
                n = npc.samples
                npc.pos = MapPos(e.pos.map, (npc.pos.x * n + e.pos.x) / (n + 1), (npc.pos.y * n + e.pos.y) / (n + 1))
                npc.samples = n + 1
            stats["npc_updates"] += 1
        # pure travel legs: hub entry -> hub entry with no kills in between
        if prev and prev.type in ("accept", "turnin", "hs", "train", "vendor") and e.type in ("accept", "turnin", "train", "vendor") \
                and not e.mobs and prev.pos and e.pos:
            dt = e.t - prev.t - 4.0   # minus the dialogue itself
            if 5 < dt < 900:
                world.observe_leg(prev.pos, e.pos, dt)
                stats["legs"] += 1
        # kill time samples
        if e.type in ("complete", "turnin") and e.mobs and prev:
            kills = parse_mobs(e.mobs)
            n = sum(k[1] for k in kills)
            if n > 0:
                dt = e.t - prev.t
                mob = max(k[3] for k in kills)
                stats["ttk_samples"].append((e.level, mob, dt / n))
        # drop rates for collect objectives
        if e.type == "complete" and e.mobs and e.questID in cat.quests:
            q = cat.quests[e.questID]
            o = next((o for o in q.objectives if o.index == (e.objective or 1)), None)
            if o and o.kind == ObjKind.COLLECT:
                kills = sum(k[1] for k in parse_mobs(e.mobs))
                if kills:
                    o.drop_rate = min(1.0, o.count / kills)
                    stats["drop"].append((q.id, o.index, o.drop_rate))
        # quest XP check
        if e.type == "turnin" and e.xp and e.questID in cat.quests:
            pred = XP.quest_xp(e.level, cat.quests[e.questID])
            stats["quest_xp"].append((e.questID, e.level, e.xp, pred))
        # flights
        if e.type == "flyStart":
            fly_start = e
        elif e.type == "fly" and fly_start and e.name:
            src = min(cat.flights.values(), key=lambda f: world.yards(f.pos, fly_start.pos) if fly_start.pos else 1e9, default=None)
            if src:
                cat.flight_seconds[(src.name, e.name)] = e.t - fly_start.t
                stats["flights"] += 1
            fly_start = None
        prev = e
    fit_kill_time(stats["ttk_samples"], cm)
    fit_quest_xp(stats["quest_xp"])
    return stats


def fit_kill_time(samples: list[tuple[int, int, float]], cm: CostModel) -> None:
    """Least-squares fit of the class factor given the model's delta shape (t0 and slopes stay as priors)."""
    if len(samples) < 5:
        return
    num, den = 0.0, 0.0
    for lvl, mob, secs in samples:
        pred = cm.seconds_per_kill(lvl, mob) / cm.class_factor
        num += pred * secs
        den += pred * pred
    if den > 0:
        cm.class_factor = max(0.4, min(2.5, num / den))


def fit_quest_xp(samples: list[tuple[int, int, int, int]]) -> None:
    good = [(a, p) for _, _, a, p in samples if p > 0]
    if len(good) < 3:
        return
    ratio = sum(a for a, _ in good) / sum(p for _, p in good)
    if 0.5 < ratio < 2.0:
        XP.CFG.quest_xp_scale = ratio


# --- the human lap as a plan --------------------------------------------------------------------------------

def steps_from_lap(entries: list[LapEntry], cat: Catalog, hub_yards: float = 20.0, hub_seconds: float = 180.0,
                   world: Optional[World] = None) -> list[Step]:
    """Group a recording into steps the same way Recorder.BuildRecordingText does, so validate.replay can
    score the human route under the same cost model as the planner's route (and it is the incumbent for
    local search)."""
    steps: list[Step] = []
    i = 0
    while i < len(entries):
        e = entries[i]
        if e.type in ("accept", "turnin"):
            group = [e]
            j = i + 1
            while j < len(entries):
                n = entries[j]
                close = (world is None) or (e.pos and n.pos and world.yards(e.pos, n.pos) <= hub_yards)
                if n.type in ("accept", "turnin") and n.t - e.t <= hub_seconds and close:
                    group.append(n); j += 1
                else:
                    break
            s = Step(kind=StepKind.HUB, goto=e.pos)
            s.turnins = [g.questID for g in group if g.type == "turnin" and g.questID in cat.quests]
            s.accepts = [g.questID for g in group if g.type == "accept" and g.questID in cat.quests]
            steps.append(s)
            i = j
        elif e.type == "complete" and e.questID in cat.quests:
            steps.append(Step(kind=StepKind.OBJECTIVE, goto=e.pos, completes=[(e.questID, e.objective or 1)]))
            i += 1
        elif e.type == "hs":
            steps.append(Step(kind=StepKind.HEARTH_BIND, goto=e.pos, name=e.name)); i += 1
        elif e.type == "fly":
            steps.append(Step(kind=StepKind.FLY, goto=e.pos, name=e.name)); i += 1
        else:
            i += 1
    return steps

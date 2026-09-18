"""Player-state simulation. The planner only ever mutates state through these functions so that
every candidate bundle is scored by the same rules that produce the final timeline."""
from __future__ import annotations

import copy
from dataclasses import dataclass, field
from typing import Optional

from . import xp as XP
from .cost import CostModel, difficulty
from .model import Catalog, MapPos, Objective, ObjKind, Quest
from .world import HS_COOLDOWN, World

QUEST_LOG_CAP = 20   # Classic-era; Forever may differ (C_QuestLog.GetMaxNumQuestsCanAccept in-game)


@dataclass
class PlayerState:
    t: float                       # simulated seconds since guide start
    pos: MapPos
    level: int
    xp_into_level: int = 0
    total_xp: int = 0
    player_class: str = ""
    race: str = ""
    accepted: set[int] = field(default_factory=set)          # in the log
    done_objectives: set[tuple[int, int]] = field(default_factory=set)
    turned_in: set[int] = field(default_factory=set)
    bound_inn: Optional[str] = None
    bound_inn_pos: Optional[MapPos] = None
    hs_ready_at: float = 0.0
    known_flights: set[str] = field(default_factory=set)
    kills: int = 0

    def clone(self) -> "PlayerState":
        return copy.deepcopy(self)

    def log_size(self) -> int:
        return len(self.accepted)

    # --- XP -----------------------------------------------------------------------------------

    def gain_xp(self, amount: int, cfg: XP.XPConfig = XP.CFG) -> int:
        """Add XP; returns the number of levels gained."""
        if amount <= 0 or self.level >= cfg.max_level:
            return 0
        self.total_xp += amount
        self.xp_into_level += amount
        gained = 0
        while self.level < cfg.max_level and self.xp_into_level >= XP.xp_to_level(self.level, cfg):
            self.xp_into_level -= XP.xp_to_level(self.level, cfg)
            self.level += 1
            gained += 1
        return gained

    # --- quest log ----------------------------------------------------------------------------

    def can_accept(self, q: Quest) -> bool:
        if q.id in self.accepted or (q.id in self.turned_in and not q.repeatable):
            return False
        if self.level < q.min_level:
            return False
        if any(p not in self.turned_in for p in q.prereqs):
            return False
        if q.prereqs_any and not any(p in self.turned_in for p in q.prereqs_any):
            return False
        if any(e in self.turned_in or e in self.accepted for e in q.exclusive_with):
            return False
        if q.classes and (not self.player_class or self.player_class.lower() not in {c.lower() for c in q.classes}):
            return False   # class quests only in a plan for that class; generic routes add them as .class steps by hand
        if q.races and self.race and self.race.lower() not in {r.lower() for r in q.races}:
            return False
        return self.log_size() < QUEST_LOG_CAP

    def accept(self, q: Quest) -> None:
        self.accepted.add(q.id)

    def objective_done(self, o: Objective) -> bool:
        return o.uid() in self.done_objectives

    def quest_complete(self, q: Quest) -> bool:
        return q.id in self.accepted and all(o.uid() in self.done_objectives for o in q.objectives)

    def can_turnin(self, q: Quest) -> bool:
        return self.quest_complete(q)

    def turnin(self, q: Quest) -> int:
        gained = XP.quest_xp(self.level, q)
        self.accepted.discard(q.id)
        self.turned_in.add(q.id)
        for o in q.objectives:
            self.done_objectives.discard(o.uid())
        self.gain_xp(gained)
        return gained


# --- applying work to a state --------------------------------------------------------------------

def travel(state: PlayerState, world: World, dest: MapPos, seconds: float, kind: str = "run",
           via: Optional[str] = None) -> None:
    state.t += seconds
    state.pos = dest
    if kind == "hearth":
        state.hs_ready_at = state.t + HS_COOLDOWN
    if kind == "fly" and via:
        state.known_flights.add(via)


def do_objective(state: PlayerState, cat: Catalog, cm: CostModel, o: Objective) -> tuple[float, int]:
    """Complete an objective at the current position. Returns (seconds, kill xp)."""
    q = cat.quests[o.quest_id]
    secs = cm.objective_seconds(o, state.level, q.level)
    kill_xp = 0
    if o.kind in (ObjKind.KILL, ObjKind.COLLECT) and o.mob_ids:
        n = cm.kills_needed(o)
        mob = o.mob_level_max if o.mob_level_max is not None else q.level
        # XP per kill changes as the player levels mid-objective; integrate kill by kill (cheap: n is small)
        for _ in range(n):
            kill_xp += XP.mob_xp(state.level, mob)
            state.gain_xp(XP.mob_xp(state.level, mob))
        state.kills += n
    state.t += secs
    state.done_objectives.add(o.uid())
    return secs, kill_xp


def grind_until(state: PlayerState, cm: CostModel, mob_level: int, density: float, target_level: int,
                cfg: XP.XPConfig = XP.CFG) -> tuple[float, int]:
    """Kill mobs of mob_level until reaching target_level. Returns (seconds, xp)."""
    secs, total = 0.0, 0
    guard = 0
    while state.level < target_level and guard < 20000:
        guard += 1
        per = XP.mob_xp(state.level, mob_level, cfg=cfg)
        if per <= 0:
            return float("inf"), total   # grey: cannot grind here
        secs += cm.seconds_per_kill(state.level, mob_level, density)
        state.gain_xp(per, cfg)
        total += per
        state.kills += 1
    state.t += secs
    return secs, total

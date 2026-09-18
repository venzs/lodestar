"""Time models. Every constant here is a prior that laps.py re-fits from recordings.

Kill time (seconds per kill, solo, including pull + fight + loot, excluding downtime):

    ttk(player, mob) = T0(player) * f(delta)            delta = mob_level - player_level
    f(delta) = 1 + 0.30*delta      for delta >= 0   (mob HP grows ~linearly; hit/crit chance drops ~1%/lvl;
                                                     at +3 mobs also start to dodge/parry/resist much more)
             = max(0.35, 1 + 0.15*delta) for delta < 0
    downtime(delta) = D0 * max(0, 1 + 0.5*delta)       eat/drink between fights, grows fast above the player's level
    find(spot)      = FIND0 / density                  running to the next mob

Feasibility (the user's rule): objective difficulty (max mob level, or quest level when no mob data)
must be <= player level + MAX_ABOVE (2); the planner prefers |delta| <= 1 through the score, not a hard cut.

Collect objectives: kills = ceil(count / drop_rate). Interact/explore: a walk to the POI plus a few seconds.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from .model import Objective, ObjKind

MAX_ABOVE = 2            # never plan an objective more than this many levels above the player
PREFER_BAND = 1          # +/-1 gets no penalty; outside the band the score is discounted
DEFAULT_DROP_RATE = 0.5
FIND0 = 5.0              # seconds to locate the next mob at density 1.0
T0_BASE = 9.0            # seconds per equal-level kill at level 1 for an average class
T0_PER_LEVEL = 0.35      # fights get longer as levels rise (more HP on both sides)
D0 = 3.0                 # baseline downtime seconds per kill at equal level
INTERACT_SECONDS = 6.0
ESCORT_DEFAULT = 180.0


@dataclass
class CostModel:
    t0_base: float = T0_BASE
    t0_per_level: float = T0_PER_LEVEL
    up_slope: float = 0.30
    down_slope: float = 0.15
    downtime0: float = D0
    find0: float = FIND0
    class_factor: float = 1.0          # e.g. 0.8 for hunter/warlock, 1.2 for warrior/priest early on
    drop_rate_default: float = DEFAULT_DROP_RATE

    def t0(self, player_level: int) -> float:
        return (self.t0_base + self.t0_per_level * player_level) * self.class_factor

    def ttk(self, player_level: int, mob_level: int) -> float:
        d = mob_level - player_level
        f = 1 + self.up_slope * d if d >= 0 else max(0.35, 1 + self.down_slope * d)
        return self.t0(player_level) * f

    def downtime(self, player_level: int, mob_level: int) -> float:
        d = mob_level - player_level
        return self.downtime0 * max(0.0, 1 + 0.5 * d)

    def seconds_per_kill(self, player_level: int, mob_level: int, density: float = 1.0) -> float:
        return self.ttk(player_level, mob_level) + self.downtime(player_level, mob_level) + self.find0 / max(density, 0.1)

    def kills_needed(self, o: Objective) -> int:
        if o.kind == ObjKind.KILL:
            return o.count
        if o.kind == ObjKind.COLLECT and o.mob_ids:
            p = o.drop_rate or self.drop_rate_default
            return math.ceil(o.count / p)
        return 0

    def objective_seconds(self, o: Objective, player_level: int, quest_level: int) -> float:
        """Time spent at the objective site (travel to it is charged separately)."""
        if o.kind == ObjKind.ESCORT:
            return o.fixed_seconds or ESCORT_DEFAULT
        if o.kind in (ObjKind.INTERACT, ObjKind.EXPLORE):
            return o.fixed_seconds or INTERACT_SECONDS * max(1, o.count)
        mob = o.mob_level_max if o.mob_level_max is not None else quest_level
        return self.kills_needed(o) * self.seconds_per_kill(player_level, mob)


def difficulty(o: Objective, quest_level: int) -> int:
    return o.difficulty_level if o.difficulty_level is not None else quest_level


def feasible(o: Objective, quest_level: int, player_level: int) -> bool:
    return difficulty(o, quest_level) <= player_level + MAX_ABOVE


def band_penalty(o: Objective, quest_level: int, player_level: int) -> float:
    """Multiplier on a bundle's score: 1.0 inside +/-1, decaying outside. Grey objectives still
    count (they unlock turn-ins) but are discounted so the planner does them when convenient."""
    d = difficulty(o, quest_level) - player_level
    if abs(d) <= PREFER_BAND:
        return 1.0
    if d > 0:
        return 0.6 if d == 2 else 0.0
    return max(0.4, 1 - 0.12 * (-d - PREFER_BAND))

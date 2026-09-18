"""Data model for the route optimizer.

Everything positional is stored twice: the (uiMapID, x%, y%) triple that Recorder.lua captures and
the guide format needs, and a world-yards (cx, cy) pair the planner uses for distances.
World conversion lives in world.py (MapFrame).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


@dataclass(frozen=True)
class MapPos:
    map: int          # uiMapID (18 = Tirisfal Glades in the sample guide)
    x: float          # 0-100 percent, as the guide format writes it
    y: float

    def key(self) -> tuple[int, float, float]:
        return (self.map, round(self.x, 1), round(self.y, 1))


@dataclass
class NPC:
    id: int
    name: str
    pos: MapPos
    roles: set[str] = field(default_factory=set)   # questgiver, flightmaster, innkeeper, trainer:<class>, vendor, repair
    samples: int = 1                               # how many recorded positions were averaged


class ObjKind(str, Enum):
    KILL = "kill"          # kill N of mob(s)
    COLLECT = "collect"    # loot N items from mob(s) (needs drop rate)
    INTERACT = "interact"  # ground object / talk to NPC / use item at location
    EXPLORE = "explore"    # reach a location
    ESCORT = "escort"      # fixed-duration scripted event


@dataclass
class Objective:
    quest_id: int
    index: int                         # 1-based, matches C_QuestLog.GetQuestObjectives order
    kind: ObjKind
    text: str
    count: int = 1
    pois: list[MapPos] = field(default_factory=list)   # candidate spots; planner picks the nearest
    mob_ids: tuple[int, ...] = ()                       # for KILL/COLLECT; shared ids => merge visits
    mob_level_min: Optional[int] = None                 # from recordings (Recorder mobs summary) or catalog
    mob_level_max: Optional[int] = None
    drop_rate: Optional[float] = None                   # COLLECT only; None -> cost.DEFAULT_DROP_RATE
    fixed_seconds: Optional[float] = None               # ESCORT / scripted; from recordings

    @property
    def difficulty_level(self) -> Optional[int]:
        return self.mob_level_max

    def uid(self) -> tuple[int, int]:
        return (self.quest_id, self.index)


@dataclass
class Quest:
    id: int
    name: str
    level: int                       # quest level (drives XP scaling)
    min_level: int                   # required level to accept
    xp: int                          # full XP at quest level
    giver: Optional[int]             # NPC id (None: auto-accepted / item-started)
    turnin: Optional[int]            # NPC id
    objectives: list[Objective] = field(default_factory=list)
    prereqs: tuple[int, ...] = ()    # quest ids that must be turned in first (chain)
    exclusive_with: tuple[int, ...] = ()
    classes: tuple[str, ...] = ()    # empty = all
    races: tuple[str, ...] = ()
    faction: str = "Both"
    repeatable: bool = False
    breadcrumb: bool = False         # "go talk to X in the next zone" - turn-in is the next hub's giver
    zone: str = ""

    def is_class_quest(self) -> bool:
        return bool(self.classes)


@dataclass
class Hub:
    """A cluster of NPCs the player interacts with while standing in one spot (~hub_radius yards)."""
    id: int
    name: str
    center: MapPos
    npc_ids: list[int] = field(default_factory=list)
    services: set[str] = field(default_factory=set)   # union of member NPC roles


@dataclass
class FlightNode:
    name: str
    npc_id: int
    pos: MapPos


@dataclass
class Catalog:
    quests: dict[int, Quest]
    npcs: dict[int, NPC]
    flights: dict[str, FlightNode] = field(default_factory=dict)
    flight_seconds: dict[tuple[str, str], float] = field(default_factory=dict)  # (from, to) -> seconds, from recordings
    grind_spots: list["GrindSpot"] = field(default_factory=list)
    faction: str = "Both"
    race: str = ""
    zone_map_names: dict[int, str] = field(default_factory=dict)

    def quest_giver_pos(self, q: Quest) -> Optional[MapPos]:
        return self.npcs[q.giver].pos if q.giver in self.npcs else None

    def quest_turnin_pos(self, q: Quest) -> Optional[MapPos]:
        return self.npcs[q.turnin].pos if q.turnin in self.npcs else None


@dataclass
class GrindSpot:
    """Somewhere with a dense pack of mobs of a known level; from recorded kills or objective POIs."""
    name: str
    pos: MapPos
    mob_level_min: int
    mob_level_max: int
    density: float = 1.0        # relative; 1.0 = ~5 s to find the next mob at level


# --- plan output ---------------------------------------------------------------------------------

class StepKind(str, Enum):
    HUB = "hub"          # turn-ins + accepts (+ services) at one spot
    OBJECTIVE = "objective"
    GRIND = "grind"
    TRAVEL = "travel"    # goto-only (completes on arrival), used for hearth/long legs
    FLY = "fly"
    HEARTH_BIND = "hs"
    TRAIN = "train"
    ZONE = "zone"


@dataclass
class Step:
    kind: StepKind
    goto: Optional[MapPos] = None
    turnins: list[int] = field(default_factory=list)
    accepts: list[int] = field(default_factory=list)
    order: list[tuple[str, int]] = field(default_factory=list)   # ("turnin"|"accept", quest_id) in execution order
    completes: list[tuple[int, int]] = field(default_factory=list)   # (quest_id, objective_index)
    level_gate: Optional[int] = None                                 # .xp N
    zone: Optional[str] = None
    name: Optional[str] = None      # fly destination / hearth name
    text: Optional[str] = None      # >>label override
    classes: tuple[str, ...] = ()
    comment: Optional[str] = None   # trailing "-- ..." (sim time, level, xp/min) for humans
    # bookkeeping filled by the simulator
    sim_t_start: float = 0.0
    sim_t_end: float = 0.0
    sim_level: int = 0
    sim_xp_gained: int = 0

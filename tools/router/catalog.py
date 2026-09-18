"""Load a catalog JSON (see examples/deathknell.json for the shape).

Real data sources for each block (wago.tools CSV exports for build 1.60.1, plus recordings):
  quests      QuestV2CliTask (id, name, quest level, min level, flags), QuestXP (base XP by quest level and
              reward tier), QuestObjective (objectives, counts, type: kill/collect/interact/explore/escort)
  pois        QuestPOIPoint / QuestPOIBlob (objective areas per uiMap), QuestPOI (numeric ids)
  npcs        NOT in client DB2 - positions come from recordings (accept/turn-in entries). Creature names
              from Creature/CreatureDisplayInfo are only names; roles from recordings (TRAINER_SHOW etc.)
  flights     TaxiNodes (positions, names), TaxiPath / TaxiPathNode (routes, length -> seconds)
  map_frames  UiMapAssignment (world bounds per uiMapID)  or the in-game calib dump
  prereqs     QuestV2CliTask has no prerequisite column client-side; use the recorder (order of accepts,
              QUEST_DETAIL after QUEST_TURNED_IN at the same NPC) and community DBs to fill `prereqs`
"""
from __future__ import annotations

import json

from .model import Catalog, FlightNode, GrindSpot, MapPos, NPC, Objective, ObjKind, Quest
from .sim import PlayerState
from .world import MapFrame, World


def _pos(d) -> MapPos:
    return MapPos(int(d["map"]), float(d["x"]), float(d["y"]))


def load(path: str) -> tuple[Catalog, World, PlayerState, dict]:
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    world = World()
    for fr in raw.get("map_frames", []):
        world.frames[int(fr["map"])] = MapFrame(int(fr["map"]), fr["x0"], fr["y0"], fr["x1"], fr["y1"], fr.get("continent", 0))
    npcs = {}
    for n in raw.get("npcs", []):
        npcs[n["id"]] = NPC(n["id"], n["name"], _pos(n), set(n.get("roles", ["questgiver"])))
    quests = {}
    for q in raw.get("quests", []):
        objs = []
        for i, o in enumerate(q.get("objectives", []), 1):
            objs.append(Objective(
                quest_id=q["id"], index=o.get("index", i), kind=ObjKind(o.get("kind", "kill")), text=o["text"],
                count=o.get("count", 1), pois=[_pos(p) for p in o.get("pois", [])],
                mob_ids=tuple(o.get("mob_ids", [])), mob_level_min=o.get("mob_level_min"), mob_level_max=o.get("mob_level_max"),
                drop_rate=o.get("drop_rate"), fixed_seconds=o.get("fixed_seconds")))
        quests[q["id"]] = Quest(
            id=q["id"], name=q["name"], level=q["level"], min_level=q.get("min_level", 1), xp=q["xp"],
            giver=q.get("giver"), turnin=q.get("turnin"), objectives=objs, prereqs=tuple(q.get("prereqs", [])),
            exclusive_with=tuple(q.get("exclusive_with", [])), classes=tuple(q.get("classes", [])),
            races=tuple(q.get("races", [])), faction=q.get("faction", "Both"), repeatable=q.get("repeatable", False),
            breadcrumb=q.get("breadcrumb", False), zone=q.get("zone", ""))
    cat = Catalog(quests=quests, npcs=npcs, faction=raw.get("faction", "Both"), race=raw.get("race", ""))
    for fl in raw.get("flights", []):
        cat.flights[fl["name"]] = FlightNode(fl["name"], fl["npc_id"], _pos(fl))
    for k, v in raw.get("flight_seconds", {}).items():
        a, b = k.split("->")
        cat.flight_seconds[(a.strip(), b.strip())] = float(v)
    for g in raw.get("grind_spots", []):
        cat.grind_spots.append(GrindSpot(g["name"], _pos(g), g["mob_level_min"], g["mob_level_max"], g.get("density", 1.0)))
    s = raw.get("start", {})
    start = PlayerState(t=0.0, pos=_pos(s) if s else next(iter(npcs.values())).pos, level=s.get("level", 1),
                        player_class=s.get("class", ""), race=raw.get("race", ""))
    return cat, world, start, raw

"""Build a router catalog straight from the Vanilla database (Lodestar_Guide/Data/Vanilla.lua).

    python3 -m tools.router.vanilla_catalog --zone Durotar --faction Horde --race Orc --levels 1-12 -o /tmp/durotar.json
    python3 -m tools.router /tmp/durotar.json --target 12 --class Warrior -o /tmp/durotar.txt

The JSON has the same shape catalog.load() reads (see examples/deathknell.json), so everything downstream
(planner, validate, emit, laps) works unchanged. What comes from where:

  quests      Vanilla.lua quests[]: title, quest level (lvl), min level (min), race/class masks, `pre`
              (prerequisites; pfQuest lists alternatives, so it maps to Quest.prereqs_any: ONE of them must
              be done), giver = first start npc, turn-in = first end npc (or the start npc of the object
              when a quest ends at an object - those get a synthetic NPC id 900000+objID)
  objectives  obj.npcs -> KILL (one per npc id, count DEFAULT_KILLS); obj.items -> COLLECT (count
              DEFAULT_COLLECT, mob_ids = the item's drop sources, drop_rate = best source's %; when the item
              only comes from objects it is INTERACT); obj.objs -> INTERACT; obj.areas -> EXPLORE.
              pfQuest has no objective counts, so the counts are the usual starter-zone numbers and the
              index order is npcs, items, objs, areas - the guide author checks both against the quest text
              (a named 100% drop or a rare <= 30% drop counts as one item, the rest as DEFAULT_COLLECT).
  positions   percent coordinates on the pfQuest zone id (AreaTable id). MapPos.map holds that id and
              `map_names` carries the zone name so emit() writes `.goto Durotar,42.1,68.3`.
  map frames  ZONE_FRAMES below: the Classic (1.12) WorldMapArea rectangles in yards as map addons of the era
              carried them (Astrolabe's zoneData): width/height of the zone map and its offset on the
              continent map, x growing east, y growing south. Kalimdor is continent 1, Eastern Kingdoms 0.
              Values are approximate (±1%), which is far below the routing model's own error; the in-game
              calib dump (docs/DESIGN.md) replaces them when available.
  quest XP    QUEST_XP: an approximation of the Classic 1.12 "standard" quest reward tier by quest level
              (kill / collect quests). Quests without objectives (hand-offs, "report to") get 20% of it,
              minimum 40. Every value is corrected by harvested QUEST_TURNED_IN xp later (laps.calibrate).
  npc roles   questgiver from start/end lists, innkeeper by name, flight masters from FLIGHT_MASTERS,
              trainer:<class> from Data/Trainers.lua.
  grind spots one per hostile mob type with >= GRIND_MIN_SPOTS positions in the zone (its centroid sample).
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import re
import sys
from dataclasses import dataclass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUERY_PY = os.path.join(ROOT, "tools", "pfquest", "query.py")
TRAINERS_LUA = os.path.join(ROOT, "Lodestar_Guide", "Data", "Trainers.lua")

RACE_BIT = {"Human": 1, "Orc": 2, "Dwarf": 4, "NightElf": 8, "Undead": 16, "Scourge": 16, "Tauren": 32, "Gnome": 64, "Troll": 128}
HORDE_MASK, ALLIANCE_MASK = 2 | 16 | 32 | 128, 1 | 4 | 8 | 64
CLASS_BIT = {"Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16, "Shaman": 64, "Mage": 128, "Warlock": 256, "Druid": 1024}

DEFAULT_KILLS = 8
DEFAULT_COLLECT = 6
DEFAULT_OBJECTS = 5
GRIND_MIN_SPOTS = 3
OBJ_NPC_BASE = 900000        # synthetic NPC ids for quests that start/end at a game object

# Classic 1.12 quest XP, standard tier, by quest level (approximation; see module docstring).
QUEST_XP = {1: 40, 2: 170, 3: 250, 4: 360, 5: 450, 6: 550, 7: 630, 8: 700, 9: 800, 10: 875, 11: 950, 12: 1150,
            13: 1250, 14: 1300, 15: 1400, 16: 1500, 17: 1600, 18: 1700, 19: 1800, 20: 1950, 21: 2050, 22: 2150,
            23: 2250, 24: 2350, 25: 2450, 26: 2550, 27: 2650, 28: 2750, 29: 2850, 30: 2950}


def quest_xp(level: int, has_objectives: bool) -> int:
    lvl = max(1, min(level, max(QUEST_XP)))
    base = QUEST_XP[lvl] if lvl in QUEST_XP else QUEST_XP[max(QUEST_XP)] + 100 * (lvl - max(QUEST_XP))
    if has_objectives:
        return base
    return max(40, int(round(base * 0.2 / 5.0) * 5))


@dataclass(frozen=True)
class ZoneFrame:
    name: str
    continent: int      # 1 Kalimdor, 0 Eastern Kingdoms
    x_off: float        # yards, top-left corner of the zone map on the continent map
    y_off: float
    width: float
    height: float


# pfQuest zone id -> frame. Astrolabe-era WorldMapArea numbers (yards); approximate.
try:
    from .map_frames import AREA_TO_UIMAP, FRAMES as CLIENT_FRAMES
    from . import taxi_routes
    from .world import MapFrame, TAXI_SPEED
    from .model import MapPos
except ImportError:  # run as a script rather than a module
    from map_frames import AREA_TO_UIMAP, FRAMES as CLIENT_FRAMES  # type: ignore
    import taxi_routes  # type: ignore
    from world import MapFrame, TAXI_SPEED  # type: ignore
    from model import MapPos  # type: ignore


ZONE_FRAMES: dict[int, ZoneFrame] = {
    # Kalimdor
    331: ZoneFrame("Ashenvale", 1, 15366.76, 8126.93, 5766.73, 3843.72),
    16: ZoneFrame("Azshara", 1, 20343.90, 7458.18, 5070.89, 3381.23),
    17: ZoneFrame("The Barrens", 1, 14443.96, 11187.32, 10133.44, 6756.20),
    148: ZoneFrame("Darkshore", 1, 14125.08, 4466.53, 6550.07, 4366.64),
    1657: ZoneFrame("Darnassus", 1, 14128.39, 2561.57, 1058.34, 705.72),
    405: ZoneFrame("Desolace", 1, 12833.40, 12347.72, 4495.88, 2997.90),
    14: ZoneFrame("Durotar", 1, 19029.30, 10991.48, 5287.55, 3525.01),
    15: ZoneFrame("Dustwallow Marsh", 1, 18041.79, 14833.12, 5250.04, 3500.00),
    361: ZoneFrame("Felwood", 1, 15425.10, 5666.53, 5750.05, 3833.33),
    357: ZoneFrame("Feralas", 1, 11625.06, 15166.45, 6950.08, 4633.30),
    493: ZoneFrame("Moonglade", 1, 18448.05, 4308.20, 2308.36, 1539.57),
    215: ZoneFrame("Mulgore", 1, 15018.84, 13072.72, 5137.55, 3424.99),
    1637: ZoneFrame("Orgrimmar", 1, 20747.42, 10525.94, 1402.62, 935.41),
    1377: ZoneFrame("Silithus", 1, 14529.25, 18758.10, 3483.37, 2322.90),
    406: ZoneFrame("Stonetalon Mountains", 1, 13820.91, 9883.26, 4883.39, 3256.23),
    440: ZoneFrame("Tanaris", 1, 17285.53, 18674.76, 6900.08, 4600.03),
    141: ZoneFrame("Teldrassil", 1, 13252.16, 968.68, 5091.72, 3393.73),
    400: ZoneFrame("Thousand Needles", 1, 17500.12, 16766.44, 4400.05, 2933.31),
    1638: ZoneFrame("Thunder Bluff", 1, 16550.11, 13649.80, 1043.76, 695.83),
    490: ZoneFrame("Un'Goro Crater", 1, 16533.44, 18766.43, 3700.04, 2466.65),
    618: ZoneFrame("Winterspring", 1, 17383.45, 4266.54, 7100.08, 4733.37),
    # Eastern Kingdoms
    36: ZoneFrame("Alterac Mountains", 0, 17388.63, 9676.38, 2800.04, 1866.67),
    45: ZoneFrame("Arathi Highlands", 0, 19038.66, 11309.72, 3600.05, 2400.03),
    3: ZoneFrame("Badlands", 0, 20251.19, 17066.15, 2487.53, 1658.35),
    4: ZoneFrame("Blasted Lands", 0, 19413.65, 21743.09, 3350.04, 2233.36),
    46: ZoneFrame("Burning Steppes", 0, 18438.63, 18207.66, 2929.17, 1952.08),
    41: ZoneFrame("Deadwind Pass", 0, 19005.32, 21043.09, 2500.04, 1666.66),
    1: ZoneFrame("Dun Morogh", 0, 16369.85, 15053.48, 4925.06, 3283.37),
    10: ZoneFrame("Duskwood", 0, 17338.63, 20893.09, 2700.03, 1800.02),
    139: ZoneFrame("Eastern Plaguelands", 0, 20459.48, 7472.21, 3870.05, 2581.26),
    12: ZoneFrame("Elwynn Forest", 0, 16636.51, 19116.01, 3470.87, 2314.59),
    267: ZoneFrame("Hillsbrad Foothills", 0, 17105.30, 10776.38, 3200.04, 2133.36),
    1537: ZoneFrame("Ironforge", 0, 18885.51, 15745.63, 790.63, 527.60),
    38: ZoneFrame("Loch Modan", 0, 20165.71, 15663.90, 2758.37, 1839.59),
    44: ZoneFrame("Redridge Mountains", 0, 19741.05, 19751.42, 2170.86, 1447.91),
    51: ZoneFrame("Searing Gorge", 0, 18494.87, 17276.41, 2231.28, 1487.52),
    130: ZoneFrame("Silverpine Forest", 0, 14721.96, 9509.71, 4200.06, 2800.03),
    1519: ZoneFrame("Stormwind City", 0, 16449.09, 19172.22, 1737.53, 1158.37),
    33: ZoneFrame("Stranglethorn Vale", 0, 15951.30, 22345.03, 6381.26, 4254.19),
    8: ZoneFrame("Swamp of Sorrows", 0, 20394.83, 20797.57, 2293.78, 1529.19),
    47: ZoneFrame("The Hinterlands", 0, 19746.06, 11255.98, 3850.05, 2566.70),
    85: ZoneFrame("Tirisfal Glades", 0, 15138.65, 7338.88, 4518.81, 3012.53),
    1497: ZoneFrame("Undercity", 0, 17298.86, 9298.39, 959.38, 640.11),
    28: ZoneFrame("Western Plaguelands", 0, 17755.31, 7809.71, 4300.05, 2866.66),
    40: ZoneFrame("Westfall", 0, 15155.29, 20576.44, 3500.03, 2333.40),
    11: ZoneFrame("Wetlands", 0, 18561.66, 13324.32, 4135.26, 2756.25),
}

# NPC ids that sell a flight. Only the ids: the names that used to sit beside them came from
# memory and three of them were wrong -- 1387 "Stormwind" is Thysta, the Grom'gol wind rider master
# (Horde, on the other continent's list), 2299 "Lakeshire" is Borgus Stoutarm at Morgan's Vigil in
# the Burning Steppes, and 931 "Sentinel Hill" is Ariena Stormfeather, whom pfQuest places 114 yards
# from the Lakeshire flight point rather than in Westfall. The name a guide says to fly to now comes
# from the client's TaxiNodes, and taxi_network() reports any id here that is not standing on one.
#
# Still hand-typed because no client table links a creature to a taxi node: DB2 knows where the
# flight points are, not who takes the money. This covers the 1-30 world, not all ~60 of them.
FLIGHT_MASTERS = {
    523, 931, 1387, 1571, 1573, 2226, 2299, 2389, 2409, 2432, 2851, 2861, 2995,
    3305, 3310, 3615, 3838, 3841, 4267, 4312, 4314, 4319, 4321, 4407, 4551, 6026,
    10378, 12616, 16227,
}

# Flight master NPCs, by the name the guide says to fly to. Kept because pfQuest has no role for
# them: TaxiNodes says where the flight points are, not which creature sells the ride. The node a
# name belongs to is matched by position rather than by string, which is also how this list gets
# checked - a name here that is nowhere near a taxi node is reported by taxi_network().
FLIGHT_MASTER_MAX_YARDS = 25.0  # matches land within 10; 25 leaves room for a re-recorded position


def npc_world(n) -> "tuple[int, float, float] | None":
    """A catalog NPC's (map, x%, y%) in world yards, or None if no client rectangle covers its map.

    Only the client's own frames are used. The Astrolabe-era ZONE_FRAMES fallback stores an offset
    and a size rather than two corners and does not share the client's sign conventions, so mixing
    the two here would put an NPC in the wrong hemisphere; a miss just leaves the flight point
    without an NPC attached, which costs nothing but discoverability in that one zone."""
    key = n["map"]
    ui = key if key in CLIENT_FRAMES else AREA_TO_UIMAP.get(key)
    if ui not in CLIENT_FRAMES:
        return None
    _name, cont, x0, y0, x1, y1 = CLIENT_FRAMES[ui]
    wx, wy = MapFrame(ui, x0, y0, x1, y1, cont).to_world(MapPos(ui, n["x"], n["y"]))
    return cont, wx, wy


def taxi_network(faction: str, npcs: dict) -> "tuple[list, dict]":
    """Every flight point this faction can select, plus the flying time between each reachable pair.

    Both halves come from the client (tools/wowdb/import_taxi.py). Before this, `flights` held only
    the hand-listed flight masters that happened to stand in the zone being routed and
    `flight_seconds` was always empty, so travel_options() priced a flight as a straight line at
    TAXI_SPEED -- roughly 40% short, because a flight path bends and usually changes griffon
    somewhere in the middle.

    Distant nodes are emitted too, even though the player has not discovered them: the planner only
    adds a node to known_flights when it walks a hub that contains its flight master, so listing
    them cannot make it fly somewhere it has not been. It only means the destination exists once it
    has."""
    if faction not in ("Horde", "Alliance"):
        return [], {}
    nodes = taxi_routes.nodes(faction)
    conts = taxi_routes.continents()
    node_npc: dict[int, int] = {}
    unmatched: list[str] = []
    for nid in sorted(FLIGHT_MASTERS):
        n = npcs.get(nid)
        if not n:
            continue
        w = npc_world(n)
        if w is None:
            continue
        cont, wx, wy = w
        near = [(math.dist((wx, wy), (nx, ny)), i) for i, (_s, _p, nx, ny) in nodes.items()
                if conts[i] == cont]
        d, i = min(near, default=(math.inf, 0))
        if d <= FLIGHT_MASTER_MAX_YARDS and i not in node_npc:
            node_npc[i] = nid
        elif d != math.inf:
            unmatched.append(f"{n.get('name', nid)} ({nid}): nearest {faction} taxi node "
                             f"({nodes[i][0]}) is {d:.0f} yd away")
    for u in unmatched:
        print(f"  flight master not at a taxi node: {u}", file=sys.stderr)

    flights = [{"name": s, "npc_id": node_npc.get(i, 0), "map": p.map, "x": round(p.x, 2), "y": round(p.y, 2)}
               for i, (s, p, _x, _y) in sorted(nodes.items(), key=lambda kv: kv[1][0])]
    secs = {}
    for (a, b), yards in taxi_routes.route_yards(faction).items():
        secs[f"{nodes[a][0]} -> {nodes[b][0]}"] = round(yards / TAXI_SPEED, 1)
    return flights, secs


# Quest flags/ids that are not part of a leveling route (seasonal, max-level, PvP).
SEASONAL_TITLES = ("Winter's Presents", "Raptor Replacement", "A Donation of", "Treats for Greatfather", "Stolen Winter Veil",
                   "Smokywood Pastures", "Great-father Winter", "Metzen the Reindeer", "The Feast of Winter Veil",
                   "Warsong Gulch", "Past Victories", "Past Efforts", "Alterac Valley", "Arathi Basin", "Concerted Efforts")


# --- loading -----------------------------------------------------------------------------------------------

def load_vanilla():
    spec = importlib.util.spec_from_file_location("pfquest_query", QUERY_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod.load()


def load_trainers() -> dict[int, str]:
    """npc id -> class file (lower-case) from Data/Trainers.lua."""
    out: dict[int, str] = {}
    if not os.path.exists(TRAINERS_LUA):
        return out
    src = open(TRAINERS_LUA, encoding="utf-8").read()
    body = src.split("Guide.TrainerData = {", 1)[1].split("\n}\n", 1)[0]
    for m in re.finditer(r"(\w+) = \{(.*?)\n\t\},", body, re.S):
        cls = m.group(1).lower()
        for line in m.group(2).splitlines():
            line = line.split("--", 1)[0]
            for n in re.findall(r"\d+", line):
                out[int(n)] = cls
    return out


def zone_id(data, want: str) -> int:
    if want.isdigit():
        return int(want)
    for z, n in data["zones"].items():
        if n.lower() == want.lower():
            return z
    for z, f in ZONE_FRAMES.items():
        if f.name.lower() == want.lower():
            return z
    raise SystemExit(f"unknown zone {want!r}")


def coord_in(entity, zone: int):
    """First coordinate of an entity in `zone` (nearest its centroid there), else None."""
    for c in entity.get("c") or []:
        if c[0] == zone:
            return c
    return None


def any_framed_coord(entity, zones: list[int]):
    for z in zones:
        c = coord_in(entity, z)
        if c:
            return c
    for c in entity.get("c") or []:
        if c[0] in ZONE_FRAMES:
            return c
    return None


def race_names(mask: int) -> list[str]:
    """Race restriction as names; empty when the mask covers a whole faction (nothing to restrict)."""
    if not mask or (mask & HORDE_MASK) == HORDE_MASK or (mask & ALLIANCE_MASK) == ALLIANCE_MASK:
        return []
    return mask_names(mask, RACE_BIT)


def class_names(mask: int) -> list[str]:
    """Class restriction as names. Masks of four or more classes are "everyone except X" variants (Vile
    Familiars 792 is for every class but warlocks, who get 1485/1499) and count as unrestricted."""
    names = mask_names(mask, CLASS_BIT)
    return names if len(names) <= 3 else []


def mask_names(mask: int, table: dict[str, int]) -> list[str]:
    seen = set()
    out = []
    for name, bit in table.items():
        if mask & bit and bit not in seen:
            seen.add(bit)
            out.append(name)
    return out


# --- the build -----------------------------------------------------------------------------------------------

def build(data, zones: list[int], faction: str, race: str, levels: tuple[int, int], player_class: str = "",
          bbox: tuple[float, float, float, float] | None = None, start: tuple[float, float] | None = None) -> dict:
    lo, hi = levels
    primary = zones[0]
    trainers = load_trainers()
    race_bit = RACE_BIT.get(race, 0)
    faction_mask = HORDE_MASK if faction == "Horde" else ALLIANCE_MASK if faction == "Alliance" else 0

    def in_bbox(c) -> bool:
        if not bbox or c[0] != primary:
            return True
        return bbox[0] <= c[1] <= bbox[2] and bbox[1] <= c[2] <= bbox[3]

    def race_ok(q) -> bool:
        m = q.get("race") or 0
        if not m:
            return True
        if race_bit and not (m & race_bit):
            return False
        if faction_mask and not (m & faction_mask):
            return False
        return True

    npcs: dict[int, dict] = {}

    def add_npc(nid: int, role: str, prefer_zone: int | None = None) -> bool:
        e = data["npcs"].get(nid)
        if not e:
            return False
        c = coord_in(e, prefer_zone) if prefer_zone else None
        c = c or any_framed_coord(e, zones)
        if not c:
            return False
        n = npcs.setdefault(nid, {"id": nid, "name": e.get("n", f"npc {nid}"), "map": c[0], "x": c[1], "y": c[2], "roles": []})
        if role not in n["roles"]:
            n["roles"].append(role)
        return True

    def add_obj_as_npc(oid: int, role: str) -> int | None:
        e = data["objs"].get(oid)
        if not e:
            return None
        c = coord_in(e, primary) or any_framed_coord(e, zones)
        if not c:
            return None
        nid = OBJ_NPC_BASE + oid
        n = npcs.setdefault(nid, {"id": nid, "name": e.get("n", f"object {oid}"), "map": c[0], "x": c[1], "y": c[2], "roles": []})
        if role not in n["roles"]:
            n["roles"].append(role)
        return nid

    def spots(entity, zone_pref: int):
        """Positions of an entity: the ones in the primary zone first, then other framed zones."""
        out = []
        for c in entity.get("c") or []:
            if c[0] == zone_pref and c[0] in ZONE_FRAMES:
                out.append({"map": c[0], "x": c[1], "y": c[2]})
        if not out:
            for c in entity.get("c") or []:
                if c[0] in ZONE_FRAMES and c[0] in zones:
                    out.append({"map": c[0], "x": c[1], "y": c[2]})
        return out

    def mob_levels(nid: int):
        e = data["npcs"].get(nid) or {}
        lvl = e.get("lvl")
        if isinstance(lvl, list) and len(lvl) == 2:
            return int(lvl[0]), int(lvl[1])
        return None, None

    quests = []
    for qid, q in sorted(data["quests"].items()):
        qlvl = int(q.get("lvl") or 0)
        qmin = int(q.get("min") or 1)
        if qlvl > hi + 1 or qmin > hi:
            continue
        if not race_ok(q):
            continue
        if q.get("event") or any(s in (q.get("t") or "") for s in SEASONAL_TITLES) or qmin >= 50:
            continue          # world events (Winter Veil, Scourge Invasion, ...) are not part of a route
        st = q.get("start") or {}
        giver_ids = list(st.get("npcs") or [])
        giver_pos = None
        giver = None
        for nid in giver_ids:
            c = coord_in(data["npcs"].get(nid, {}), primary)
            if c and in_bbox(c):
                giver, giver_pos = nid, c
                break
        if giver is None:
            for oid in st.get("objs") or []:
                c = coord_in(data["objs"].get(oid, {}), primary)
                if c and in_bbox(c):
                    giver = add_obj_as_npc(oid, "questgiver")
                    giver_pos = c
                    break
        if giver is None or giver_pos is None:
            continue          # item-started or not in this zone
        if giver < OBJ_NPC_BASE:
            add_npc(giver, "questgiver", primary)
        en = q.get("end") or {}
        turnin = None
        for nid in en.get("npcs") or []:
            if add_npc(nid, "questgiver", primary):
                turnin = nid
                break
        if turnin is None:
            for oid in en.get("objs") or []:
                turnin = add_obj_as_npc(oid, "questgiver")
                if turnin:
                    break
        objectives = []
        o = q.get("obj") or {}
        for nid in o.get("npcs") or []:
            e = data["npcs"].get(nid)
            if not e:
                continue
            lmin, lmax = mob_levels(nid)
            objectives.append({"kind": "kill", "text": f"Kill {e.get('n', '?')}", "count": DEFAULT_KILLS,
                               "mob_ids": [nid], "mob_level_min": lmin, "mob_level_max": lmax, "pois": spots(e, primary)})
        for iid in o.get("items") or []:
            it = data["items"].get(iid)
            if not it:
                continue
            srcs = sorted(it.get("npcs") or [], key=lambda s: -s[1])
            mobs = []
            for nid, pct in srcs:
                e = data["npcs"].get(nid)
                if not e:
                    continue
                ps = spots(e, primary)
                if not ps:
                    continue
                lmin, lmax = mob_levels(nid)
                mobs.append((nid, pct, lmin, lmax, ps, e.get("n", "?")))
            if mobs:
                # farm the easiest source: sort by max level, keep those within 2 levels of the easiest
                mobs.sort(key=lambda m: (m[3] if m[3] is not None else qlvl))
                easiest = mobs[0][3] if mobs[0][3] is not None else qlvl
                keep = [m for m in mobs if (m[3] if m[3] is not None else qlvl) <= easiest + 2]
                pois = [p for m in keep for p in m[4]]
                best_pct = keep[0][1]
                # a named drop (100% from one spawn) or a rare drop (<= 30%) is a single item; the rest are stacks
                count = 1 if (best_pct >= 95 and len(keep[0][4]) <= 2) or best_pct <= 30 else DEFAULT_COLLECT
                objectives.append({"kind": "collect", "text": f"Collect {it.get('n', '?')} from {keep[0][5]}",
                                   "count": count, "mob_ids": [m[0] for m in keep],
                                   "mob_level_min": min((m[2] for m in keep if m[2] is not None), default=None),
                                   "mob_level_max": max((m[3] for m in keep if m[3] is not None), default=None),
                                   "drop_rate": min(1.0, max(keep[0][1], 5) / 100.0), "pois": pois})
                continue
            osrcs = sorted(it.get("objs") or [], key=lambda s: -s[1])
            pois = []
            for oid, _pct in osrcs:
                e = data["objs"].get(oid)
                if e:
                    pois += spots(e, primary)
            if pois:
                objectives.append({"kind": "interact", "text": f"Collect {it.get('n', '?')}", "count": DEFAULT_OBJECTS, "pois": pois})
            # else: vendor item / quest-start item / drops elsewhere -> no objective (the planner cannot place it)
        for oid in o.get("objs") or []:
            e = data["objs"].get(oid)
            if not e:
                continue
            objectives.append({"kind": "interact", "text": f"Use {e.get('n', '?')}", "count": 1, "pois": spots(e, primary)})
        for aid in o.get("areas") or []:
            a = data["areas"].get(aid)
            if a:
                objectives.append({"kind": "explore", "text": "Explore the area", "count": 1, "pois": spots(a, primary)})
        if o and not objectives:
            continue      # every objective needs something the data cannot place (PvP marks, items from another zone)
        for i, ob in enumerate(objectives, 1):
            ob["index"] = i
        quests.append({
            "id": qid, "name": q.get("t") or f"quest {qid}", "level": max(1, qlvl), "min_level": qmin,
            "xp": quest_xp(max(1, qlvl), bool(objectives)),
            "giver": giver, "turnin": turnin, "objectives": objectives,
            "prereqs_any": [p for p in (q.get("pre") or [])],
            "classes": class_names(q.get("class") or 0),
            "races": race_names(q.get("race") or 0),
            "faction": faction if q.get("race") else "Both",
            "breadcrumb": turnin is None or npcs.get(turnin, {}).get("map") != primary,
            "zone": ZONE_FRAMES[primary].name if primary in ZONE_FRAMES else data["zones"].get(primary, str(primary)),
        })

    # services in the loaded zones
    for nid, e in data["npcs"].items():
        name = e.get("n") or ""
        c = any_framed_coord(e, zones)
        if not c or c[0] not in zones:
            continue
        if name.startswith("Innkeeper"):
            add_npc(nid, "innkeeper")
        if nid in FLIGHT_MASTERS:
            add_npc(nid, "flightmaster")
        if nid in trainers:
            add_npc(nid, f"trainer:{trainers[nid]}")
    flights, flight_seconds = taxi_network(faction, npcs)

    # grind spots: hostile mobs with several positions in the primary zone
    grind = []
    for nid, e in data["npcs"].items():
        if e.get("f"):
            continue
        lmin, lmax = mob_levels(nid)
        if lmin is None or lmax > hi + 3 or lmin < lo - 2:
            continue
        cs = [c for c in e.get("c") or [] if c[0] == primary and in_bbox(c)]
        if len(cs) < GRIND_MIN_SPOTS:
            continue
        c = cs[0]
        grind.append({"name": e.get("n", f"npc {nid}"), "map": c[0], "x": c[1], "y": c[2],
                      "mob_level_min": lmin, "mob_level_max": lmax, "density": 1.0})

    # Frames are world rectangles in the UiMapAssignment convention -- see world.MapFrame, whose
    # to_world() maps the map's horizontal axis onto world y and its vertical axis onto world x.
    #
    # Frames: the client's own rectangles where it has them, the Astrolabe-era hand table only for
    # anything it does not. They agree to within a yard on 44 of 46 shared zones, so this is not a
    # rewrite -- it is the two that disagree (Mulgore is 20% larger than the hand table said, and
    # every distance computed in it was wrong by that much) and the maps that were never in it.
    #
    # Emitted under BOTH ids a coordinate might carry. pfQuest writes an old area id into c[0] and
    # the harvest writes a uiMapID, and after Data.lua merges the sources both arrive in the same
    # slot; a frame table that knows only one of them fails on whichever source it does not.
    frames, map_names, seen = [], {}, set()

    def put(key, name, continent, x0, y0, x1, y1):
        if key in seen:
            return
        seen.add(key)
        frames.append({"map": key, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "continent": continent})
        if name:
            map_names[str(key)] = name

    for ui, (name, cont, x0, y0, x1, y1) in CLIENT_FRAMES.items():
        put(ui, name, cont, x0, y0, x1, y1)
    for area, ui in AREA_TO_UIMAP.items():
        if ui in CLIENT_FRAMES:
            name, cont, x0, y0, x1, y1 = CLIENT_FRAMES[ui]
            put(area, ZONE_FRAMES[area].name if area in ZONE_FRAMES else name, cont, x0, y0, x1, y1)
    # The hand table stores an Astrolabe rectangle: an offset on the continent map plus a width
    # (east-west) and a height (north-south). A MapFrame is two world corners with world x running
    # north and world y running west, so width belongs on the y axis and height on the x axis --
    # which is exactly how the client's own numbers came out, and why 44 of these 46 match it to
    # within a yard when compared that way round. The offsets are Astrolabe's continent frame, not
    # world coordinates, so a converted frame gets distances inside the zone right and its absolute
    # position wrong. Harmless today: the client covers all 46, so nothing reaches this loop.
    for z, f in ZONE_FRAMES.items():
        put(z, f.name, f.continent, f.y_off, f.x_off, f.y_off + f.height, f.x_off + f.width)

    # start: explicit, else the giver of the lowest-level quest without prerequisites
    if start:
        s = {"map": primary, "x": start[0], "y": start[1]}
    else:
        first = min((q for q in quests if not q["prereqs_any"] and q["giver"] in npcs), key=lambda q: (q["level"], q["id"]), default=None)
        g = npcs[first["giver"]] if first else next(iter(npcs.values()))
        s = {"map": g["map"], "x": g["x"], "y": g["y"]}
    s["level"] = lo
    if player_class:
        s["class"] = player_class

    zone_name = ZONE_FRAMES[primary].name if primary in ZONE_FRAMES else data["zones"].get(primary, str(primary))
    return {
        "_comment": f"Generated by tools/router/vanilla_catalog.py from Data/Vanilla.lua: {zone_name}, {faction}/{race}, levels {lo}-{hi}. "
                    "Quest XP and objective counts are approximations (see the module docstring).",
        "faction": faction, "race": race, "zone": zone_name, "levels": [lo, hi],
        "map_frames": frames, "map_names": map_names,
        "start": s,
        "npcs": sorted(npcs.values(), key=lambda n: n["id"]),
        "quests": quests,
        "flights": flights,
        "flight_seconds": flight_seconds,
        "grind_spots": grind,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tools.router.vanilla_catalog", description=__doc__.split("\n\n")[0])
    ap.add_argument("--zone", required=True, help="zone name or pfQuest area id; comma-separated for extra zones (first is primary)")
    ap.add_argument("--faction", default="Horde", choices=["Horde", "Alliance", "Both"])
    ap.add_argument("--race", default="", help="Orc, Troll, Tauren, Undead, ... (filters race-locked quests)")
    ap.add_argument("--class", dest="player_class", default="", help="Warrior, Shaman, ... (start.class for the planner)")
    ap.add_argument("--levels", default="1-12", help="lo-hi: quests above hi+1 are left out, start level = lo")
    ap.add_argument("--bbox", default=None, help="x0,y0,x1,y1 percent box on the primary zone map; quest givers outside it are ignored")
    ap.add_argument("--start", default=None, help="x,y start position on the primary map (default: first quest giver)")
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args(argv)
    data = load_vanilla()
    zones = [zone_id(data, z.strip()) for z in args.zone.split(",")]
    lo, hi = (int(x) for x in args.levels.split("-"))
    bbox = tuple(float(x) for x in args.bbox.split(",")) if args.bbox else None
    start = tuple(float(x) for x in args.start.split(",")) if args.start else None
    raw = build(data, zones, args.faction, args.race, (lo, hi), args.player_class, bbox, start)  # type: ignore[arg-type]
    text = json.dumps(raw, indent=1)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {args.out}: {len(raw['quests'])} quests, {len(raw['npcs'])} npcs, {len(raw['flights'])} flights, "
              f"{len(raw['grind_spots'])} grind spots", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

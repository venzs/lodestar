#!/usr/bin/env python3
"""Convert the pfQuest Vanilla database (tools/pfquest/src/, see fetch.sh) into Lodestar_Guide/Data/Vanilla.lua.

Output shape (one Lua file, `Guide.VanillaData`):

  zones  = { [areaID] = "Zone Name" }                         -- only zones some coordinate uses
  quests = { [questID] = { t = "title", lvl = n, min = n, race = mask, class = mask, skill = n, event = n,
                           start = { npcs = {ids}, objs = {ids}, items = {ids} },
                           ["end"] = { npcs = {ids}, objs = {ids} },
                           obj = { npcs = {ids}, objs = {ids}, items = {ids}, areas = {ids} },
                           pre = {questIDs}, next = {questIDs} } }
  npcs   = { [id] = { n = "name", lvl = {min, max}, r = rank, f = "A"|"H"|"AH", c = { {zone, x, y}, ... } } }
  objs   = { [id] = { n = "name", c = { {zone, x, y}, ... } } }
  items  = { [id] = { n = "name", npcs = { {npcID, dropPct}, ... }, objs = { {objID, pct}, ... }, vend = {npcIDs} } }
  areas  = { [id] = { c = { {zone, x, y}, ... } } }          -- areatriggers used by explore objectives

`zone` is the pfQuest zone id (an AreaTable id: 12 = Elwynn Forest, 85 = Tirisfal Glades, 1637 = Orgrimmar);
the addon resolves the name in `zones` to a uiMapID at runtime. Coordinates are percent of that zone's map,
one decimal, capped at MAX_COORDS well-spread samples per entity (spread across zones first, then farthest-point
sampling inside a zone). Empty fields are omitted.

Included: every quest with a title; every npc/object referenced by a quest (start/end/objective) or by the drop
sources of a quest item; every other npc that has coordinates (mobs matter for "level of mobs" routing).
Objects not tied to a quest (ore, herbs, chests, mailboxes) are left out.
"""
from __future__ import annotations

import math
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "Lodestar_Guide", "Data", "Vanilla.lua")

MAX_COORDS = 12          # samples kept per npc/object
MAX_ITEM_SOURCES = 8     # drop sources kept per quest item (best chance first)
MAX_VENDORS = 4
MIN_DROP_PCT = 0.5       # drop sources below this are only kept when nothing better exists
CHUNK = 1500             # entries per emitted function (Lua 5.1 allows 2^18 constants per function)


# --- a small parser for pfQuest's literal Lua tables -----------------------------------------------------------

_NUM = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
_IDENT = re.compile(r"[A-Za-z_]\w*")


def parse_lua_table(text: str):
    pos = 0
    n = len(text)

    def skip_ws():
        nonlocal pos
        while pos < n:
            c = text[pos]
            if c in " \t\r\n":
                pos += 1
            elif text.startswith("--", pos):
                e = text.find("\n", pos)
                pos = n if e < 0 else e + 1
            else:
                break

    def parse_string(q: str) -> str:
        nonlocal pos
        pos += 1
        out = []
        while True:
            ch = text[pos]
            if ch == "\\":
                nx = text[pos + 1]
                if nx.isdigit():
                    j = pos + 1
                    num = ""
                    while j < pos + 4 and text[j].isdigit():
                        num += text[j]
                        j += 1
                    out.append(chr(int(num)))
                    pos = j
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nx, nx))
                pos += 2
            elif ch == q:
                pos += 1
                return "".join(out)
            else:
                out.append(ch)
                pos += 1

    def parse_value():
        nonlocal pos
        skip_ws()
        c = text[pos]
        if c == "{":
            return parse_table()
        if c in "\"'":
            return parse_string(c)
        m = _NUM.match(text, pos)
        if m:
            pos = m.end()
            s = m.group(0)
            return float(s) if any(ch in s for ch in ".eE") else int(s)
        for kw, v in (("true", True), ("false", False), ("nil", None)):
            if text.startswith(kw, pos):
                pos += len(kw)
                return v
        raise ValueError("bad value at %d: %r" % (pos, text[pos:pos + 40]))

    def parse_table():
        nonlocal pos
        pos += 1  # '{'
        d = {}
        idx = 1
        while True:
            skip_ws()
            if text[pos] == "}":
                pos += 1
                return d
            if text[pos] == "[":
                pos += 1
                k = parse_value()
                skip_ws()
                pos += 1  # ']'
                skip_ws()
                pos += 1  # '='
                d[k] = parse_value()
            else:
                m = _IDENT.match(text, pos)
                if m and text[m.end():].lstrip().startswith("="):
                    pos = m.end()
                    skip_ws()
                    pos += 1
                    d[m.group(0)] = parse_value()
                else:
                    d[idx] = parse_value()
                    idx += 1
            skip_ws()
            if text[pos] in ",;":
                pos += 1

    return parse_value()


def load(rel: str):
    path = os.path.join(SRC, rel)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    return parse_lua_table(text[text.index("{"):])


def values(t) -> list:
    """Array part of a parsed Lua table, in index order."""
    if not t:
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


# --- coordinates ------------------------------------------------------------------------------------------------

def r1(v: float) -> float:
    return math.floor(v * 10 + 0.5) / 10


def to_parent_zone(zone: int, x: float, y: float, zones_data: dict):
    """Lift a coordinate given in a sub-area (zones.data entry with a parent) into its parent zone's map."""
    seen = 0
    while zone in zones_data and seen < 4:
        parent, width, height, cx, cy = values(zones_data[zone])[:5]
        if not parent:
            break
        x = cx + (x - 50) * width / 100
        y = cy + (y - 50) * height / 100
        zone = parent
        seen += 1
    return zone, x, y


def spread(points: list[tuple[int, float, float]], limit: int) -> list[tuple[int, float, float]]:
    """Keep at most `limit` points, spread across zones first and by farthest-point sampling inside a zone.
    The first point of every zone is the one nearest that zone's centroid."""
    by_zone: dict[int, list] = defaultdict(list)
    for z, x, y in points:
        by_zone[z].append((x, y))
    for z in by_zone:
        by_zone[z] = sorted(set(by_zone[z]))
    zones = sorted(by_zone, key=lambda z: (-len(by_zone[z]), z))
    total = sum(len(v) for v in by_zone.values())
    if total <= limit:
        quota = {z: len(by_zone[z]) for z in zones}
    else:
        quota = {z: 1 for z in zones[:limit]}
        left = limit - len(quota)
        # largest remainder on the proportional share of what is left
        shares = {z: (len(by_zone[z]) - 1) * left / max(1, total - len(quota)) for z in quota}
        for z in quota:
            add = min(int(shares[z]), len(by_zone[z]) - 1)
            quota[z] += add
            left -= add
        for z in sorted(quota, key=lambda z: -(shares[z] - int(shares[z]))):
            if left <= 0:
                break
            if quota[z] < len(by_zone[z]):
                quota[z] += 1
                left -= 1
    out = []
    for z in zones:
        pts = by_zone[z]
        k = quota.get(z, 0)
        if k <= 0:
            continue
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        first = min(pts, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
        chosen = [first]
        rest = [p for p in pts if p != first]
        dist = {p: (p[0] - first[0]) ** 2 + (p[1] - first[1]) ** 2 for p in rest}
        while len(chosen) < k and rest:
            far = max(rest, key=lambda p: dist[p])
            chosen.append(far)
            rest.remove(far)
            for p in rest:
                d = (p[0] - far[0]) ** 2 + (p[1] - far[1]) ** 2
                if d < dist[p]:
                    dist[p] = d
        out.extend((z, x, y) for x, y in chosen)
    return out


def coords_of(entry: dict, zones_data: dict, with_respawn=True) -> list[tuple[int, float, float]]:
    pts = []
    for c in values(entry.get("coords")):
        c = values(c)
        if len(c) < 3:
            continue
        x, y, zone = float(c[0]), float(c[1]), int(c[2])
        zone, x, y = to_parent_zone(zone, x, y, zones_data)
        if 0 <= x <= 100 and 0 <= y <= 100:
            pts.append((zone, r1(x), r1(y)))
    return pts


# --- Lua emitting -------------------------------------------------------------------------------------------------

def lua_str(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def lua_num(v) -> str:
    if isinstance(v, float):
        if v == int(v):
            return str(int(v))
        return ("%.1f" % v)
    return str(v)


def lua_list(vals) -> str:
    return "{" + ",".join(lua_num(v) if isinstance(v, (int, float)) else v for v in vals) + "}"


def lua_fields(pairs) -> str:
    """pairs: [(key, rendered value or None)] -> '{k=v,...}' skipping None."""
    parts = []
    for k, v in pairs:
        if v is None:
            continue
        key = ('["%s"]' % k) if k in ("end",) else k
        parts.append("%s=%s" % (key, v))
    return "{" + ",".join(parts) + "}"


def lua_idlist(ids) -> str | None:
    ids = sorted(set(int(i) for i in ids))
    return lua_list(ids) if ids else None


# --- build ------------------------------------------------------------------------------------------------------------

def main() -> int:
    if not os.path.isdir(SRC):
        print("missing %s — run tools/pfquest/fetch.sh first" % SRC, file=sys.stderr)
        return 1
    version = {}
    vpath = os.path.join(SRC, "VERSION.txt")
    if os.path.exists(vpath):
        for line in open(vpath, encoding="utf-8"):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                version[k] = v

    quests = load("db/quests.lua")
    units = load("db/units.lua")
    objects = load("db/objects.lua")
    items = load("db/items.lua")
    refloot = load("db/refloot.lua")
    areatrigger = load("db/areatrigger.lua")
    zones_data = load("db/zones.lua")
    zone_names = load("db/enUS/zones.lua")
    quest_loc = load("db/enUS/quests.lua")
    unit_names = load("db/enUS/units.lua")
    object_names = load("db/enUS/objects.lua")
    item_names = load("db/enUS/items.lua")

    # Quests ---------------------------------------------------------------------------------------------------------
    # Areatriggers without coordinates are useless to the arrow; drop the references so every id in `areas` resolves.
    positioned_areas = {aid for aid, a in areatrigger.items() if coords_of(a, zones_data)}
    quest_out = {}
    ref_units, ref_objects, ref_items, ref_areas = set(), set(), set(), set()
    next_of: dict[int, set] = defaultdict(set)
    for qid, q in quests.items():
        loc = quest_loc.get(qid) or {}
        title = loc.get("T")
        if not title:
            continue
        for pre in values(q.get("pre")):
            next_of[int(pre)].add(qid)
        quest_out[qid] = (q, title)

    def section(sec: dict | None, keys: tuple[str, ...]):
        sec = sec or {}
        got = {}
        for k in keys:
            ids = [int(i) for i in values(sec.get(k))]
            if ids:
                got[k] = sorted(set(ids))
        return got

    q_lines = []
    stats = Counter()
    for qid in sorted(quest_out):
        q, title = quest_out[qid]
        start = section(q.get("start"), ("U", "O", "I"))
        end = section(q.get("end"), ("U", "O"))
        obj = section(q.get("obj"), ("U", "O", "I", "A"))
        if "A" in obj:
            obj["A"] = [a for a in obj["A"] if a in positioned_areas]
            if not obj["A"]:
                del obj["A"]
        ref_units.update(start.get("U", []), end.get("U", []), obj.get("U", []))
        ref_objects.update(start.get("O", []), end.get("O", []), obj.get("O", []))
        ref_items.update(start.get("I", []), obj.get("I", []))
        ref_areas.update(obj.get("A", []))
        pre = sorted(set(int(p) for p in values(q.get("pre"))))
        nxt = sorted(next_of.get(qid, ()))
        stats["quests"] += 1
        if start:
            stats["quests_with_start"] += 1
        if obj:
            stats["quests_with_obj"] += 1

        def block(sec, names):
            if not sec:
                return None
            return lua_fields([(name, lua_idlist(sec[k])) for k, name in names if k in sec])

        fields = [
            ("t", lua_str(title)),
            ("lvl", lua_num(q["lvl"]) if q.get("lvl") is not None else None),
            ("min", lua_num(q["min"]) if q.get("min") is not None else None),
            ("race", lua_num(q["race"]) if q.get("race") else None),
            ("class", lua_num(q["class"]) if q.get("class") else None),
            ("skill", lua_num(q["skill"]) if q.get("skill") else None),
            ("event", lua_num(q["event"]) if q.get("event") else None),
            ("start", block(start, (("U", "npcs"), ("O", "objs"), ("I", "items")))),
            ("end", block(end, (("U", "npcs"), ("O", "objs")))),
            ("obj", block(obj, (("U", "npcs"), ("O", "objs"), ("I", "items"), ("A", "areas")))),
            ("pre", lua_idlist(pre)),
            ("next", lua_idlist(nxt)),
        ]
        q_lines.append("[%d]=%s" % (qid, lua_fields(fields)))

    # Items (quest-referenced only) ------------------------------------------------------------------------------------
    def item_sources(iid: int):
        it = items.get(iid) or {}
        npc_src: dict[int, float] = {}
        obj_src: dict[int, float] = {}
        for u, chance in (it.get("U") or {}).items():
            npc_src[int(u)] = max(npc_src.get(int(u), 0), float(chance or 0))
        for o, chance in (it.get("O") or {}).items():
            obj_src[int(o)] = max(obj_src.get(int(o), 0), float(chance or 0))
        for ref, chance in (it.get("R") or {}).items():
            rl = refloot.get(ref) or {}
            for u in (rl.get("U") or {}):
                npc_src[int(u)] = max(npc_src.get(int(u), 0), float(chance or 0))
            for o in (rl.get("O") or {}):
                obj_src[int(o)] = max(obj_src.get(int(o), 0), float(chance or 0))
        vendors = sorted(int(v) for v in (it.get("V") or {}))

        def top(src: dict, keep_positions: bool):
            ranked = sorted(src.items(), key=lambda kv: (-kv[1], kv[0]))
            # prefer sources that actually have a position, then chance
            if keep_positions:
                ranked.sort(key=lambda kv: (0 if (units.get(kv[0]) or {}).get("coords") else 1, -kv[1], kv[0]))
            else:
                ranked.sort(key=lambda kv: (0 if (objects.get(kv[0]) or {}).get("coords") else 1, -kv[1], kv[0]))
            good = [kv for kv in ranked if kv[1] >= MIN_DROP_PCT]
            return (good or ranked)[:MAX_ITEM_SOURCES]

        return top(npc_src, True), top(obj_src, False), vendors[:MAX_VENDORS]

    i_lines = []
    for iid in sorted(ref_items):
        npc_src, obj_src, vendors = item_sources(iid)
        name = item_names.get(iid)
        ref_units.update(u for u, _ in npc_src)
        ref_units.update(vendors)
        ref_objects.update(o for o, _ in obj_src)
        if npc_src or obj_src:
            stats["items_with_source"] += 1
        stats["items"] += 1
        fields = [
            ("n", lua_str(name) if name else None),
            ("npcs", lua_list(lua_list([u, r1(c)]) for u, c in npc_src) if npc_src else None),
            ("objs", lua_list(lua_list([o, r1(c)]) for o, c in obj_src) if obj_src else None),
            ("vend", lua_idlist(vendors)),
        ]
        i_lines.append("[%d]=%s" % (iid, lua_fields(fields)))

    # NPCs -----------------------------------------------------------------------------------------------------------------
    used_zones: set[int] = set()

    def parse_level(s):
        if s is None:
            return None
        s = str(s).strip()
        m = re.fullmatch(r"(\d+)(?:\s*-\s*(\d+))?", s)
        if not m:
            return None
        lo = int(m.group(1))
        hi = int(m.group(2) or lo)
        if lo <= 0:
            return None
        return (min(lo, hi), max(lo, hi))

    n_lines = []
    for uid in sorted(units):
        u = units[uid]
        pts = coords_of(u, zones_data)
        if uid not in ref_units and not pts:
            continue
        pts = spread(pts, MAX_COORDS)
        for z, _, _ in pts:
            used_zones.add(z)
        lvl = parse_level(u.get("lvl"))
        rank = u.get("rnk")
        name = unit_names.get(uid)
        stats["npcs"] += 1
        if uid in ref_units:
            stats["npcs_quest"] += 1
        if pts:
            stats["npcs_with_coords"] += 1
        stats["npc_coords"] += len(pts)
        fields = [
            ("n", lua_str(name) if name else None),
            ("lvl", lua_list(lvl) if lvl else None),
            ("r", lua_num(int(rank)) if rank not in (None, "", "0", 0) else None),
            ("f", lua_str(str(u["fac"])) if u.get("fac") else None),
            ("c", lua_list(lua_list(p) for p in pts) if pts else None),
        ]
        n_lines.append("[%d]=%s" % (uid, lua_fields(fields)))

    # Objects (quest-referenced only) ------------------------------------------------------------------------------------
    o_lines = []
    for oid in sorted(ref_objects):
        o = objects.get(oid) or {}
        pts = spread(coords_of(o, zones_data), MAX_COORDS)
        for z, _, _ in pts:
            used_zones.add(z)
        name = object_names.get(oid)
        stats["objs"] += 1
        if pts:
            stats["objs_with_coords"] += 1
        stats["obj_coords"] += len(pts)
        fields = [
            ("n", lua_str(name) if name else None),
            ("c", lua_list(lua_list(p) for p in pts) if pts else None),
        ]
        o_lines.append("[%d]=%s" % (oid, lua_fields(fields)))

    # Areatriggers used by explore objectives --------------------------------------------------------------------------
    a_lines = []
    for aid in sorted(ref_areas):
        a = areatrigger.get(aid) or {}
        pts = spread(coords_of(a, zones_data), MAX_COORDS)
        for z, _, _ in pts:
            used_zones.add(z)
        if pts:
            stats["areas"] += 1
            a_lines.append("[%d]=%s" % (aid, lua_fields([("c", lua_list(lua_list(p) for p in pts))])))

    # Zones ------------------------------------------------------------------------------------------------------------------
    z_lines = []
    for z in sorted(used_zones):
        name = zone_names.get(z)
        if not name:
            print("warning: zone %d has no name" % z, file=sys.stderr)
            continue
        z_lines.append("[%d]=%s" % (z, lua_str(name)))
    stats["zones"] = len(z_lines)

    # Write ----------------------------------------------------------------------------------------------------------------
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    src_note = "%s @ %s (fetched %s)" % (version.get("repo", "https://github.com/shagu/pfQuest"),
                                          version.get("ref", "master"), version.get("fetched", "?"))
    out = []
    out.append("-- Lodestar_Guide: Vanilla quest / NPC / object position database. GENERATED FILE — do not edit.")
    out.append("--   source: pfQuest, %s" % src_note)
    out.append("--   license: MIT, Copyright (c) 2017-2021 Eric Mauser (Shagu) — see Data/LICENSE-pfQuest.txt")
    out.append("--   regenerate: tools/pfquest/fetch.sh && python3 tools/pfquest/import.py")
    out.append("--")
    out.append("-- zones  [areaID] = name           coordinates below use these ids; resolve name -> uiMapID via C_Map at runtime")
    out.append("-- quests [id] = { t, lvl, min, race, class, skill, event, start{npcs,objs,items}, end{npcs,objs},")
    out.append("--                  obj{npcs,objs,items,areas}, pre{}, next{} }")
    out.append("-- npcs   [id] = { n, lvl = {min,max}, r = rank (1 elite, 2 rare elite, 3 boss, 4 rare), f = friendly to A/H/AH, c = {{zone,x,y},...} }")
    out.append("-- objs   [id] = { n, c = {{zone,x,y},...} }")
    out.append("-- items  [id] = { n, npcs = {{npcID, dropPct},...}, objs = {{objID, pct},...}, vend = {npcIDs} }   (quest items only)")
    out.append("-- areas  [id] = { c = {{zone,x,y},...} }   (areatriggers for explore objectives)")
    out.append("local Guide = _G.Lodestar:GetModule(\"Guide\")")
    out.append("local D = { zones = {}, quests = {}, npcs = {}, objs = {}, items = {}, areas = {} }")
    out.append("Guide.VanillaData = D")
    out.append("local fill")

    def emit(name: str, lines: list[str]):
        # Each chunk is its own function so no single function nears Lua 5.1's constant-table limit
        # (2^18 constants per function); a plain `(function(t) ... end)(x)` statement would be ambiguous syntax in 5.1.
        for i in range(0, len(lines), CHUNK):
            out.append("fill = function(t)")
            for line in lines[i:i + CHUNK]:
                out.append("t" + line)
            out.append("end")
            out.append("fill(D.%s)" % name)

    emit("zones", z_lines)
    emit("quests", q_lines)
    emit("npcs", n_lines)
    emit("objs", o_lines)
    emit("items", i_lines)
    emit("areas", a_lines)
    out.append("")
    text = "\n".join(out)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    size = os.path.getsize(OUT)
    print("wrote %s (%.2f MB)" % (os.path.relpath(OUT, ROOT), size / 1e6))
    for k in ("zones", "quests", "quests_with_start", "quests_with_obj", "npcs", "npcs_quest", "npcs_with_coords",
              "npc_coords", "objs", "objs_with_coords", "obj_coords", "items", "items_with_source", "areas"):
        print("  %-18s %d" % (k, stats[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

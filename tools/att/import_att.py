#!/usr/bin/env python3
"""Build Lodestar_Guide/Data/ATT.lua from All The Things' Camelot database.

    lua5.1 tools/att/att_to_json.lua <att>/db/Camelot/**/*.lua > data/att/att-camelot.json
    python3 tools/att/import_att.py data/att/att-camelot.json

ATT (https://github.com/ATTWoWAddon/AllTheThings, MIT) maintains a Forever/Camelot database with
quest-giver coordinates, objective providers and the sourceQuests prerequisite graph. It covers the
classic world densely and the new Forever zones thinly; Lodestar's own harvest is the reverse. So
this is merged UNDER the harvest overlay: ATT fills the world in, and anything a real player
recorded first-hand wins over it (Data.lua: MergeATTData runs before MergeForeverData).

Emitted in the same shape as the Forever overlay so one reader serves both:
  quests[id] = { start = {npcs={...}}, acceptAt = {0,x,y,m=map}, prev = {...}, lvl, spots = {...} }
  npcs[id]   = { c = { {0,x,y,m=map}, ... } }
Coordinates are percent (0-100), matching Data/Forever.lua.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "Lodestar_Guide", "Data", "ATT.lua")
CHUNK = 1200          # entries per fill() function: Lua 5.1 caps constants per function
MAX_SPOTS = 4         # objective spots kept per objective


def lua_str(s):
    s = str(s).replace("\\", "\\\\").replace('"', '\\"')
    s = s.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    s = re.sub(r"[\x00-\x1f\x7f]", lambda m: "\\%03d" % ord(m.group(0)), s)
    return '"' + s + '"'


def lua_num(v):
    f = float(v)
    if f == int(f):
        return str(int(f))
    return ("%.1f" % f).rstrip("0").rstrip(".")


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_value(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k in sorted(v, key=lambda k: (isinstance(k, str), k)):
            val = v[k]
            if val is None or val == [] or val == {}:
                continue
            if isinstance(k, int):
                key = "[%d]" % k
            elif re.match(r"^[A-Za-z_]\w*$", k) and k not in ("end", "for", "in", "do", "then"):
                key = k
            else:
                key = "[%s]" % lua_str(k)
            parts.append("%s=%s" % (key, lua_value(val)))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(v))


def coord(c):
    """{0, x, y, m = uiMapID} -- indexable like Vanilla's {zone, x, y} with zone 0 and the map in m."""
    return {1: 0, 2: round(float(c["x"]), 1), 3: round(float(c["y"]), 1), "m": int(c["m"])}


def dedupe(coords, limit=None):
    out, seen = [], set()
    for c in coords or []:
        try:
            key = (int(c["m"]), round(float(c["x"]), 1), round(float(c["y"]), 1))
        except (KeyError, TypeError, ValueError):
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append({"m": key[0], "x": key[1], "y": key[2]})
        if limit and len(out) >= limit:
            break
    return out


def build(raw):
    quests, npcs, objs = {}, {}, {}

    for k, v in (raw.get("quests") or {}).items():
        qid = int(k)
        q = {}
        coords = dedupe(v.get("coords"), 1)
        if coords:
            q["acceptAt"] = coord(coords[0])
        if v.get("qgs"):
            q["start"] = {"npcs": sorted(set(int(i) for i in v["qgs"]))}
        if v.get("qis"):
            q["item"] = int(v["qis"][0])
        if v.get("prev"):
            q["prev"] = sorted(set(int(i) for i in v["prev"]))
        if v.get("lvl"):
            q["lvl"] = int(v["lvl"])
        if v.get("map"):
            q["map"] = int(v["map"])
        # Objective providers become "spots" keyed by objective index, the same shape the harvest
        # writes, so Data.lua's objective routing needs no special case for ATT.
        spots = {}
        for o in v.get("obj") or []:
            idx = int(o.get("i") or 0)
            if idx <= 0:
                continue
            pts = dedupe(o.get("coords"), MAX_SPOTS)
            if pts:
                spots[idx] = [coord(p) for p in pts]
            prov = {}
            for key, src in (("npcs", "npcs"), ("items", "items"), ("objects", "objs")):
                if o.get(key):
                    prov[src] = sorted(set(int(i) for i in o[key]))
            if prov:
                q.setdefault("objp", {})[idx] = prov
        if spots:
            q["spots"] = spots
        if q:
            quests[qid] = q

    for k, v in (raw.get("npcs") or {}).items():
        pts = dedupe(v.get("coords"), 6)
        if pts:
            npcs[int(k)] = {"c": [coord(p) for p in pts]}

    for k, v in (raw.get("objects") or {}).items():
        pts = dedupe(v.get("coords"), 6)
        if pts:
            objs[int(k)] = {"c": [coord(p) for p in pts]}

    return quests, npcs, objs


def emit_table(lines, target, table):
    """Write `table` into `target` in CHUNK-sized fill() functions (Lua 5.1 constant limit)."""
    items = sorted(table.items())
    for i in range(0, len(items), CHUNK):
        lines.append("fill = function(t)")
        for qid, body in items[i:i + CHUNK]:
            lines.append("t[%d]=%s" % (qid, lua_value(body)))
        lines.append("end")
        lines.append("fill(%s)" % target)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "data", "att", "att-camelot.json")
    raw = json.load(open(src, encoding="utf-8"))
    quests, npcs, objs = build(raw)

    lines = [
        "-- Lodestar_Guide: All The Things overlay -- quest givers, objective providers and quest",
        "-- chains for WoW: Forever, converted from ATT's Camelot database.",
        "-- GENERATED by tools/att/import_att.py. Do not edit.",
        "--",
        "-- Source: https://github.com/ATTWoWAddon/AllTheThings (MIT, see Data/LICENSE-ATT.txt).",
        "-- Merged UNDER the harvest overlay (Data.lua: MergeATTData): ATT covers the old world",
        "-- densely and the new zones thinly, and anything a player recorded first-hand wins.",
        "-- Coordinates are {0, x, y, m = uiMapID} in percent, as in Data/Forever.lua.",
        "local Guide = _G.Lodestar:GetModule(\"Guide\")",
        "local A = { quests = {}, npcs = {}, objs = {} }",
        "local fill",
    ]
    emit_table(lines, "A.quests", quests)
    emit_table(lines, "A.npcs", npcs)
    emit_table(lines, "A.objs", objs)
    lines.append("Guide.ATTData = A")
    lines.append("")

    body = "\n".join(lines)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(body)
    print("wrote %s: %d quests, %d npcs, %d objects (%d bytes)"
          % (os.path.relpath(OUT, ROOT), len(quests), len(npcs), len(objs), len(body)))
    withstart = sum(1 for q in quests.values() if q.get("start"))
    withpos = sum(1 for q in quests.values() if q.get("acceptAt"))
    withprev = sum(1 for q in quests.values() if q.get("prev"))
    print("  with a giver: %d, with a position: %d, with prerequisites: %d" % (withstart, withpos, withprev))


if __name__ == "__main__":
    main()

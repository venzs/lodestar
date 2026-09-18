#!/usr/bin/env python3
"""Build Lodestar_Guide/Data/Forever.lua from harvested LodestarScanDB exports.

    lua5.1 tools/pfquest/sv_to_json.lua <SavedVariables/Lodestar_Guide.lua> > data/beta/scan-YYYY-MM-DD.json
    python3 tools/pfquest/merge_scan.py data/beta/*.json

The harvest (see Lodestar_Guide/Harvest.lua) records what the client shows a player on the Forever beta:
quests with titles/levels/objectives (census + quest log), the NPC that gave/ended each quest, reward XP,
where objectives were worked on, and every NPC talked to or targeted with a position. This script keeps
what the Vanilla database does not have (Forever-only quests, Forever-only NPCs, changed givers/enders)
and writes it as an overlay the addon merges over Data/Vanilla.lua at load (Data.lua: MergeForeverData).

Coordinates are uiMapID-based: { 0, x, y, m = <uiMapID> } (x, y in percent), unlike Vanilla's zone ids.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(ROOT, "Lodestar_Guide", "Data", "Forever.lua")
sys.path.insert(0, HERE)
from query import load as load_vanilla  # noqa: E402

JUNK = re.compile(r"<nyi>|<txt>|<unused>|test quest|do not use|test copy", re.I)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%.1f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
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
            key = ("[%d]" % k) if isinstance(k, int) else (k if re.match(r"^[A-Za-z_]\w*$", k) and k != "end" else "[%s]" % lua_str(k))
            parts.append("%s=%s" % (key, lua_value(val)))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(v))


def coord(pos):
    """{1=0, 2=x, 3=y, m=uiMapID}: indexable like Vanilla's {zone, x, y} with zone 0 and the map in m."""
    return {1: 0, 2: round(float(pos[1]), 1), 3: round(float(pos[2]), 1), "m": int(pos[0])}


def coord_list(entries):
    out, seen = [], set()
    for p in entries:
        key = (int(p[0]), round(float(p[1]), 1), round(float(p[2]), 1))
        if key in seen:
            continue
        seen.add(key)
        out.append(coord((key[0], key[1], key[2])))
    return out


def index_map(v):
    """SavedVariables tables with 1..n keys arrive as JSON lists; sparse ones as dicts."""
    if isinstance(v, list):
        return {i + 1: x for i, x in enumerate(v) if x is not None}
    if isinstance(v, dict):
        return {int(k): x for k, x in v.items()}
    return {}


def merge(exports):
    npcs, objects, quests, taxi, levels = {}, {}, {}, {}, {}
    for path in exports:
        raw = json.load(open(path, encoding="utf-8"))
        for k, v in (raw.get("npcs") or {}).items():
            e = npcs.setdefault(int(k), {"name": None, "positions": [], "samples": [], "gives": set(), "ends": set(), "kind": {}, "minL": None, "maxL": None, "trains": None})
            if v.get("name"):
                e["name"] = v["name"]
            if v.get("exact") and v.get("map"):
                e["positions"].append((v["map"], v["x"], v["y"]))
            elif v.get("map"):
                e["samples"].append((v["map"], v["x"], v["y"]))
            for s in v.get("samples") or []:
                e["samples"].append((s[0], s[1], s[2]))
            e["gives"].update(int(q) for q in (v.get("gives") or {}))
            e["ends"].update(int(q) for q in (v.get("ends") or {}))
            e["kind"].update(v.get("kind") or {})
            if v.get("trains"):
                e["trains"] = v["trains"]
            for key in ("minL", "maxL"):
                if v.get(key) is not None:
                    e[key] = v[key] if e[key] is None else (min if key == "minL" else max)(e[key], v[key])
        for k, v in (raw.get("objects") or {}).items():
            e = objects.setdefault(int(k), {"name": None, "positions": [], "gives": set(), "ends": set()})
            if v.get("name"):
                e["name"] = v["name"]
            if v.get("map"):
                e["positions"].append((v["map"], v["x"], v["y"]))
            e["gives"].update(int(q) for q in (v.get("gives") or {}))
            e["ends"].update(int(q) for q in (v.get("ends") or {}))
        for k, v in (raw.get("quests") or {}).items():
            q = quests.setdefault(int(k), {})
            for key in ("t", "lvl", "o", "giver", "ender", "xp", "money", "tag", "acceptAt", "turninAt", "prog", "fin", "done", "auto", "freq", "rep"):
                if v.get(key) is not None and (key not in q or key in ("o", "prog", "fin", "done")):
                    q[key] = v[key]
        for k, v in (raw.get("taxi") or {}).items():
            taxi[int(k)] = v
        for k, v in (raw.get("levels") or {}).items():
            levels[int(k)] = v
    return npcs, objects, quests, taxi, levels


def build(exports):
    vanilla = load_vanilla()
    npcs, objects, quests, taxi, levels = merge(exports)
    out_quests, out_npcs, out_objs = {}, {}, {}

    # quest starts/ends known from the NPC side
    starts, ends = {}, {}
    for nid, e in npcs.items():
        for qid in e["gives"]:
            starts.setdefault(qid, set()).add(nid)
        for qid in e["ends"]:
            ends.setdefault(qid, set()).add(nid)
    for qid, q in quests.items():
        if isinstance(q.get("giver"), int):
            starts.setdefault(qid, set()).add(q["giver"])
        if isinstance(q.get("ender"), int):
            ends.setdefault(qid, set()).add(q["ender"])

    for qid, q in sorted(quests.items()):
        title = q.get("t")
        if not title or JUNK.search(title):
            continue
        van = vanilla["quests"].get(qid)
        forever_only = van is None
        entry = {}
        if forever_only:
            # census-only ids without a level or objectives are dev/test leftovers on this client
            if not q.get("lvl") and not q.get("o"):
                continue
            entry["t"] = title
            if q.get("lvl"):
                entry["lvl"] = q["lvl"]
            if q.get("o"):
                entry["o"] = [{"text": o.get("text"), "type": o.get("type"), "n": o.get("n")} for o in q["o"] if o.get("text")]
            if q.get("tag"):
                entry["tag"] = q["tag"]
        # starts / ends we learned (also for Vanilla quests when the data has none, or when Forever moved them)
        s = sorted(starts.get(qid, ()))
        e = sorted(ends.get(qid, ()))
        if s and (forever_only or not (van.get("start") or {}).get("npcs")):
            entry["start"] = {"npcs": s}
        if e and (forever_only or not (van.get("end") or {}).get("npcs")):
            entry["end"] = {"npcs": e}
        if q.get("xp"):
            entry["xp"] = q["xp"]
        spots = {}
        fin = q.get("fin")
        if not isinstance(fin, (dict, list)):  # older builds stored finished spots under "done", colliding with the flag
            fin = q.get("done") if isinstance(q.get("done"), (dict, list)) else {}
        for idx, pos in index_map(fin).items():
            spots[idx] = [pos]
        for idx, lst in index_map(q.get("prog")).items():
            spots.setdefault(idx, []).extend(lst)
        if spots and (forever_only or not van.get("obj")):
            entry["spots"] = {i: coord_list(v) for i, v in spots.items()}
        if forever_only and not entry.get("start") and q.get("acceptAt"):
            entry["acceptAt"] = coord(q["acceptAt"])
        if forever_only and not entry.get("end") and q.get("turninAt"):
            entry["turninAt"] = coord(q["turninAt"])
        if len(entry) > (0 if forever_only else 0) and (forever_only or any(k in entry for k in ("start", "end", "spots", "xp"))):
            out_quests[qid] = entry

    for nid, e in sorted(npcs.items()):
        van = vanilla["npcs"].get(nid)
        entry = {}
        if van:
            # A known NPC: only an interaction-exact position that disagrees with every Vanilla spot is
            # worth shipping (Forever moved it); mouse-over samples are within ~30 yd of the player, not the NPC.
            pos = [p for p in e["positions"] if not any(abs(c[1] - p[1]) < 1.5 and abs(c[2] - p[2]) < 1.5 for c in (van.get("c") or []))]
            if not pos and not e["trains"]:
                continue
        else:
            if not e["name"]:
                continue
            pos = e["positions"] or e["samples"]
            entry["n"] = e["name"]
            if e["minL"]:
                entry["lvl"] = [e["minL"], e["maxL"] or e["minL"]]
        if pos:
            entry["c"] = coord_list(pos[:6])
        kinds = {k: True for k, v in e["kind"].items() if v}
        if e["trains"]:
            kinds["trainer"] = True
            entry["trains"] = e["trains"]
        if kinds:
            entry["kind"] = kinds
        if entry:
            out_npcs[nid] = entry

    for oid, e in sorted(objects.items()):
        if e["positions"]:
            out_objs[oid] = {"n": e["name"] or ("Object %d" % oid), "c": coord_list(e["positions"][:6])}

    lines = [
        "-- Lodestar_Guide: Forever overlay — quests, NPCs and positions harvested on the WoW: Forever beta.",
        "-- GENERATED by tools/pfquest/merge_scan.py from LodestarScanDB exports (data/beta/). Do not edit.",
        "-- Merged over Data/Vanilla.lua at load (Data.lua: Guide:MergeForeverData). Coordinates are {0, x, y, m = uiMapID}.",
        "local Guide = _G.Lodestar:GetModule(\"Guide\")",
        "local F = { quests = {}, npcs = {}, objs = {}, taxi = {}, levels = {} }",
        "Guide.ForeverData = F",
    ]
    for qid, q in sorted(out_quests.items()):
        lines.append("F.quests[%d]=%s" % (qid, lua_value(q)))
    for nid, n in sorted(out_npcs.items()):
        lines.append("F.npcs[%d]=%s" % (nid, lua_value(n)))
    for oid, o in sorted(out_objs.items()):
        lines.append("F.objs[%d]=%s" % (oid, lua_value(o)))
    for tid, t in sorted(taxi.items()):
        lines.append("F.taxi[%d]=%s" % (tid, lua_value({k: v for k, v in t.items() if k in ("name", "map", "x", "y", "state", "links")})))
    for lvl, xp in sorted(levels.items()):
        lines.append("F.levels[%d]=%d" % (lvl, xp))
    text = "\n".join(lines) + "\n"
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote %s: %d quests, %d npcs, %d objects, %d taxi nodes, %d levels (%d bytes)" % (
        os.path.relpath(OUT, ROOT), len(out_quests), len(out_npcs), len(out_objs), len(taxi), len(levels), len(text)))
    return out_quests, out_npcs


if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "data", "beta", "*.json")))
    if not files:
        sys.exit("no exports given")
    build(files)

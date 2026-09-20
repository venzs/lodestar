#!/usr/bin/env python3
"""Query the generated Lodestar_Guide/Data/Vanilla.lua from the command line.

    python3 tools/pfquest/query.py quest 363 364 3901        # quest cards: giver, ender, objectives with positions
    python3 tools/pfquest/query.py npc 1569 "Deathguard"      # npc by id or name substring
    python3 tools/pfquest/query.py zone 85 --max-level 12     # quests starting in a zone (area id or name)
    python3 tools/pfquest/query.py chain 363                  # follow `next` links from a quest

Positions are printed as `zone x,y`; `--zone <id>` prefers positions in that zone for objectives.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "Lodestar_Guide", "Data", "Vanilla.lua")
CURATED = os.path.join(HERE, "..", "..", "Lodestar_Guide", "Data", "Curated.lua")


def lua_value(text):
    """Parse the subset of Lua literals the data file uses (tables, strings, numbers)."""
    pos = 0

    def skip_ws():
        nonlocal pos
        while pos < len(text) and text[pos] in " \t\r\n":
            pos += 1

    def parse():
        nonlocal pos
        skip_ws()
        c = text[pos]
        if c == "{":
            pos += 1
            arr, obj, idx = [], {}, 1
            while True:
                skip_ws()
                if text[pos] == "}":
                    pos += 1
                    break
                if text[pos] == "[":
                    pos += 1
                    key = parse()
                    skip_ws()
                    assert text[pos] == "]"
                    pos += 1
                    skip_ws()
                    assert text[pos] == "="
                    pos += 1
                    obj[key] = parse()
                else:
                    m = re.match(r"([A-Za-z_]\w*)\s*=", text[pos:])
                    if m:
                        pos += m.end()
                        obj[m.group(1)] = parse()
                    else:
                        arr.append(parse())
                        idx += 1
                skip_ws()
                if text[pos] == ",":
                    pos += 1
            if obj and arr:
                for i, v in enumerate(arr, 1):
                    obj[i] = v
                return obj
            return obj if obj else arr
        if c == '"':
            m = re.match(r'"((?:[^"\\]|\\.)*)"', text[pos:])
            pos += m.end()
            return m.group(1).encode().decode("unicode_escape")
        m = re.match(r"-?\d+(?:\.\d+)?", text[pos:])
        if m:
            pos += m.end()
            s = m.group(0)
            return float(s) if "." in s else int(s)
        if text.startswith("true", pos):
            pos += 4
            return True
        if text.startswith("false", pos):
            pos += 5
            return False
        raise ValueError("unexpected %r at %d" % (text[pos:pos + 20], pos))

    return parse()


def load():
    src = open(DATA, encoding="utf-8").read()
    data = {"zones": {}, "quests": {}, "npcs": {}, "objs": {}, "items": {}, "areas": {}}
    chunks = re.split(r"\nfill\(D\.(\w+)\)\n", src)
    bodies, names = chunks[0::2], chunks[1::2]
    for body, name in zip(bodies, names):
        for m in re.finditer(r"^t\[(\d+)\]=(.*)$", body, re.M):
            data[name][int(m.group(1))] = lua_value(m.group(2))
    apply_curated(data)
    return data


def apply_curated(data) -> int:
    """Fold Data/Curated.lua over the generated data, filling gaps only.

    The same merge the addon does in Data.lua (MergeCuratedData) and the route generator does at
    load. Three copies of it is two too many, but they live in three languages reading the same
    file, and the alternative -- the linter checking guides against data the addon does not have --
    is how you get a route that passes lint and points at nothing in game. The rule is small enough
    to state in one line and is stated identically in all three: never overwrite a field a
    generated source already filled.
    """
    if not os.path.exists(CURATED):
        return 0
    applied = 0
    for m in re.finditer(r"^C\.(\w+)\[(\d+)\]\s*=\s*(.*)$", open(CURATED, encoding="utf-8").read(), re.M):
        store, eid, body = m.group(1), int(m.group(2)), m.group(3)
        if store not in data:
            continue
        entry = data[store].setdefault(eid, {})
        for k, v in (lua_value(body) or {}).items():
            if k == "c":
                if not entry.get("c"):
                    entry["c"] = v
                    applied += 1
            elif entry.get(k) is None:
                entry[k] = v
                applied += 1
    return applied


def fmt_pos(d, c, prefer=None):
    zone = d["zones"].get(c[0], str(c[0]))
    return "%s %s,%s" % (zone, c[1], c[2])


def best_coord(entity, prefer):
    coords = entity.get("c") or []
    if not coords:
        return None
    if prefer is not None:
        for c in coords:
            if c[0] == prefer:
                return c
    return coords[0]


def entity_line(d, store, eid, prefer):
    e = d[store].get(eid)
    if not e:
        return "#%d (unknown)" % eid
    c = best_coord(e, prefer)
    lvl = e.get("lvl")
    lvl = ("lvl %s-%s " % tuple(lvl)) if isinstance(lvl, list) and lvl[0] != lvl[1] else ("lvl %s " % lvl[0] if isinstance(lvl, list) else "")
    return "%s #%d %s@ %s%s" % (e.get("n", "?"), eid, lvl, fmt_pos(d, c, prefer) if c else "no position", (" (+%d more spots)" % (len(e["c"]) - 1)) if e.get("c") and len(e["c"]) > 1 else "")


def quest_card(d, qid, prefer):
    q = d["quests"].get(qid)
    if not q:
        print("quest %d: not in data" % qid)
        return
    print("== %d %s  (lvl %s, min %s%s%s)" % (qid, q.get("t"), q.get("lvl"), q.get("min"),
          (", race %d" % q["race"]) if q.get("race") else "", (", class %d" % q["class"]) if q.get("class") else ""))
    for label, key in (("from", "start"), ("to  ", "end")):
        s = q.get(key) or {}
        for nid in s.get("npcs", []):
            print("   %s npc  %s" % (label, entity_line(d, "npcs", nid, prefer)))
        for oid in s.get("objs", []):
            print("   %s obj  %s" % (label, entity_line(d, "objs", oid, prefer)))
        for iid in s.get("items", []):
            print("   %s item %s" % (label, d["items"].get(iid, {}).get("n", "#%d" % iid)))
    o = q.get("obj") or {}
    for nid in o.get("npcs", []):
        print("   kill     %s" % entity_line(d, "npcs", nid, prefer))
    for oid in o.get("objs", []):
        print("   use      %s" % entity_line(d, "objs", oid, prefer))
    for iid in o.get("items", []):
        it = d["items"].get(iid, {})
        print("   collect  %s #%d" % (it.get("n", "?"), iid))
        for src in it.get("npcs", [])[:4]:
            print("       drops from %s (%s%%)" % (entity_line(d, "npcs", src[0], prefer), src[1]))
        for src in it.get("objs", [])[:4]:
            print("       from object %s (%s%%)" % (entity_line(d, "objs", src[0], prefer), src[1]))
    for aid in o.get("areas", []):
        a = d["areas"].get(aid)
        c = best_coord(a, prefer) if a else None
        print("   explore  area #%d @ %s" % (aid, fmt_pos(d, c, prefer) if c else "?"))
    if q.get("pre"):
        print("   needs    %s" % ", ".join("%d %s" % (p, d["quests"].get(p, {}).get("t", "?")) for p in q["pre"]))
    if q.get("next"):
        print("   leads to %s" % ", ".join("%d %s" % (n, d["quests"].get(n, {}).get("t", "?")) for n in q["next"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["quest", "npc", "zone", "chain"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--zone", type=int, help="prefer positions in this area id")
    ap.add_argument("--max-level", type=int, default=99)
    ap.add_argument("--horde", action="store_true")
    ap.add_argument("--alliance", action="store_true")
    a = ap.parse_args()
    d = load()
    if a.what == "quest":
        for x in a.args:
            quest_card(d, int(x), a.zone)
    elif a.what == "npc":
        for x in a.args:
            if x.isdigit():
                print(entity_line(d, "npcs", int(x), a.zone))
            else:
                for nid, e in sorted(d["npcs"].items()):
                    if x.lower() in e.get("n", "").lower():
                        print(entity_line(d, "npcs", nid, a.zone))
    elif a.what == "zone":
        want = a.args[0]
        zone = int(want) if want.isdigit() else next((z for z, n in d["zones"].items() if n.lower() == want.lower()), None)
        rows = []
        for qid, q in d["quests"].items():
            if (q.get("lvl") or 0) > a.max_level:
                continue
            race = q.get("race") or 0
            if a.horde and race and not race & 178:
                continue
            if a.alliance and race and not race & 77:
                continue
            s = q.get("start") or {}
            pos = None
            for nid in s.get("npcs", []):
                pos = best_coord(d["npcs"].get(nid, {}), zone)
                if pos:
                    break
            if not pos:
                for oid in s.get("objs", []):
                    pos = best_coord(d["objs"].get(oid, {}), zone)
                    if pos:
                        break
            if pos and pos[0] == zone:
                rows.append((q.get("lvl") or 0, qid, q.get("t"), pos))
        for lvl, qid, t, pos in sorted(rows):
            print("lvl %2d  %5d  %-40s %s" % (lvl, qid, t, fmt_pos(d, pos)))
    elif a.what == "chain":
        seen = set()
        todo = [int(x) for x in a.args]
        while todo:
            qid = todo.pop(0)
            if qid in seen:
                continue
            seen.add(qid)
            quest_card(d, qid, a.zone)
            todo.extend(d["quests"].get(qid, {}).get("next", []))


if __name__ == "__main__":
    main()

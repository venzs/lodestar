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
ATT = os.path.join(HERE, "..", "..", "Lodestar_Guide", "Data", "ATT.lua")
FOREVER = os.path.join(HERE, "..", "..", "Lodestar_Guide", "Data", "Forever.lua")
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


def _filled_blocks(path, prefix):
    """{store: {id: value}} from a generated file's `fill(<prefix>.<store>)` chunks.

    Vanilla.lua and ATT.lua are both repeated `fill = function(t) t[id]=... end` chunks followed by
    the table they fill. The same `t[id]=` line shape is used for quests, NPCs and objects, so each
    chunk is attributed to the table it is actually filled into -- taking every id would let a
    mistyped quest id pass because some NPC happens to share the number.
    """
    out = {}
    if not os.path.exists(path):
        return out
    src = open(path, encoding="utf-8").read()
    chunks = re.split(r"\nfill\(" + re.escape(prefix) + r"\.(\w+)\)\n", src)
    for body, name in zip(chunks[0::2], chunks[1::2]):
        store = out.setdefault(name, {})
        for m in re.finditer(r"^t\[(\d+)\]=(.*)$", body, re.M):
            store[int(m.group(1))] = lua_value(m.group(2))
    return out


def _assigned_lines(path, prefix):
    """{store: {id: value}} from direct `<prefix>.<store>[id]=<value>` lines (Forever.lua's shape)."""
    out = {}
    if not os.path.exists(path):
        return out
    pat = re.compile(r"^" + re.escape(prefix) + r"\.(\w+)\[(\d+)\]=(.*)$", re.M)
    for m in pat.finditer(open(path, encoding="utf-8").read()):
        out.setdefault(m.group(1), {})[int(m.group(2))] = lua_value(m.group(3))
    return out


def apply_att(data) -> int:
    """Fold Data/ATT.lua in: gap-fill for quests, additive for positions.

    Ported field for field from Guide:MergeATTData in Lodestar_Guide/Data.lua, and it has to stay
    that way. A route planned against a different merge than the addon reads is a route that passes
    every check here and points somewhere else in game.
    """
    att = _filled_blocks(ATT, "A")
    applied = 0
    for qid, aq in (att.get("quests") or {}).items():
        q = data["quests"].setdefault(qid, {})
        for k, v in (aq or {}).items():
            if q.get(k) is None:
                q[k] = v
                applied += 1
                # Provenance for prerequisites specifically, because ATT's sourceQuests are a
                # looser notion than pfQuest's `pre` and are sometimes simply wrong: ATT claims
                # quest 46 (Bounty on Murlocs) requires 39 (Deliver Thomas' Report), when Guard
                # Thomas hands out 46 first and 39 is the follow-up you take back to Dughan. A
                # caller that treats an ATT-only prerequisite as a hard constraint will rewrite a
                # correct route to satisfy a claim nobody verified.
                if k == "pre":
                    q["preFromATT"] = True
        q["att"] = True
    for store in ("npcs", "objs"):
        for eid, ae in (att.get(store) or {}).items():
            e = data[store].setdefault(eid, {})
            # Appended, not gap-filled: ATT is dense where pfQuest is thin and the reverse, so the
            # union is the point. Vanilla's coordinates stay first, which is the order the addon
            # builds and therefore the order the arrow picks from.
            if ae and ae.get("c"):
                e["c"] = (e.get("c") or []) + list(ae["c"])
                applied += 1
    return applied


def apply_forever(data) -> int:
    """Fold Data/Forever.lua in -- the beta harvest, which outranks both generated sources.

    Ported from Guide:MergeForeverData. Quest fields overwrite rather than gap-fill: somebody
    watched this happen on this build, which beats anything inferred from a fifteen-year-old
    database. Positions are still appended, because two sightings of one NPC are both true.
    """
    fv = _assigned_lines(FOREVER, "F")
    applied = 0
    for qid, fq in (fv.get("quests") or {}).items():
        q = data["quests"].setdefault(qid, {})
        for k, v in (fq or {}).items():
            q[k] = v
            applied += 1
        q["forever"] = True
    for store in ("npcs", "objs"):
        for eid, fe in (fv.get(store) or {}).items():
            e = data[store].setdefault(eid, {})
            if not fe:
                continue
            if fe.get("n") and not e.get("n"):
                e["n"] = fe["n"]
                applied += 1
            if fe.get("lvl") and not e.get("lvl"):
                e["lvl"] = fe["lvl"]
                applied += 1
            if fe.get("kind"):
                e["kind"] = fe["kind"]
            if fe.get("c"):
                e["c"] = (e.get("c") or []) + list(fe["c"])
                applied += 1
    data["levels"] = dict(fv.get("levels") or {})
    data["taxi"] = dict(fv.get("taxi") or {})
    # Zone names for Forever's new maps, which pfQuest cannot know. Gap-fill: an established name
    # from the old database always wins, so this can only ever add a map nothing else could name.
    for mapid, name in (fv.get("zones") or {}).items():
        if mapid not in data["zones"]:
            data["zones"][mapid] = name
            applied += 1
    return applied


def _normalize_coords(data) -> int:
    """One coordinate shape for every caller: [mapID, x, y].

    pfQuest's importer writes {areaID, x, y} and ATT's and the harvest's write
    {[1]=0, [2]=x, [3]=y, m=uiMapID} -- two shapes for one fact, because the three databases were
    imported by different tools. The addon copes by testing both at every use site
    (generate_route.lua does it in three places); in Python that had simply never come up, because
    the loader only ever read pfQuest. Merging the overlays in made it come up immediately, as a
    KeyError deep inside the linter.

    Normalising once here rather than at each use site is the same reasoning as everywhere else in
    this project: the second copy of a rule is the one that ends up missing a case.
    """
    fixed = 0
    for store in ("npcs", "objs"):
        for e in data[store].values():
            coords = e.get("c")
            if not coords:
                continue
            out = []
            for c in coords:
                if isinstance(c, dict):
                    # `m` is the uiMapID; index 1 is a placeholder zero in this shape.
                    mapid = c.get("m", c.get(1))
                    if mapid is None or 2 not in c or 3 not in c:
                        continue
                    out.append([mapid, c[2], c[3]])
                    fixed += 1
                elif isinstance(c, list) and len(c) >= 3:
                    out.append(c)
            e["c"] = out
    return fixed


def load(att=True, forever=True, curated=True):
    """The world as the addon sees it: Vanilla, then ATT, then the harvest, then Curated.

    The overlays are switchable for one caller only: merge_scan.py, which GENERATES Data/Forever.lua
    and reads this to decide which harvested facts are new. Handing it its own output makes every
    fact it already ships look "already known", and it silently drops them -- the file went from
    54KB to 3KB the first time this defaulted to on. A generator must never read the file it writes.

    That order is the whole point and is the one Data.lua:EnableData applies. Reading Vanilla alone
    -- which this did until 2026-09-20 -- means every caller plans against a quarter of the
    database: no ATT giver positions, nothing any player has harvested on the beta, and no curated
    stopgaps. lint_guides.py had grown its own id-only scrapers of the two overlays to compensate.
    """
    src = open(DATA, encoding="utf-8").read()
    data = {"zones": {}, "quests": {}, "npcs": {}, "objs": {}, "items": {}, "areas": {},
            "levels": {}, "taxi": {}}
    chunks = re.split(r"\nfill\(D\.(\w+)\)\n", src)
    bodies, names = chunks[0::2], chunks[1::2]
    for body, name in zip(bodies, names):
        for m in re.finditer(r"^t\[(\d+)\]=(.*)$", body, re.M):
            data[name][int(m.group(1))] = lua_value(m.group(2))
    if att:
        apply_att(data)
    if forever:
        apply_forever(data)
    if curated:
        apply_curated(data)
    _normalize_coords(data)
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

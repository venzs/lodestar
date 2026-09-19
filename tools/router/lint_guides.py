#!/usr/bin/env python3
"""Lint the guide packs (Lodestar_Guides_*/**/*.lua) against the Vanilla database.

    python3 tools/router/lint_guides.py                 # every pack
    python3 tools/router/lint_guides.py Lodestar_Guides_Horde/Horde_Barrens.lua [--tolerance 4]

Every `Guide:RegisterGuide([[ ... ]])` block is parsed with the same directive grammar as
Lodestar_Guide/Parser.lua and checked:

  ids         every quest id in .accept / .turnin / .complete exists in one of the three databases
              the addon loads: Data/Vanilla.lua, Data/Forever.lua (the beta harvest) or Data/ATT.lua
  accept      every .accept is turned in later (same guide, or a guide down the #next chain), unless it is
              in the guide's last step
  turnin      every .turnin was accepted earlier (same guide or a guide that leads here through #next)
  complete    every .complete refers to a quest accepted earlier (same rule)
  prereqs     a quest's `pre` list (pfQuest: alternatives, ONE of them is enough) has a member turned in
              earlier in this guide or in a preceding guide; a member turned in LATER in the same guide is an
              ordering error (a warning when it is at least accepted, since pfQuest's `pre` also covers
              "while on" links), none at all is a warning (the prerequisite may live in a zone with no guide yet)
  level       a quest's min level is <= the latest .xp checkpoint before the accept (start: #levels low end)
  goto        for accept/turnin steps the .goto is on a map where the giver/ender has a position, within
              --tolerance percent units of it (an NPC with several spots: the nearest one)
  directives  unknown directives, malformed .goto / ids, a step without a goto for accept/turnin/complete

Errors exit 1; warnings are informational (a summary line lists both).
"""
from __future__ import annotations

import argparse
import glob
import importlib.util
import json
import math
import os
import re
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUERY_PY = os.path.join(ROOT, "tools", "pfquest", "query.py")

ACTION_TYPES = {
    "accept", "turnin", "complete", "xp", "level", "zone", "train", "hs", "fly", "vendor", "repair", "text",
    "goto", "class", "race", "link", "buy", "optional", "path", "profession", "camp", "cook", "item",
}
NEEDS_GOTO = {"accept", "turnin", "complete"}

# Filled once at start-up from the two generated overlays; see forever_quest_ids / att_quest_ids.
EXTRA_QUEST_IDS: set[int] = set()


def load_vanilla():
    spec = importlib.util.spec_from_file_location("pfquest_query", QUERY_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod.load()


def forever_quest_ids():
    """Quest ids the Forever overlay knows, from Data/Forever.lua's `F.quests[id]={...}` lines."""
    path = os.path.join(ROOT, "Lodestar_Guide", "Data", "Forever.lua")
    if not os.path.exists(path):
        return set()
    return {int(m) for m in re.findall(r"^F\.quests\[(\d+)\]=", open(path, encoding="utf-8").read(), re.M)}


def att_quest_ids():
    """Quest ids from Data/ATT.lua.

    The generator emits several `fill = function(t) ... end fill(<target>)` chunks, and the same
    `t[id]=` line shape is used for quests, NPCs and objects. Taking every id would let a mistyped
    quest id pass because some NPC happens to share the number, so each chunk is attributed to the
    table it is actually filled into.
    """
    path = os.path.join(ROOT, "Lodestar_Guide", "Data", "ATT.lua")
    if not os.path.exists(path):
        return set()
    ids: set[int] = set()
    chunk: list[str] = []
    for line in open(path, encoding="utf-8"):
        target = re.match(r"^fill\((\S+)\)", line)
        if target:
            if target.group(1) == "A.quests":
                ids.update(int(m) for c in chunk for m in re.findall(r"^t\[(\d+)\]=", c))
            chunk = []
        else:
            chunk.append(line)
    return ids


# --- parsing --------------------------------------------------------------------------------------------------

@dataclass
class Action:
    type: str
    line: int
    quest: int | None = None
    objective: int | None = None
    level: int | None = None
    text: str | None = None


@dataclass
class Step:
    index: int
    line: int
    goto: tuple[str, float, float] | None = None
    actions: list[Action] = field(default_factory=list)
    optional: bool = False
    classes: list[str] = field(default_factory=list)
    races: list[str] = field(default_factory=list)


@dataclass
class Guide:
    file: str
    name: str = ""
    next: str | None = None
    min_level: int = 1
    max_level: int = 60
    faction: str = "Both"
    steps: list[Step] = field(default_factory=list)
    problems: list[tuple[str, int, str]] = field(default_factory=list)   # (severity, line, message)

    def error(self, line: int, msg: str) -> None:
        self.problems.append(("error", line, msg))

    def warn(self, line: int, msg: str) -> None:
        self.problems.append(("warning", line, msg))


def split_args_text(rest: str) -> tuple[str, str | None]:
    if ">>" in rest:
        args, text = rest.split(">>", 1)
        return args.strip(), text.strip() or None
    return rest.strip(), None


def parse_guide(file: str, text: str, first_line: int) -> Guide:
    g = Guide(file=file)
    step: Step | None = None
    for i, raw in enumerate(text.split("\n")):
        line_no = first_line + i
        line = raw.strip()
        if not line or line.startswith("--") or line.startswith(";"):
            continue
        if line.startswith("#"):
            m = re.match(r"^#(\w+)\s*(.*)$", line)
            key, value = (m.group(1).lower(), m.group(2).strip()) if m else ("", "")
            if key in ("guide", "name"):
                g.name = value
            elif key == "next":
                # "#next Horde: <guide>" chains per faction for a neutral race; the qualified form
                # is not the unconditional successor, so it must not overwrite it.
                mf = re.match(r"^(Horde|Alliance)\s*:\s*(.+)$", value, re.I)
                if not mf:
                    g.next = value
            elif key == "faction":
                g.faction = value.capitalize()
            elif key in ("levels", "level"):
                m2 = re.match(r"(\d+)\s*-\s*(\d+)", value)
                if m2:
                    g.min_level, g.max_level = int(m2.group(1)), int(m2.group(2))
            continue
        if re.match(r"^step\b", line, re.I):
            step = Step(index=len(g.steps) + 1, line=line_no)
            g.steps.append(step)
            continue
        if line.startswith("."):
            if step is None:
                g.error(line_no, "directive before the first step")
                continue
            m = re.match(r"^\.(\w+)\s*(.*)$", line)
            directive = (m.group(1) if m else "").lower()
            rest = m.group(2) if m else ""
            if directive not in ACTION_TYPES:
                g.error(line_no, f"unknown directive .{directive}")
                continue
            args, label = split_args_text(rest)
            if directive == "goto":
                parts = [p.strip() for p in args.split(",")]
                if len(parts) < 3:
                    g.error(line_no, "goto needs map,x,y")
                    continue
                try:
                    step.goto = (parts[0], float(parts[1]), float(parts[2]))
                except ValueError:
                    g.error(line_no, "goto coordinates must be numbers")
            elif directive == "optional":
                step.optional = True
            elif directive == "class":
                step.classes = [p.strip() for p in args.split(",") if p.strip()]
            elif directive == "race":
                step.races = [p.strip() for p in args.split(",") if p.strip()]
            elif directive in ("accept", "turnin"):
                ids = [p.strip() for p in args.split(",") if p.strip()]
                if not ids:
                    g.error(line_no, f"{directive} needs a quest id")
                for s in ids:
                    if not s.isdigit():
                        g.error(line_no, f"{directive}: bad quest id {s}")
                        continue
                    step.actions.append(Action(directive, line_no, quest=int(s), text=label))
            elif directive == "complete":
                parts = [p.strip() for p in args.split(",") if p.strip()]
                if not parts or not parts[0].isdigit():
                    g.error(line_no, "complete needs a quest id")
                    continue
                obj = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None
                step.actions.append(Action("complete", line_no, quest=int(parts[0]), objective=obj, text=label))
            elif directive in ("xp", "level"):
                m3 = re.match(r"^(\d+)", args)
                if not m3:
                    g.error(line_no, "xp needs a level")
                    continue
                step.actions.append(Action("level", line_no, level=int(m3.group(1)), text=label))
            elif directive == "buy":
                parts = [p.strip() for p in args.split(",") if p.strip()]
                if not parts or not parts[0].isdigit():
                    g.error(line_no, "buy needs an item id")
            elif directive == "path":
                for pair in args.split(";"):
                    if not re.match(r"^\s*-?[\d.]+\s*,\s*-?[\d.]+\s*$", pair):
                        g.error(line_no, "path points must be x,y pairs separated by ;")
                        break
            else:
                step.actions.append(Action(directive, line_no, text=label))
            continue
        g.error(line_no, f"unrecognised line: {line}")
    if not g.name:
        g.error(first_line, "guide has no #guide name")
    if not g.steps:
        g.error(first_line, "guide has no steps")
    return g


def guides_in_file(path: str) -> list[Guide]:
    src = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"RegisterGuide\(\s*\[\[(.*?)\]\]", src, re.S):
        first_line = src.count("\n", 0, m.start(1)) + 1
        out.append(parse_guide(path, m.group(1), first_line))
    return out


# --- checks -----------------------------------------------------------------------------------------------------

def npc_positions(data, quest: dict, key: str) -> list[tuple[str, float, float, str]]:
    """(zone name, x, y, npc name) for every position of the quest's start/end npcs and objects."""
    out = []
    s = quest.get(key) or {}
    for store, ids in (("npcs", s.get("npcs") or []), ("objs", s.get("objs") or [])):
        for eid in ids:
            e = data[store].get(eid) or {}
            for c in e.get("c") or []:
                out.append((data["zones"].get(c[0], str(c[0])), float(c[1]), float(c[2]), e.get("n", f"#{eid}")))
    return out


def route_shape(g: Guide) -> dict:
    """How far this route walks, and how much of that is doubling back.

    Everything else here proves a route is VALID -- right order, right positions, right levels, the
    right faction's NPCs. None of it says whether the route is any good to play. A guide that sends
    you to the far corner of Ashenvale, back to the entrance, and out to the same corner again
    passes every check in this file.

    Distance is in map percent, which is the unit the .goto coordinates are already in. It is not
    yards and does not convert to them -- a percent of Durotar is a different distance from a
    percent of Elwynn -- so the number is only meaningful compared against other routes for the
    SAME zone, or against the same route before and after a change. That is exactly the comparison
    that matters when the generator changes.

    Backtracking is the honest signal and it is comparable across zones: of all the ground the route
    covers, how much is spent returning to somewhere it has already been. A perfectly efficient
    circuit is 0; walking out and back for every quest approaches 1.
    """
    points = [st.goto for st in g.steps if st.goto]
    if len(points) < 2:
        return {"travel": 0.0, "hops": 0, "backtrack": 0.0, "longest": 0.0}
    hops = [math.hypot(b[1] - a[1], b[2] - a[2]) for a, b in zip(points, points[1:])]
    travel = sum(hops)
    # "Near enough to be the same place" has to scale with the route, or the measure just reports
    # density. A fixed two percent is about one camp in Durotar and about a third of Zephras Isle,
    # so a compact starting zone scored 73% backtracking for ordinary hub-and-spoke questing while a
    # sprawling one scored well for genuinely walking back and forth. A quarter of the typical hop
    # is the same idea expressed in the route's own units.
    ordered = sorted(h for h in hops if h > 0)
    median_hop = ordered[len(ordered) // 2] if ordered else 0.0
    radius = max(1.0, median_hop * 0.25)
    back = 0.0
    visited: list[tuple[float, float]] = [(points[0][1], points[0][2])]
    for (_, _, _), (_, x2, y2), d in zip(points, points[1:], hops):
        if any(math.hypot(x2 - vx, y2 - vy) < radius for vx, vy in visited[:-1]):
            back += d
        visited.append((x2, y2))
    return {"travel": travel, "hops": len(hops), "backtrack": back / travel if travel else 0.0,
            "longest": max(hops), "radius": radius}


def check_faction(g: Guide, data, action, quest: dict, key: str, verb: str) -> None:
    """A route must never send a player to an NPC of the other faction.

    In a contested zone the faction split is expressed by who stands there, not by a flag on the
    quest: most Ashenvale quests carry no race restriction at all, and the difference between the
    Alliance and Horde routes is entirely which camp gives them out. A generated "Alliance"
    Ashenvale route once contained 22 quests taken from Horde NPCs -- Je'neu Sancrea at Zoram'gar,
    the Warsong Lumber Camp chain, Senani Thunderheart at Splintertree -- and passed every check
    there was, because none of them looked at the NPC.

    An NPC with no recorded faction is accepted: most of the three and a half thousand of them are
    ordinary neutral givers, and failing closed would empty the routes.
    """
    if g.faction not in ("Alliance", "Horde"):
        return
    wrong = "H" if g.faction == "Alliance" else "A"
    s = quest.get(key) or {}
    ids = s.get("npcs") or []
    if not ids:
        return
    # A quest offered in every capital lists one NPC per city, so a wrong-faction name in the list
    # is normal. It is only an error when NONE of them will talk to this faction.
    usable = [e for e in (data["npcs"].get(i) or {} for i in ids) if e.get("f") != wrong]
    if usable:
        return
    first = data["npcs"].get(ids[0]) or {}
    other = "Horde" if wrong == "H" else "Alliance"
    g.error(action.line, "%s %d (%s): every NPC who %ss it is %s-only (%s) in a %s guide"
            % ("accept" if verb == "take" else "turnin", action.quest, quest.get("t", "?"),
               "give" if verb == "take" else "take", other,
               first.get("n", "#%d" % ids[0]), g.faction))


def check_guide(g: Guide, data, before_accepted: set[int], before_turned: set[int], later_turned: set[int],
                tolerance: float) -> None:
    quests = data["quests"]
    accepted: set[int] = set(before_accepted)
    turned: set[int] = set(before_turned)
    accept_line: dict[int, int] = {}
    accept_filters: dict[int, list[tuple[set[str], set[str]]]] = {}   # (classes, races) of the steps that accepted a quest
    turnin_step: dict[int, int] = {}
    level = g.min_level
    last_step = len(g.steps)
    # first pass: where each quest is turned in (for ordering checks)
    for st in g.steps:
        for a in st.actions:
            if a.type == "turnin" and a.quest is not None and a.quest not in turnin_step:
                turnin_step[a.quest] = st.index
    for st in g.steps:
        # An accept or a turn-in without a position is an authoring mistake: there is a specific NPC
        # to stand in front of. A step that only says "complete this" may legitimately have nowhere
        # to point -- a generated route emits one whenever the objective's location is unknown, and
        # inventing coordinates there would be worse than leaving the arrow alone.
        if st.goto is None:
            hard = any(a.type in ("accept", "turnin") for a in st.actions)
            # An optional step made only of turn-ins is the one honest exception: a breadcrumb taken
            # in this zone and handed in somewhere else has no position HERE, and the giver's spot
            # -- the only coordinate to hand -- is not where the ender stands. Pointing the arrow at
            # it would be a confident lie, so the route says "handed in outside this zone" instead
            # and names the NPC. Requiring a .goto here would force exactly the bug it exists to
            # prevent.
            elsewhere = st.optional and st.actions and all(a.type == "turnin" for a in st.actions)
            if hard and not elsewhere:
                g.error(st.line, "step with accept/turnin has no .goto")
            elif any(a.type == "complete" for a in st.actions):
                g.warn(st.line, "complete step has no .goto -- the arrow has nothing to point at")
        for a in st.actions:
            if a.type == "level":
                level = max(level, a.level or level)
                continue
            if a.quest is None:
                continue
            q = quests.get(a.quest)
            if q is None:
                # Forever's own quests are not in the Vanilla database at all; they come from the
                # harvest and from ATT. Known there but not here means no title or position to check
                # against, which is a gap in what we can verify, not a bad id.
                if a.quest in EXTRA_QUEST_IDS:
                    continue
                g.error(a.line, f".{a.type} {a.quest}: quest id in no database (Vanilla, Forever or ATT)")
                continue
            title = q.get("t", "?")
            if a.type == "accept":
                mine = ({c.lower() for c in st.classes}, {r.lower() for r in st.races})
                if a.quest in accepted and a.quest not in turned:
                    # the same quest in .class/.race-restricted steps for different players is one accept each
                    def overlaps(a_f, b_f):
                        for x, y in zip(a_f, b_f):
                            if x and y and not (x & y):
                                return False
                        return True
                    if any(overlaps(mine, prev) for prev in accept_filters.get(a.quest, [])):
                        g.warn(a.line, f"accept {a.quest} ({title}): already accepted")
                accepted.add(a.quest)
                accept_line[a.quest] = a.line
                accept_filters.setdefault(a.quest, []).append(mine)
                qmin = int(q.get("min") or 1)
                if qmin > level:
                    g.error(a.line, f"accept {a.quest} ({title}): min level {qmin} but the latest .xp checkpoint is {level}")
                pre = q.get("pre") or []
                if pre:
                    if not any(p in turned for p in pre):
                        later = [p for p in pre if turnin_step.get(p, 0) > st.index]
                        in_progress = [p for p in later if p in accepted]
                        if in_progress:
                            # pfQuest's `pre` also covers "started by / while on" links (Proving Allegiance's candle
                            # sub-quests): the prerequisite is in the log, so only warn
                            g.warn(a.line, f"accept {a.quest} ({title}): prerequisite {in_progress[0]} ({quests.get(in_progress[0], {}).get('t', '?')}) is only in progress here (turned in later)")
                        elif later:
                            g.error(a.line, f"accept {a.quest} ({title}): prerequisite {later[0]} ({quests.get(later[0], {}).get('t', '?')}) is turned in later in this guide")
                        else:
                            names = ", ".join(f"{p} {quests.get(p, {}).get('t', '?')}" for p in pre)
                            g.warn(a.line, f"accept {a.quest} ({title}): none of its prerequisites is turned in by this or a preceding guide ({names})")
                if st.index != last_step and a.quest not in turnin_step and a.quest not in later_turned:
                    g.warn(a.line, f"accept {a.quest} ({title}): never turned in (this guide or the #next chain)")
                if st.goto:
                    check_goto(g, a, st, npc_positions(data, q, "start"), tolerance, "giver")
                    check_faction(g, data, a, q, "start", "take")
            elif a.type == "turnin":
                if a.quest not in accepted:
                    g.error(a.line, f"turnin {a.quest} ({title}): not accepted earlier (this guide or a preceding one)")
                turned.add(a.quest)
                if st.goto:
                    check_goto(g, a, st, npc_positions(data, q, "end"), tolerance, "ender")
                    check_faction(g, data, a, q, "end", "hand")
            elif a.type == "complete":
                if a.quest not in accepted:
                    g.error(a.line, f"complete {a.quest} ({title}): not accepted earlier")
                elif a.quest in turned and turnin_step.get(a.quest, 10**9) < st.index:
                    g.error(a.line, f"complete {a.quest} ({title}): after its turn-in")


def check_goto(g: Guide, a: Action, st: Step, positions, tolerance: float, what: str) -> None:
    if not positions:
        g.warn(a.line, f".{a.type} {a.quest}: the {what} has no position in the data")
        return
    zone, x, y = st.goto  # type: ignore[misc]
    same_zone = [p for p in positions if p[0].lower() == zone.lower()]
    if not same_zone:
        zones = sorted({p[0] for p in positions})
        g.warn(a.line, f".{a.type} {a.quest}: goto is on {zone} but the {what} ({positions[0][3]}) stands in {', '.join(zones)}")
        return
    best = min(same_zone, key=lambda p: math.hypot(p[1] - x, p[2] - y))
    d = math.hypot(best[1] - x, best[2] - y)
    if d > tolerance:
        g.error(a.line, f".{a.type} {a.quest}: goto {x:.1f},{y:.1f} is {d:.1f} map units from {best[3]} at {best[1]},{best[2]} ({what})")


def lint(paths: list[str], tolerance: float, record_shape: bool = False) -> tuple[int, int]:
    data = load_vanilla()
    guides: list[Guide] = []
    for p in paths:
        guides += guides_in_file(p)
    by_name = {g.name: g for g in guides}
    # predecessors through #next (transitive)
    preds: dict[str, set[str]] = {g.name: set() for g in guides}
    for g in guides:
        if g.next and g.next in preds:
            preds[g.next].add(g.name)
    changed = True
    while changed:
        changed = False
        for name, ps in preds.items():
            for p in list(ps):
                for pp in preds.get(p, ()):
                    if pp not in ps:
                        ps.add(pp)
                        changed = True
    for g in guides:
        if g.next and g.next not in by_name:
            g.warn(0, f"#next '{g.next}' is not a guide in the packs (yet)")

    def quests_of(g: Guide, kind: str) -> set[int]:
        return {a.quest for st in g.steps for a in st.actions if a.type == kind and a.quest is not None}

    succ: dict[str, set[str]] = {g.name: set() for g in guides}
    for name, ps in preds.items():
        for p in ps:
            succ[p].add(name)
    for g in guides:
        before_acc = set().union(*(quests_of(by_name[p], "accept") for p in preds[g.name])) if preds[g.name] else set()
        before_turn = set().union(*(quests_of(by_name[p], "turnin") for p in preds[g.name])) if preds[g.name] else set()
        later = set().union(*(quests_of(by_name[s], "turnin") for s in succ[g.name])) if succ[g.name] else set()
        check_guide(g, data, before_acc, before_turn, later, tolerance)
    errors = warnings = 0
    shapes: dict[str, dict] = {}
    for g in guides:
        for sev, line, msg in sorted(g.problems, key=lambda p: p[1]):
            print(f"{g.file}:{line}: {sev}: {msg}")
            if sev == "error":
                errors += 1
            else:
                warnings += 1
        n_quests = len(quests_of(g, "accept"))
        shape = route_shape(g)
        print(f"{g.file}: {g.name!r}: {len(g.steps)} steps, {n_quests} quests accepted, "
              f"{len(quests_of(g, 'turnin'))} turned in, "
              f"travel {shape['travel']:.0f}%/{shape['hops']} hops, "
              f"{shape['backtrack'] * 100:.0f}% backtracking, longest hop {shape['longest']:.0f}%")
        shapes[g.name] = {k: round(v, 3) for k, v in shape.items()}
    # Route quality is judged against this route's own past, not against a number somebody picked.
    #
    # There is no defensible absolute threshold: the hand-written guides -- the ones a person walked
    # and was happy with -- range from 28% to 64% backtracking, so any line drawn through that is
    # taste dressed up as a rule. What IS meaningful is a route getting worse than it was, which is
    # exactly what happens when a change to the generator has an effect nobody intended. The
    # baseline is committed; `--record-shape` updates it deliberately.
    baseline_path = os.path.join(ROOT, "docs", "route-shape.json")
    if record_shape:
        os.makedirs(os.path.dirname(baseline_path), exist_ok=True)
        with open(baseline_path, "w", encoding="utf-8") as fh:
            json.dump(shapes, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print(f"route shape: recorded {len(shapes)} routes to docs/route-shape.json")
    elif os.path.exists(baseline_path):
        with open(baseline_path, encoding="utf-8") as fh:
            base = json.load(fh)
        regressed = 0
        for name, now in sorted(shapes.items()):
            was = base.get(name)
            if not was:
                print(f"route shape: {name!r} is new (travel {now['travel']:.0f}%, "
                      f"{now['backtrack'] * 100:.0f}% backtracking)")
                continue
            # 10%: below that is noise from a quest moving one step in the order.
            for key, label in (("travel", "walks"), ("backtrack", "doubles back")):
                old, new = was.get(key, 0), now.get(key, 0)
                if old > 0 and new > old * 1.10:
                    regressed += 1
                    print(f"route shape: {name!r} now {label} {new / old:.2f}x what it did "
                          f"({old:.2f} -> {new:.2f}) -- a generator change made this route worse")
        if regressed:
            print(f"route shape: {regressed} regression(s); rerun with --record-shape if intended")
    print(f"lint: {len(guides)} guides, {errors} errors, {warnings} warnings")
    return errors, warnings


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="lint guide packs against the Vanilla database")
    ap.add_argument("files", nargs="*", help="guide .lua files (default: every Lodestar_Guides_*/**/*.lua)")
    ap.add_argument("--tolerance", type=float, default=4.0, help="max distance (map percent units) between a .goto and the giver/ender")
    ap.add_argument("--record-shape", action="store_true",
                    help="rewrite docs/route-shape.json from the current routes, accepting them as the new baseline")
    args = ap.parse_args(argv)
    # Forever's own quests live in the two generated overlays, not in the Vanilla database.
    EXTRA_QUEST_IDS.update(forever_quest_ids())
    EXTRA_QUEST_IDS.update(att_quest_ids())
    paths = args.files or sorted(glob.glob(os.path.join(ROOT, "Lodestar_Guides_*", "**", "*.lua"), recursive=True))
    errors, _ = lint(paths, args.tolerance, args.record_shape)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

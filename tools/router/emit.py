"""Write a plan in the Lodestar guide text format (Lodestar_Guide/Parser.lua).

Mirrors Recorder.lua's export: one `step`, an optional `.goto map,x,y[,radius]`, turn-ins before
accepts, one directive per quest with a `>>label`, and `-- comments` carrying the simulator's numbers
so a human can see why a step is where it is.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from .model import Catalog, Step, StepKind


@dataclass
class GuideHeader:
    name: str
    faction: str = "Both"
    races: list[str] = field(default_factory=list)
    classes: list[str] = field(default_factory=list)
    levels: tuple[int, int] = (1, 1)
    next: Optional[str] = None
    author: str = "Lodestar router"
    note: Optional[str] = None


def _mmss(seconds: float) -> str:
    s = int(round(seconds))
    return f"{s // 60}:{s % 60:02d}"


def hub_actions(s: Step) -> list[tuple[str, int]]:
    """Turn-ins before accepts (how you play a hub), except where the planner recorded that an accept had
    to precede a turn-in in the same visit (a hand-off quest taken and handed in at the same spot)."""
    if s.order:
        kept = {("turnin", q) for q in s.turnins} | {("accept", q) for q in s.accepts}
        ordered = [a for a in s.order if a in kept]
        # stable partition: pull turn-ins forward unless an accept of the same quest precedes them
        out: list[tuple[str, int]] = []
        for a in ordered:
            if a[0] == "turnin" and ("accept", a[1]) not in ordered[:ordered.index(a)]:
                out.append(a)
        for a in ordered:
            if a not in out:
                out.append(a)
        return out
    return [("turnin", q) for q in s.turnins] + [("accept", q) for q in s.accepts]


def _goto(step: Step, radius: Optional[float] = None, names: Optional[dict[int, str]] = None) -> Optional[str]:
    """`.goto <map>,x,y[,radius]`; the map is written as its zone name when the catalog knows one (the
    parser accepts either a uiMapID or a name, and names survive uiMapID changes between builds)."""
    if not step.goto:
        return None
    r = f",{int(radius)}" if radius else ""
    where = (names or {}).get(step.goto.map, step.goto.map)
    return f"  .goto {where},{step.goto.x:.1f},{step.goto.y:.1f}{r}"


def emit(header: GuideHeader, steps: list[Step], cat: Catalog, with_sim_comments: bool = True) -> str:
    out = [f"#guide {header.name}", f"#faction {header.faction}"]
    if header.races:
        out.append("#race " + ",".join(header.races))
    if header.classes:
        out.append("#class " + ",".join(header.classes))
    out.append(f"#levels {header.levels[0]}-{header.levels[1]}")
    if header.next:
        out.append(f"#next {header.next}")
    out.append(f"#author {header.author}")
    if header.note:
        out.append(f"#note {header.note}")
    out.append("")

    last_level = None
    names = cat.zone_map_names
    for s in steps:
        lines = ["step"]
        if s.classes:
            lines.append("  .class " + ",".join(s.classes))
        if s.kind == StepKind.HUB:
            g = _goto(s, names=names)
            if g: lines.append(g)
            for kind, qid in hub_actions(s):
                q = cat.quests[qid]
                if kind == "turnin":
                    lines.append(f"  .turnin {qid} >>Turn in {q.name}")
                else:
                    giver = cat.npcs[q.giver].name if q.giver in cat.npcs else "?"
                    lines.append(f"  .accept {qid} >>Accept {q.name} from {giver}   -- quest lvl {q.level}")
        elif s.kind == StepKind.OBJECTIVE:
            g = _goto(s, names=names)
            if g: lines.append(g)
            for qid, idx in s.completes:
                q = cat.quests[qid]
                o = next(o for o in q.objectives if o.index == idx)
                lvl = ""
                if o.mob_level_min is not None:
                    lvl = f" (lvl {o.mob_level_min}-{o.mob_level_max})" if o.mob_level_min != o.mob_level_max else f" (lvl {o.mob_level_min})"
                lines.append(f"  .complete {qid},{idx} >>{o.text}{lvl}")
        elif s.kind == StepKind.GRIND:
            g = _goto(s, radius=40, names=names)
            if g: lines.append(g)
            lines.append(f"  .xp {s.level_gate} >>{s.text}")
        elif s.kind == StepKind.TRAVEL:
            g = _goto(s, radius=30, names=names)
            if g: lines.append(g + (f" >>{s.text}" if s.text else ""))
        elif s.kind == StepKind.FLY:
            g = _goto(s, names=names)
            if g: lines.append(g)
            lines.append(f"  .fly {s.name} >>{s.text or ('Fly to ' + str(s.name))}")
        elif s.kind == StepKind.HEARTH_BIND:
            g = _goto(s, names=names)
            if g: lines.append(g)
            lines.append(f"  .hs {s.name} >>{s.text or ('Set your hearthstone at ' + str(s.name))}")
        elif s.kind == StepKind.TRAIN:
            g = _goto(s, names=names)
            if g: lines.append(g)
            lines.append(f"  .train >>{s.text or 'Train new skills'}")
        elif s.kind == StepKind.ZONE:
            lines.append(f"  .zone {s.zone} >>{s.text or ('Go to ' + str(s.zone))}")
        if with_sim_comments:
            parts = [f"t {_mmss(s.sim_t_start)}-{_mmss(s.sim_t_end)}"]
            if s.sim_level != last_level:
                parts.append(f"level {s.sim_level}")
                last_level = s.sim_level
            if s.sim_xp_gained:
                parts.append(f"+{s.sim_xp_gained} xp")
            if s.comment:
                parts.append(s.comment)
            lines.append("  -- " + ", ".join(parts))
        out.extend(lines)
        out.append("")
    return "\n".join(out).rstrip() + "\n"

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


def _goto(step: Step, radius: Optional[float] = None) -> Optional[str]:
    if not step.goto:
        return None
    r = f",{int(radius)}" if radius else ""
    return f"  .goto {step.goto.map},{step.goto.x:.1f},{step.goto.y:.1f}{r}"


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
    for s in steps:
        lines = ["step"]
        if s.classes:
            lines.append("  .class " + ",".join(s.classes))
        if s.kind == StepKind.HUB:
            g = _goto(s)
            if g: lines.append(g)
            for qid in s.turnins:
                q = cat.quests[qid]
                lines.append(f"  .turnin {qid} >>Turn in {q.name}")
            for qid in s.accepts:
                q = cat.quests[qid]
                giver = cat.npcs[q.giver].name if q.giver in cat.npcs else "?"
                lines.append(f"  .accept {qid} >>Accept {q.name} from {giver}   -- quest lvl {q.level}")
        elif s.kind == StepKind.OBJECTIVE:
            g = _goto(s)
            if g: lines.append(g)
            for qid, idx in s.completes:
                q = cat.quests[qid]
                o = next(o for o in q.objectives if o.index == idx)
                lvl = ""
                if o.mob_level_min is not None:
                    lvl = f" (lvl {o.mob_level_min}-{o.mob_level_max})" if o.mob_level_min != o.mob_level_max else f" (lvl {o.mob_level_min})"
                lines.append(f"  .complete {qid},{idx} >>{o.text}{lvl}")
        elif s.kind == StepKind.GRIND:
            g = _goto(s, radius=40)
            if g: lines.append(g)
            lines.append(f"  .xp {s.level_gate} >>{s.text}")
        elif s.kind == StepKind.TRAVEL:
            g = _goto(s, radius=30)
            if g: lines.append(g + (f" >>{s.text}" if s.text else ""))
        elif s.kind == StepKind.FLY:
            g = _goto(s)
            if g: lines.append(g)
            lines.append(f"  .fly {s.name} >>{s.text or ('Fly to ' + str(s.name))}")
        elif s.kind == StepKind.HEARTH_BIND:
            g = _goto(s)
            if g: lines.append(g)
            lines.append(f"  .hs {s.name} >>{s.text or ('Set your hearthstone at ' + str(s.name))}")
        elif s.kind == StepKind.TRAIN:
            g = _goto(s)
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

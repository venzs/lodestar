"""Invariants a plan must satisfy, checked by replaying it through the simulator.

replay() is also the "second pass": after pruning, every step's sim_* fields are recomputed so the
comments in the emitted guide reflect the final route, and the total time is the number to compare
against a recorded lap.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .cost import MAX_ABOVE, CostModel, difficulty
from .emit import hub_actions
from .model import Catalog, ObjKind, Step, StepKind
from .sim import QUEST_LOG_CAP, PlayerState, do_objective, grind_until, travel
from .world import World, travel_options


@dataclass
class Report:
    issues: list[str] = field(default_factory=list)
    total_seconds: float = 0.0
    final_level: int = 0
    xp_per_minute: float = 0.0

    def ok(self) -> bool:
        return not self.issues


def replay(steps: list[Step], cat: Catalog, world: World, cm: CostModel, start: PlayerState) -> Report:
    st = start.clone()
    rep = Report()
    seen_accept: set[int] = set()
    t0 = st.t
    for i, s in enumerate(steps, 1):
        s.sim_t_start = st.t
        s.sim_level = st.level
        xp_before = st.total_xp
        if s.goto is not None:
            opt = travel_options(world, cat, st, s.goto)[0]
            travel(st, world, s.goto, opt.seconds, opt.kind, opt.via)
            if s.kind == StepKind.TRAVEL and opt.kind != "hearth" and s.text and s.text.startswith("Use your Hearthstone"):
                rep.issues.append(f"step {i}: hearth planned but cooldown not ready at t={st.t:.0f}s")
        if s.kind == StepKind.HUB:
            for kind, qid in hub_actions(s):   # the exact order the guide text will show
                q = cat.quests[qid]
                if kind == "turnin":
                    if not st.can_turnin(q):
                        rep.issues.append(f"step {i}: turn-in {qid} ({q.name}) before it is complete/accepted")
                        continue
                    st.turnin(q); st.t += 4
                else:
                    if not st.can_accept(q):
                        why = "prereqs" if any(p not in st.turned_in for p in q.prereqs) else "min level/log/class"
                        rep.issues.append(f"step {i}: accept {qid} ({q.name}) not possible ({why}, level {st.level})")
                        continue
                    st.accept(q); st.t += 3
                    seen_accept.add(qid)
                    if st.log_size() > QUEST_LOG_CAP:
                        rep.issues.append(f"step {i}: quest log over capacity ({st.log_size()})")
        elif s.kind == StepKind.OBJECTIVE:
            for qid, idx in s.completes:
                q = cat.quests[qid]
                o = next(o for o in q.objectives if o.index == idx)
                if qid not in st.accepted:
                    rep.issues.append(f"step {i}: objective {qid},{idx} before accept")
                    continue
                d = difficulty(o, q.level)
                if d > st.level + MAX_ABOVE:
                    rep.issues.append(f"step {i}: objective {qid},{idx} is {d - st.level} levels above the player (level {st.level})")
                do_objective(st, cat, cm, o)
        elif s.kind == StepKind.GRIND:
            if s.level_gate is None:
                rep.issues.append(f"step {i}: grind step without .xp")
            else:
                spot = min(cat.grind_spots, key=lambda g: world.yards(g.pos, s.goto)) if cat.grind_spots and s.goto else None
                if spot is None:
                    rep.issues.append(f"step {i}: grind step with no known spot")
                else:
                    mob = min(max(spot.mob_level_min, st.level - 1), spot.mob_level_max)
                    secs, _ = grind_until(st, cm, mob, spot.density, s.level_gate)
                    if secs == float("inf"):
                        rep.issues.append(f"step {i}: grind spot is grey at level {st.level}")
        elif s.kind == StepKind.FLY:
            if s.name not in st.known_flights:
                # walking to the flight master discovers it
                st.known_flights.add(s.name or "")
        elif s.kind == StepKind.HEARTH_BIND:
            inn = next((n for n in cat.npcs.values() if n.name == s.name), None)
            st.bound_inn, st.bound_inn_pos = s.name, inn.pos if inn else s.goto
        s.sim_t_end = st.t
        s.sim_xp_gained = st.total_xp - xp_before
    # every accepted quest should be turned in or be a breadcrumb
    planned_turnins = {q for s in steps for q in s.turnins}
    for qid in seen_accept - planned_turnins:
        if not cat.quests[qid].breadcrumb:
            rep.issues.append(f"quest {qid} ({cat.quests[qid].name}) accepted but never turned in")
    rep.total_seconds = st.t - t0
    rep.final_level = st.level
    rep.xp_per_minute = (st.total_xp - start.total_xp) / max(1.0, rep.total_seconds) * 60
    return rep

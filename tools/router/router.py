"""The planner.

Problem shape: minimise simulated time to reach a target level while visiting quest givers/turn-ins
(hubs) and objective sites, subject to precedence (accept < complete < turn-in, chain prereqs),
level feasibility (objective difficulty <= level+2), quest-log capacity, hearthstone cooldown and
flight-path discovery. That is a quota prize-collecting TSP / orienteering problem with
time-dependent (level-dependent) profits and precedence - NP-hard, but the instances are small
(a zone has 5-15 hubs and 30-80 objectives) and a strong heuristic is what human authors do anyway:

  cluster-first (hubs), route-second (excursions), scored by simulated XP per minute, rolling horizon.

Loop (rolling-horizon greedy over *bundles*, not single jobs, so zero-reward accepts/objectives are
priced by the turn-in they enable):

  while level < target:
      visit_hub(here):   turn in everything complete; accept everything acceptable and plausibly
                         useful (liberal - pruned afterwards); bind / train / note flight master
      bundles = for each hub H (incl. here):
                    S = feasible objectives of accepted quests whose turn-in is at H
                    S += any other feasible accepted objective insertable into the tour for <= detour_budget
                    tour = NN + 2-opt + Or-opt over the sites of S (start = here, end = H)
                    simulate -> (seconds, xp, unlocked_value_at_H, band_penalty)
                    seconds += comeback charge (extra travel forced later by work left on this side)
                    score = (xp + gamma*unlocked) * penalty / seconds
                + pickup-only / turn-in-only trips to hubs (no sites)
      if no bundle, or best.score < grind_rate * grind_tolerance   (stall-breaker):
          grind one level at the best reachable spot within +/-1 of the player; re-evaluate
      else apply best (emit travel/objective steps), continue
  prune accepts never turned in (except breadcrumbs), merge grinds, second pass without the pruned
  quests, replay for final timings + invariants, emit.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

from . import xp as XP
from .cost import CostModel, band_penalty, difficulty, feasible
from .model import Catalog, GrindSpot, Hub, MapPos, Objective, ObjKind, Quest, Step, StepKind
from .sim import PlayerState, do_objective, grind_until, travel
from .world import World, travel_options


@dataclass
class PlannerConfig:
    target_level: int = 6
    hub_radius: float = 40.0          # yards; NPCs within this of a hub centre join it (Recorder uses 20 yd + 3 min)
    detour_budget: float = 45.0       # seconds; extra objectives are folded into a tour if they cost <= this
    gamma: float = 0.5                # discount on XP unlocked (newly acceptable) at the end hub
    grind_tolerance: float = 0.35     # stall-breaker: grind only if best bundle xp/s < grind xp/s * this
    accept_ahead_levels: int = 3      # accept quests whose difficulty <= level + this (we level while out)
    home_hub_quests: int = 3          # bind hearth at an inn hub that is the turn-in for >= this many accepted quests
    rebind_min_yards: float = 1500.0
    max_iterations: int = 400
    site_merge_yards: float = 120.0   # objectives sharing mobs within this distance are one visit (kills overlap)
    colocate_yards: float = 35.0      # objectives this close are one step even with different mobs (times add)
    village_seconds: float = 25.0     # neighbouring hubs within this run time are swept in one pickup pass


# --- hubs ---------------------------------------------------------------------------------------------

def cluster_hubs(cat: Catalog, world: World, radius: float) -> tuple[list[Hub], dict[int, int]]:
    """Greedy single-linkage clustering of NPC positions (quest givers, turn-ins, services)."""
    hubs: list[Hub] = []
    npc_hub: dict[int, int] = {}
    for npc in sorted(cat.npcs.values(), key=lambda n: n.id):
        placed = False
        for h in hubs:
            if world.yards(h.center, npc.pos) <= radius:
                h.npc_ids.append(npc.id)
                h.services |= npc.roles
                npc_hub[npc.id] = h.id
                placed = True
                break
        if not placed:
            h = Hub(id=len(hubs), name=npc.name, center=npc.pos, npc_ids=[npc.id], services=set(npc.roles))
            hubs.append(h)
            npc_hub[npc.id] = h.id
    for h in hubs:   # centroid, name = first quest giver
        xs = [cat.npcs[i].pos.x for i in h.npc_ids]
        ys = [cat.npcs[i].pos.y for i in h.npc_ids]
        h.center = MapPos(h.center.map, sum(xs) / len(xs), sum(ys) / len(ys))
    return hubs, npc_hub


# --- sites (objective visits) ---------------------------------------------------------------------------

@dataclass
class Site:
    pos: MapPos
    objectives: list[Objective]

    def key(self):
        return tuple(sorted(o.uid() for o in self.objectives))


def build_sites(objs: list[Objective], world: World, origin: MapPos, merge_yards: float, colocate_yards: float = 35.0) -> list[Site]:
    """One site per objective (nearest POI to the origin). Objectives join an existing site when they
    share mobs within merge_yards (kills overlap: one pack serves both) or simply stand within
    colocate_yards of it (one step, times add)."""
    sites: list[Site] = []
    for o in objs:
        if not o.pois:
            continue
        pos = min(o.pois, key=lambda p: world.yards(origin, p))
        merged = False
        for s in sites:
            d = world.yards(s.pos, pos)
            shares = o.mob_ids and any(set(o.mob_ids) & set(x.mob_ids) for x in s.objectives)
            if (shares and d <= merge_yards) or d <= colocate_yards:
                s.objectives.append(o)
                merged = True
                break
        if not merged:
            sites.append(Site(pos, [o]))
    return sites


def mob_groups(site: Site) -> list[list[Objective]]:
    """Partition a site's objectives into groups that share mobs; within a group the largest kill count
    covers the rest, across groups the times add."""
    groups: list[list[Objective]] = []
    for o in site.objectives:
        for g in groups:
            if o.mob_ids and any(set(o.mob_ids) & set(x.mob_ids) for x in g):
                g.append(o)
                break
        else:
            groups.append([o])
    return groups


# --- excursion ordering: nearest neighbour + 2-opt + Or-opt on run time ------------------------------------

def order_sites(sites: list[Site], world: World, start: MapPos, end: MapPos) -> list[Site]:
    if len(sites) <= 1:
        return list(sites)
    cost = lambda a, b: world.run_seconds(a, b)  # noqa: E731
    # nearest neighbour
    remaining = list(sites)
    tour: list[Site] = []
    cur = start
    while remaining:
        nxt = min(remaining, key=lambda s: cost(cur, s.pos))
        remaining.remove(nxt)
        tour.append(nxt)
        cur = nxt.pos

    def path_cost(t: list[Site]) -> float:
        c, p = 0.0, start
        for s in t:
            c += cost(p, s.pos)
            p = s.pos
        return c + cost(p, end)

    improved = True
    best = path_cost(tour)
    while improved:
        improved = False
        n = len(tour)
        for i in range(n - 1):                       # 2-opt: reverse tour[i:j+1]
            for j in range(i + 1, n):
                cand = tour[:i] + tour[i:j + 1][::-1] + tour[j + 1:]
                c = path_cost(cand)
                if c < best - 1e-6:
                    tour, best, improved = cand, c, True
        for seg in (1, 2, 3):                         # Or-opt: move a segment of 1-3 sites elsewhere
            for i in range(0, len(tour) - seg + 1):
                segment = tour[i:i + seg]
                rest = tour[:i] + tour[i + seg:]
                for k in range(0, len(rest) + 1):
                    if k == i:
                        continue
                    cand = rest[:k] + segment + rest[k:]
                    c = path_cost(cand)
                    if c < best - 1e-6:
                        tour, best, improved = cand, c, True
    return tour


# --- bundles -------------------------------------------------------------------------------------------

@dataclass
class Bundle:
    end_hub: Hub
    sites: list[Site]
    seconds: float
    xp: int
    unlocked: int
    penalty: float
    steps: list[Step]
    end_state: PlayerState
    feasible: bool = True
    needs_level: Optional[int] = None

    @property
    def score(self) -> float:
        if self.seconds <= 0:
            return 0.0
        return self.xp / self.seconds * self.penalty + 0.0


class Planner:
    def __init__(self, cat: Catalog, world: World, cm: CostModel, cfg: PlannerConfig, never_accept: Optional[set[int]] = None):
        self.cat, self.world, self.cm, self.cfg = cat, world, cm, cfg
        self.hubs, self.npc_hub = cluster_hubs(cat, world, cfg.hub_radius)
        self.last_train_level = 1
        self.never_accept: set[int] = set(never_accept or ())   # pass 2: quests pass 1 accepted but never used
        self.pruned: set[int] = set()

    # -- helpers ---------------------------------------------------------------------------------

    def hub_of_npc(self, npc_id: Optional[int]) -> Optional[Hub]:
        if npc_id is None or npc_id not in self.npc_hub:
            return None
        return self.hubs[self.npc_hub[npc_id]]

    def hub_at(self, pos: MapPos) -> Optional[Hub]:
        for h in self.hubs:
            if self.world.yards(h.center, pos) <= self.cfg.hub_radius:
                return h
        return None

    def offered_at(self, h: Hub, st: PlayerState) -> list[Quest]:
        return [q for q in self.cat.quests.values() if q.giver in h.npc_ids and st.can_accept(q)]

    def turnins_at(self, h: Hub, st: PlayerState) -> list[Quest]:
        return [q for q in self.cat.quests.values() if q.turnin in h.npc_ids and st.can_turnin(q)]

    def worth_accepting(self, q: Quest, st: PlayerState) -> bool:
        """Liberal filter: anything we could plausibly finish in the next few levels. Pruned later."""
        for o in q.objectives:
            if difficulty(o, q.level) > st.level + self.cfg.accept_ahead_levels:
                return False
        return True

    # -- hub visit ------------------------------------------------------------------------------

    def visit_hub(self, h: Hub, st: PlayerState) -> list[Step]:
        """Everything the player does standing at one hub, then a sweep of the neighbouring hubs of the
        same village (within village_seconds of running) so nothing is left to pick up before leaving."""
        steps = self._visit_one(h, st)
        visited = {h.id}
        while True:
            near = [o for o in self.hubs if o.id not in visited
                    and self.world.run_seconds(st.pos, o.center) <= self.cfg.village_seconds
                    and (self.turnins_at(o, st) or any(self.worth_accepting(q, st) for q in self.offered_at(o, st)))]
            if not near:
                break
            nxt = min(near, key=lambda o: self.world.run_seconds(st.pos, o.center))
            travel(st, self.world, nxt.center, self.world.run_seconds(st.pos, nxt.center))
            visited.add(nxt.id)
            steps += self._visit_one(nxt, st)
        return steps

    def _visit_one(self, h: Hub, st: PlayerState) -> list[Step]:
        steps: list[Step] = []
        step = Step(kind=StepKind.HUB, goto=h.center, sim_t_start=st.t, sim_level=st.level)
        xp_before = st.total_xp
        # turn in -> accept -> turn in ... until nothing changes: a turn-in unlocks the chain follow-up at the
        # same NPC, and a quest with no objectives (a "talk to X" hand-off) is turned in the moment it is taken
        changed = True
        while changed:
            changed = False
            for q in self.turnins_at(h, st):
                st.turnin(q)
                st.t += 4.0
                step.turnins.append(q.id)
                step.order.append(("turnin", q.id))
                changed = True
            for q in sorted(self.offered_at(h, st), key=lambda q: q.level):
                if self.worth_accepting(q, st) and st.can_accept(q) and q.id not in self.never_accept:
                    st.accept(q)
                    st.t += 3.0
                    step.accepts.append(q.id)
                    step.order.append(("accept", q.id))
                    changed = True
        step.sim_xp_gained = st.total_xp - xp_before
        step.sim_t_end = st.t
        if step.turnins or step.accepts:
            steps.append(step)
        # 3. services
        if "flightmaster" in h.services:
            for f in self.cat.flights.values():
                if f.npc_id in h.npc_ids:
                    st.known_flights.add(f.name)
        if "innkeeper" in h.services and self.should_bind(h, st):
            inn = next((self.cat.npcs[i] for i in h.npc_ids if "innkeeper" in self.cat.npcs[i].roles), None)
            if inn:
                st.bound_inn, st.bound_inn_pos = inn.name, inn.pos
                st.t += 5.0
                steps.append(Step(kind=StepKind.HEARTH_BIND, goto=inn.pos, name=inn.name,
                                  text=f"Set your hearthstone at {inn.name}", sim_t_start=st.t, sim_t_end=st.t, sim_level=st.level))
        trainer = f"trainer:{st.player_class.lower()}" if st.player_class else None
        if trainer and trainer in h.services and st.level >= self.last_train_level + 2:
            self.last_train_level = st.level
            st.t += 20.0
            steps.append(Step(kind=StepKind.TRAIN, goto=h.center, text=f"Train new skills (level {st.level})",
                              classes=(st.player_class,), sim_t_start=st.t, sim_t_end=st.t, sim_level=st.level))
        return steps

    def should_bind(self, h: Hub, st: PlayerState) -> bool:
        if st.bound_inn_pos is not None and self.world.yards(st.bound_inn_pos, h.center) < self.cfg.rebind_min_yards:
            return False
        n = sum(1 for qid in st.accepted if self.hub_of_npc(self.cat.quests[qid].turnin) is h)
        n += sum(1 for q in self.cat.quests.values() if q.giver in h.npc_ids and q.id not in st.turned_in)
        return n >= self.cfg.home_hub_quests

    # -- bundle construction ---------------------------------------------------------------------------

    def feasible_objectives(self, st: PlayerState) -> list[Objective]:
        out = []
        for qid in st.accepted:
            q = self.cat.quests[qid]
            for o in q.objectives:
                if not st.objective_done(o) and feasible(o, q.level, st.level) and o.pois:
                    out.append(o)
        return out

    def travel_step(self, st: PlayerState, dest: MapPos, label: str) -> list[Step]:
        opts = travel_options(self.world, self.cat, st, dest)
        best = opts[0]
        steps: list[Step] = []
        t0 = st.t
        if best.kind == "hearth":
            steps.append(Step(kind=StepKind.TRAVEL, goto=best.legs[0], text=f"Use your Hearthstone to {best.via}",
                              sim_t_start=st.t, sim_level=st.level))
        elif best.kind == "fly":
            steps.append(Step(kind=StepKind.FLY, goto=best.legs[0], name=best.via, text=f"Fly to {best.via}",
                              sim_t_start=st.t, sim_level=st.level))
        travel(st, self.world, dest, best.seconds, best.kind, best.via)
        for s in steps:
            s.sim_t_end = st.t
        if not steps and best.seconds > 90:   # long run: give the arrow an explicit leg
            steps.append(Step(kind=StepKind.TRAVEL, goto=dest, text=label, sim_t_start=t0, sim_t_end=st.t, sim_level=st.level))
        return steps

    def simulate_bundle(self, st0: PlayerState, end_hub: Hub, sites: list[Site]) -> Bundle:
        st = st0.clone()
        steps: list[Step] = []
        xp_before, t_before = st.total_xp, st.t
        pen_num, pen_den = 0.0, 0.0
        ok, needs = True, None
        for s in sites:
            steps += self.travel_step(st, s.pos, f"Go to {s.objectives[0].text}")
            step = Step(kind=StepKind.OBJECTIVE, goto=s.pos, sim_t_start=st.t, sim_level=st.level)
            for group in mob_groups(s):
                # within a group the biggest kill count covers the rest (same pack of mobs)
                main = max(group, key=lambda o: self.cm.kills_needed(o))
                for o in group:
                    q = self.cat.quests[o.quest_id]
                    if not feasible(o, q.level, st.level):
                        ok, needs = False, max(needs or 0, difficulty(o, q.level) - 2)
                    secs_est = self.cm.objective_seconds(o, st.level, q.level)
                    pen_num += band_penalty(o, q.level, st.level) * secs_est
                    pen_den += secs_est
                    if o is main:
                        do_objective(st, self.cat, self.cm, o)
                    else:
                        st.done_objectives.add(o.uid())
                        if o.kind not in (ObjKind.KILL, ObjKind.COLLECT):
                            st.t += self.cm.objective_seconds(o, st.level, q.level)
                    step.completes.append(o.uid())
                    if q.classes:
                        step.classes = tuple(q.classes)
            step.sim_t_end = st.t
            steps.append(step)
        steps += self.travel_step(st, end_hub.center, f"Go to {end_hub.name}")
        # value at the end hub: turn-ins we will be able to do, plus what they unlock
        xp_turnin = sum(XP.quest_xp(st.level, q) for q in self.turnins_at(end_hub, st))
        probe = st.clone()
        for q in self.turnins_at(end_hub, probe):
            probe.turnin(q)
        unlocked = sum(XP.quest_xp(probe.level, q) for q in self.offered_at(end_hub, probe) if self.worth_accepting(q, probe))
        xp = (st.total_xp - xp_before) + xp_turnin
        penalty = (pen_num / pen_den) if pen_den else 1.0
        b = Bundle(end_hub, sites, st.t - t_before, xp, unlocked, penalty, steps, st, ok, needs)
        return b

    def candidate_bundles(self, st: PlayerState, here: Optional[Hub]) -> list[Bundle]:
        objs = self.feasible_objectives(st)
        bundles: list[Bundle] = []
        for h in self.hubs:
            # objectives whose turn-in is at h, plus objectives of quests that need nothing else
            core = [o for o in objs if self.hub_of_npc(self.cat.quests[o.quest_id].turnin) is h]
            offers = [q for q in self.offered_at(h, st) if self.worth_accepting(q, st) and q.id not in self.never_accept]
            pending = self.turnins_at(h, st)   # already complete (e.g. a hand-off quest), just needs the walk
            if not core and not offers and not pending:
                continue
            if h is here and not core:
                continue
            sites = build_sites(core, self.world, st.pos, self.cfg.site_merge_yards, self.cfg.colocate_yards)
            tour = order_sites(sites, self.world, st.pos, h.center)
            # fold in other feasible objectives that are cheap to insert (they may complete quests for a later hub)
            extra = [o for o in objs if o not in core]
            for o in extra:
                pos = min(o.pois, key=lambda p: self.world.yards(st.pos, p))
                best_delta, best_k = math.inf, None
                pts = [st.pos] + [s.pos for s in tour] + [h.center]
                for k in range(len(pts) - 1):
                    delta = (self.world.run_seconds(pts[k], pos) + self.world.run_seconds(pos, pts[k + 1])
                             - self.world.run_seconds(pts[k], pts[k + 1]))
                    if delta < best_delta:
                        best_delta, best_k = delta, k
                if best_delta <= self.cfg.detour_budget and best_k is not None:
                    tour.insert(best_k, Site(pos, [o]))
            b = self.simulate_bundle(st, h, tour)
            b.seconds += self.comeback_charge(st, b, objs)
            bundles.append(b)
        return bundles

    def comeback_charge(self, st: PlayerState, b: Bundle, objs: list[Objective]) -> float:
        """Leaving work behind on this side of the map is not free: charge the extra travel the plan will
        need later to come back for it (max over the objectives left behind of the distance from the end
        hub minus the distance from here). This is what stops a cheap flight or hearth from bouncing the
        player between areas for one turn-in, and what makes "finish the area before you leave" emerge."""
        done = {o.uid() for s in b.sites for o in s.objectives}
        worst = 0.0
        for o in objs:
            if o.uid() in done:
                continue
            pos = min(o.pois, key=lambda p: self.world.yards(st.pos, p))
            extra = self.world.run_seconds(b.end_hub.center, pos) - self.world.run_seconds(st.pos, pos)
            worst = max(worst, extra)
        return worst

    def bundle_value(self, b: Bundle) -> float:
        """XP per second, with the discounted value of what the end hub unlocks and the level-band penalty."""
        if b.seconds <= 0:
            return 0.0
        return (b.xp + self.cfg.gamma * b.unlocked) / b.seconds * b.penalty

    # -- grinding --------------------------------------------------------------------------------------

    def best_grind(self, st: PlayerState) -> Optional[tuple[GrindSpot, float, float]]:
        """(spot, xp/s at the spot, travel seconds) for the best reachable spot at this level."""
        best = None
        for g in self.cat.grind_spots:
            mob = min(max(g.mob_level_min, st.level - 1), g.mob_level_max)
            if mob > st.level + 1:
                continue
            per = XP.mob_xp(st.level, mob)
            if per <= 0:
                continue
            rate = per / self.cm.seconds_per_kill(st.level, mob, g.density)
            trav = self.world.run_seconds(st.pos, g.pos)
            # amortise the walk over roughly one level of grinding
            eff = rate * (1.0 / (1.0 + trav / max(60.0, XP.xp_to_level(st.level) / rate)))
            if best is None or eff > best[1]:
                best = (g, eff, trav)
        # objective sites of accepted quests are grind spots too (their mobs are known)
        return best

    def grind_step(self, st: PlayerState, target_level: int) -> list[Step]:
        g = self.best_grind(st)
        if g is None:
            return []
        spot, _, _ = g
        steps = self.travel_step(st, spot.pos, f"Go to {spot.name}")
        mob = min(max(spot.mob_level_min, st.level - 1), spot.mob_level_max)
        t0, lvl0, xp0 = st.t, st.level, st.total_xp
        secs, gained = grind_until(st, self.cm, mob, spot.density, target_level)
        if secs == math.inf:
            return []
        steps.append(Step(kind=StepKind.GRIND, goto=spot.pos, level_gate=target_level,
                          text=f"Grind {spot.name} (lvl {spot.mob_level_min}-{spot.mob_level_max}) until level {target_level}",
                          sim_t_start=t0, sim_t_end=st.t, sim_level=lvl0, sim_xp_gained=st.total_xp - xp0))
        return steps

    def next_useful_level(self, st: PlayerState, bundles: list[Bundle]) -> int:
        needs = [b.needs_level for b in bundles if not b.feasible and b.needs_level]
        # quests we cannot accept yet because of min_level, and objectives too hard right now
        for q in self.cat.quests.values():
            if q.id in st.turned_in or q.id in st.accepted:
                continue
            if q.min_level > st.level and all(p in st.turned_in for p in q.prereqs):
                needs.append(q.min_level)
        for qid in st.accepted:
            q = self.cat.quests[qid]
            for o in q.objectives:
                if not st.objective_done(o) and not feasible(o, q.level, st.level):
                    needs.append(difficulty(o, q.level) - 2)
        needs = [n for n in needs if n > st.level]
        return min(needs) if needs else st.level + 1

    # -- main loop -------------------------------------------------------------------------------------

    def plan(self, st: PlayerState) -> list[Step]:
        steps: list[Step] = []
        it = 0
        while st.level < self.cfg.target_level and it < self.cfg.max_iterations:
            it += 1
            here = self.hub_at(st.pos)
            if here:
                steps += self.visit_hub(here, st)
                if st.level >= self.cfg.target_level:
                    break
            bundles = self.candidate_bundles(st, here)
            usable = [b for b in bundles if b.feasible and self.bundle_value(b) > 0]
            g = self.best_grind(st)
            grind_rate = g[1] if g else 0.0
            best = max(usable, key=self.bundle_value) if usable else None
            # stall-breaker: nothing worth doing, or everything left is so poor that grinding beats it clearly
            if best is None or self.bundle_value(best) < grind_rate * self.cfg.grind_tolerance:
                # one level at a time; consecutive grind steps at one spot are merged by merge_grinds()
                target = min(self.cfg.target_level, st.level + 1)
                gs = self.grind_step(st, target)
                if not gs:
                    if best is None:
                        break   # nothing to do and nowhere to grind: the guide ends here
                else:
                    steps += gs
                    continue
            steps += best.steps
            self._adopt(st, best.end_state)
        # final sweep: turn in whatever is complete at a nearby hub
        here = self.hub_at(st.pos)
        if here:
            steps += self.visit_hub(here, st)
        steps, self.pruned = prune_unused_accepts(steps, self.cat, self.hubs, self.npc_hub)
        return merge_grinds(steps)

    @staticmethod
    def _adopt(st: PlayerState, new: PlayerState) -> None:
        st.__dict__.update(new.clone().__dict__)


def prune_unused_accepts(steps: list[Step], cat: Catalog, hubs: list[Hub], npc_hub: dict[int, int]) -> tuple[list[Step], set[int]]:
    """Drop accepts of quests the plan never turns in, unless they are breadcrumbs to a hub outside
    the plan (the next guide will turn them in). Returns (steps, pruned quest ids) so a second planning
    pass can refuse those accepts up front (they cost log slots and dialogue time in pass 1)."""
    turned = {q for s in steps for q in s.turnins}
    pruned: set[int] = set()
    keep: list[Step] = []
    for s in steps:
        if s.kind == StepKind.HUB:
            kept = []
            for q in s.accepts:
                if q in turned or cat.quests[q].breadcrumb or cat.quests[q].turnin not in npc_hub:
                    kept.append(q)
                else:
                    pruned.add(q)
            s.accepts = kept
            if not (s.accepts or s.turnins):
                continue
        if s.kind == StepKind.OBJECTIVE:
            s.completes = [c for c in s.completes if c[0] in turned]
            if not s.completes:
                continue
        keep.append(s)
    return keep, pruned


def merge_grinds(steps: list[Step]) -> list[Step]:
    """Consecutive grind steps at the same spot become one `.xp N` step with the final level."""
    out: list[Step] = []
    for s in steps:
        if out and s.kind == StepKind.GRIND and out[-1].kind == StepKind.GRIND and out[-1].goto == s.goto:
            prev = out[-1]
            prev.level_gate = s.level_gate
            prev.text = (prev.text or "").split(" until level")[0] + f" until level {s.level_gate}"
            prev.sim_t_end = s.sim_t_end
            prev.sim_xp_gained += s.sim_xp_gained
            continue
        out.append(s)
    return out


def plan_two_pass(cat: Catalog, world: World, cm: CostModel, cfg: PlannerConfig, start: PlayerState) -> tuple[list[Step], Planner]:
    """Pass 1 accepts liberally and prunes; pass 2 replans refusing the pruned quests, which frees
    quest-log slots and dialogue time. Keep whichever pass simulates faster."""
    p1 = Planner(cat, world, cm, cfg)
    s1 = p1.plan(start.clone())
    if not p1.pruned:
        return s1, p1
    p2 = Planner(cat, world, cm, cfg, never_accept=p1.pruned)
    s2 = p2.plan(start.clone())
    t1 = s1[-1].sim_t_end if s1 else math.inf
    t2 = s2[-1].sim_t_end if s2 else math.inf
    return (s2, p2) if t2 <= t1 else (s1, p1)

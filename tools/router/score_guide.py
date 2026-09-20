"""Score a SHIPPED guide under the same cost model the planner uses, so the two are comparable.

    python3 tools/router/score_guide.py Lodestar_Guides_Horde/Orc_Troll_Durotar.lua
    python3 tools/router/score_guide.py --all

Why this exists: the project has two routers with different objectives -- generate_route.lua
minimises walking, tools/router minimises simulated time to level -- and no way to compare their
output, because the shipped guides had never been measured in anything but map percent. Distance is
a proxy for time; this replays a shipped route through validate.replay, exactly as the planner's own
output is replayed, and reports minutes and XP per minute for both.

The minutes are the cost model's opinion and not a measurement: every constant in cost.py is a prior
that laps.py exists to re-fit from a recorded run. What is meaningful is the COMPARISON -- both
routes are scored by the same rules, so a difference between them is a difference in the route.

Known limits, stated because they bound what the number means:
  * A guide step the model has no notion of (.buy, .train, .hs, .fly) contributes travel but no
    other cost, so a route that shops a lot is scored slightly optimistically.
  * A quest the catalog does not carry is DROPPED from the replay and counted in "skipped". A guide
    with a high skipped count is being scored on a subset of itself. Read that column first.
  * The absolute minutes are NOT stable against how the catalog is built. Widening the level band
    from the guide's own to band-3/band+2 (which is the margin the generated routes ask for) moved
    Tirisfal from 183 minutes reaching level 11 to 146 reaching level 6, and Thousand Needles from
    339 to 883. Same route, same model, different quest set to draw objectives and grind spots
    from. Treat a single zone's number as meaningful only where "skipped" is small, and compare a
    route against another route scored in the same run -- never across runs.
  * A route that crosses continents scores as `inf`, because World.yards returns infinity between
    them: the model has no boat or zeppelin. One guide of 23 is affected (Horde 20-25: Hillsbrad
    Foothills, which rides Orgrimmar to Undercity). That is a real gap in the planner, not in this
    script -- it cannot plan such a route either.

The one comparison that is currently solid is Durotar, where only 6 quest references are skipped and
the number held at 268 minutes across both catalog constructions: the shipped route takes 268
simulated minutes and reaches level 11, and the planner takes 203 and reaches 12.
"""
from __future__ import annotations

import argparse
import glob
import importlib.util
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "router"))
sys.path.insert(0, ROOT)

import lint_guides  # noqa: E402
from tools.router.catalog import load as load_catalog  # noqa: E402
from tools.router.cost import CostModel  # noqa: E402
from tools.router.model import MapPos, Step, StepKind  # noqa: E402
from tools.router.validate import replay  # noqa: E402
from tools.router.vanilla_catalog import ZONE_FRAMES  # noqa: E402

KIND_FOR = {"accept": StepKind.HUB, "turnin": StepKind.HUB, "complete": StepKind.OBJECTIVE}


def zone_to_map(name: str, data) -> int | None:
    for z, n in data["zones"].items():
        if str(n).lower() == name.lower():
            return z
    for z, f in ZONE_FRAMES.items():
        if f.name.lower() == name.lower():
            return z
    return None


def to_steps(g, data, cat) -> tuple[list[Step], int]:
    """The linter's parse of a shipped guide, in the planner's Step form.

    Returns the steps and the number of quest references dropped because the catalog has no such
    quest. validate.replay indexes cat.quests directly and raises on a miss, so filtering here is
    required -- but a silent filter would quietly score a different route than the one shipped.
    """
    out: list[Step] = []
    skipped = 0
    for st in g.steps:
        accepts, turnins, completes, order, gate = [], [], [], [], None
        for a in st.actions:
            if a.type in ("accept", "turnin", "complete") and a.quest and a.quest not in cat.quests:
                skipped += 1
                continue
            if a.type == "accept" and a.quest:
                accepts.append(a.quest)
                order.append(("accept", a.quest))
            elif a.type == "turnin" and a.quest:
                turnins.append(a.quest)
                order.append(("turnin", a.quest))
            elif a.type == "complete" and a.quest:
                # The DSL's `.complete <id>` with no index means "this step finishes the quest",
                # which is every objective, not objective zero. `.complete <id>,<n>` watches one.
                have = {o.index for o in cat.quests[a.quest].objectives}
                if a.objective is None:
                    if not have:
                        skipped += 1
                    for idx in sorted(have):
                        completes.append((a.quest, idx))
                elif a.objective in have:
                    completes.append((a.quest, a.objective))
                else:
                    skipped += 1
            elif a.type == "level":
                gate = a.level
        pos = None
        if st.goto:
            mapid = zone_to_map(st.goto[0], data)
            if mapid is not None:
                pos = MapPos(mapid, st.goto[1], st.goto[2])
        kind = StepKind.TRAVEL
        if gate:
            kind = StepKind.GRIND
        elif accepts or turnins:
            kind = StepKind.HUB
        elif completes:
            kind = StepKind.OBJECTIVE
        out.append(Step(kind=kind, goto=pos, accepts=accepts, turnins=turnins,
                        completes=completes, order=order, level_gate=gate,
                        zone=st.goto[0] if st.goto else None))
    return out, skipped


def score(path: str, data) -> dict | None:
    guides = lint_guides.guides_in_file(path)
    if not guides:
        return None
    g = guides[0]
    zone = next((s.goto[0] for s in g.steps if s.goto), None)
    if not zone:
        return None
    cat_json = os.path.join(os.environ.get("TEMP", "/tmp"), "score_%s.json" % os.path.basename(path).replace(".lua", ""))
    # A route legitimately uses quests outside its own band -- a chain that starts low, a turn-in
    # that lands high -- so a catalog built on the band alone is missing them, and every missing
    # quest is silently dropped from the replay. The generated routes already pass this margin
    # (Desolace's regen line asks for 27-37 to carry a 30-35 guide); match it, or the comparison is
    # between a full route and a filtered one.
    lo, hi = max(1, g.min_level - 3), g.max_level + 2
    cmd = [sys.executable, "-m", "tools.router.vanilla_catalog", "--zone", zone,
           "--faction", g.faction if g.faction in ("Horde", "Alliance") else "Horde",
           "--levels", f"{lo}-{hi}", "-o", cat_json]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        return {"guide": g.name, "error": (r.stderr.strip().splitlines() or ["catalog failed"])[-1][:60]}
    cat, world, start, _meta = load_catalog(cat_json)
    steps, skipped = to_steps(g, data, cat)
    rep = replay(steps, cat, world, CostModel(), start)
    return {"guide": g.name, "steps": len(steps), "minutes": rep.total_seconds / 60.0,
            "final_level": rep.final_level, "xp_per_min": rep.xp_per_minute,
            "issues": len(rep.issues), "skipped": skipped}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("guides", nargs="*")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location(
        "pfquest_query", os.path.join(ROOT, "tools", "pfquest", "query.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    data = mod.load()
    paths = args.guides or (sorted(glob.glob(os.path.join(ROOT, "Lodestar_Guides_*", "*.lua"))) if args.all else [])
    if not paths:
        ap.error("give a guide path or --all")
    print(f"{'shipped guide':<40}{'steps':>7}{'minutes':>9}{'to lvl':>8}{'xp/min':>9}{'skipped':>9}")
    print("-" * 82)
    for p in paths:
        r = score(p, data)
        if not r:
            continue
        if r.get("error"):
            print(f"{r['guide'][:40]:<40}{'':>7}  {r['error']}")
            continue
        print(f"{r['guide'][:40]:<40}{r['steps']:>7}{r['minutes']:>9.0f}{r['final_level']:>8}"
              f"{r['xp_per_min']:>9.0f}{r['skipped']:>9}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

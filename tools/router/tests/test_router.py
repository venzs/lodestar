"""Plain-assert tests (no pytest needed):  python -m tools.router.tests.test_router

1. XP formulas reproduce the known Classic tables.
2. The planner's route validates (replay finds no issues) and grows monotonically in level.
3. A synthetic lap built from the plan, with timestamps perturbed, round-trips through
   laps.calibrate + laps.steps_from_lap + validate.replay and moves the fitted class factor.
4. The emitted text parses with the real Parser.lua when lua5.1 is available.
"""
from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, ROOT)

from tools.router import xp as XP                                   # noqa: E402
from tools.router.catalog import load                               # noqa: E402
from tools.router.cost import CostModel                             # noqa: E402
from tools.router.emit import GuideHeader, emit, hub_actions        # noqa: E402
from tools.router.laps import LapEntry, calibrate, steps_from_lap   # noqa: E402
from tools.router.luabin import find_lua                             # noqa: E402
from tools.router.model import StepKind                             # noqa: E402
from tools.router.router import PlannerConfig, plan_two_pass        # noqa: E402
from tools.router.validate import replay                            # noqa: E402

EXAMPLE = os.path.join(HERE, "..", "examples", "deathknell.json")


def test_xp_tables():
    assert [XP.xp_to_level(l) for l in range(1, 11)] == [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600]
    assert XP.xp_to_level(30) == 47400 and XP.xp_to_level(31) == 50800 and XP.xp_to_level(33) == 58600
    assert XP.grey_level(10) == 4 and XP.grey_level(40) == 31 and XP.grey_level(5) == 0
    assert XP.mob_xp(10, 10) == 95 and XP.mob_xp(10, 12) == int(round(95 * 1.1))
    assert XP.mob_xp(10, 4) == 0 and XP.mob_xp(10, 7) == int(round(95 * (1 - 3 / 7)))
    assert XP.quest_xp_fraction(10, 4) == 0.8 and XP.quest_xp_fraction(20, 4) == 0.1


def make_plan(target=6):
    cat, world, start, _ = load(EXAMPLE)
    cm = CostModel()
    steps, planner = plan_two_pass(cat, world, cm, PlannerConfig(target_level=target), start)
    return cat, world, cm, start, steps


def test_plan_validates():
    cat, world, cm, start, steps = make_plan()
    rep = replay(steps, cat, world, cm, start)
    assert rep.ok(), rep.issues
    assert rep.final_level == 6
    levels = [s.sim_level for s in steps]
    assert levels == sorted(levels)
    # the hand-off quest is accepted and turned in inside one hub visit
    first = steps[0]
    assert first.kind == StepKind.HUB and 3901 in first.accepts and 3901 in first.turnins
    # no objective is planned more than 2 levels above the player
    for s in steps:
        if s.kind == StepKind.OBJECTIVE:
            for qid, idx in s.completes:
                o = next(o for o in cat.quests[qid].objectives if o.index == idx)
                assert (o.mob_level_max or cat.quests[qid].level) <= s.sim_level + 2


def synthetic_lap(steps, cat, slow=1.4, seed=1):
    """Pretend a human played the plan 40% slower on kills, exactly on schedule elsewhere."""
    rnd = random.Random(seed)
    entries: list[LapEntry] = []
    t = 0.0
    level = 1
    for s in steps:
        level = s.sim_level or level
        if s.kind == StepKind.HUB:
            t = s.sim_t_start
            for kind, qid in hub_actions(s):
                t += 4
                q = cat.quests[qid]
                entries.append(LapEntry(kind, t, level, s.goto.map, s.goto.x + rnd.uniform(-0.05, 0.05), s.goto.y, questID=qid,
                                        npcID=q.turnin if kind == "turnin" else q.giver, npc="x", questLevel=q.level,
                                        xp=XP.quest_xp(level, q) if kind == "turnin" else None))
        elif s.kind == StepKind.OBJECTIVE:
            t = s.sim_t_start
            for qid, idx in s.completes:
                o = next(o for o in cat.quests[qid].objectives if o.index == idx)
                dur = (s.sim_t_end - s.sim_t_start) / len(s.completes)
                mobs = None
                if o.mob_ids:
                    dur *= slow
                    mobs = f"Mob{o.mob_ids[0]} x{o.count} (lvl {o.mob_level_min}-{o.mob_level_max})"
                t += dur
                entries.append(LapEntry("complete", t, level, s.goto.map, s.goto.x, s.goto.y, questID=qid, objective=idx, mobs=mobs))
    return entries


def test_lap_roundtrip():
    cat, world, cm, start, steps = make_plan()
    base = replay(steps, cat, world, cm, start).total_seconds
    lap = synthetic_lap(steps, cat)
    before = cm.class_factor
    stats = calibrate(lap, cat, world, cm)
    assert stats["npc_updates"] > 0 and len(stats["ttk_samples"]) >= 5
    assert cm.class_factor > before, "slower kills in the lap should raise the class factor"
    human = steps_from_lap(lap, cat, world=world)
    rep = replay(human, cat, world, cm, start)
    assert rep.ok(), rep.issues
    again = replay(steps, cat, world, cm, start).total_seconds
    assert again > base, "after calibrating on a slower lap, the same plan must simulate slower"


def test_emit_parses_with_lua():
    cat, world, cm, start, steps = make_plan()
    replay(steps, cat, world, cm, start)
    text = emit(GuideHeader(name="Test 1-6: Deathknell", faction="Horde", races=["Undead"], levels=(1, 6)), steps, cat)
    assert text.startswith("#guide Test 1-6: Deathknell\n")
    lua = find_lua()
    if not lua:
        # A skip that prints and passes is how this check spent its life doing nothing: shutil.which
        # could not see the lua5.1 shim on PATH, so the branch below never ran. Say so loudly.
        print("  WARNING: no Lua interpreter found, guide was NOT parsed (set $LUA)")
        return
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(text)
        path = f.name
    try:
        out = subprocess.run([lua, os.path.join(ROOT, "tools", "router", "check_guide.lua"), path], capture_output=True, text=True)
        assert out.returncode == 0, out.stderr + out.stdout
        assert "order OK" in out.stdout
    finally:
        os.unlink(path)


# --- real data: Deathknell from Data/Vanilla.lua ----------------------------------------------------------

DEATHKNELL_QUESTS = {363, 364, 3901, 376, 6395, 3902, 380, 381, 382}   # the Undead starting loop, all classes


def test_vanilla_deathknell():
    """Build the catalog from the Vanilla database (Tirisfal Glades, Undead 1-6) and plan the Deathknell
    loop: Rude Awakening (363) is accepted before The Mindless Ones (364, which it unlocks), the plan
    validates, and every Deathknell quest is turned in by the time the player is level 6."""
    from tools.router.vanilla_catalog import build, load_vanilla
    data = load_vanilla()
    raw = build(data, [85], "Horde", "Undead", (1, 6), bbox=(20.0, 50.0, 45.0, 80.0))   # Deathknell corner of the map
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        import json
        json.dump(raw, f)
        path = f.name
    try:
        cat, world, start, _ = load(path)
    finally:
        os.unlink(path)
    assert DEATHKNELL_QUESTS <= set(cat.quests), "Deathknell quests missing from the catalog"
    assert cat.quests[364].prereqs_any == (363,)
    assert cat.zone_map_names[85] == "Tirisfal Glades"
    cm = CostModel()
    steps, _ = plan_two_pass(cat, world, cm, PlannerConfig(target_level=6), start)
    rep = replay(steps, cat, world, cm, start)
    assert rep.ok(), rep.issues
    assert rep.final_level >= 6
    order = [(k, q) for s in steps if s.kind == StepKind.HUB for k, q in hub_actions(s)]
    assert ("accept", 363) in order and ("accept", 364) in order
    assert order.index(("accept", 363)) < order.index(("turnin", 363)) < order.index(("accept", 364))
    turned = {q for s in steps for q in s.turnins}
    assert DEATHKNELL_QUESTS <= turned, f"not turned in: {DEATHKNELL_QUESTS - turned}"
    text = emit(GuideHeader(name="Test 1-6: Deathknell", faction="Horde", races=["Undead"], levels=(1, 6)), steps, cat)
    assert ".goto Tirisfal Glades," in text


if __name__ == "__main__":
    # At the bottom on purpose: this block runs where it is written, so anything defined below it
    # is invisible to globals() and never runs. test_vanilla_deathknell sat below it and had never
    # been executed once.
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)

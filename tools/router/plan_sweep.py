"""Run the time-based planner over every zone the guide packs cover, and report what happens.

    python3 tools/router/plan_sweep.py

There are two routers in this repo: generate_route.lua, which ships the guides and minimises
WALKING, and tools/router, which does not ship anything and minimises simulated TIME TO LEVEL.
Those are different objectives, and only the second is the one players care about. Consolidating on
one is only safe once the survivor demonstrably produces a route everywhere the other does, so this
is the evidence for that decision rather than an argument about it.

Failures are the output worth reading. A zone that cannot be planned is either missing a MapFrame
(no world bounds for that uiMapID), or missing data outright -- Zephras Isle stops because the
planner validates its own route and refuses one that would send the player to grind a grey mob.

The minutes are the cost model's opinion, not a measurement: every constant in cost.py is a prior
that laps.py is meant to re-fit from a recorded run. Compare zones against each other, and the same
zone before and after a change; do not read the absolute number as a promise.

Needs the real interpreter path for LuaJIT on Windows, where `lua5.1` on PATH may be a shell shim.
"""
import json, os, re, subprocess, sys, glob
LUA = "C:/Users/abhin/AppData/Local/Programs/LuaJIT/bin/luajit.exe"
TMP = os.environ["TEMP"] + "/lode"
sys.path.insert(0, "tools/router")
import lint_guides

rows = []
for path in sorted(glob.glob("Lodestar_Guides_*/*.lua")):
    txt = open(path, encoding="utf-8", errors="replace").read()
    g = re.search(r"#guide\s+(.+)", txt)
    lv = re.search(r"#levels\s+(\d+)\s*-\s*(\d+)", txt)
    fac = re.search(r"#faction\s+(\w+)", txt)
    race = re.search(r"#race\s+([A-Za-z ]+)", txt)
    zone = re.search(r"\.goto ([^,]+),", txt)
    if not (g and lv and zone):
        continue
    rows.append(dict(file=os.path.basename(path), name=g.group(1).strip(), zone=zone.group(1).strip(),
                     lo=int(lv.group(1)), hi=int(lv.group(2)),
                     faction=(fac.group(1) if fac else "Horde"),
                     race=(race.group(1).split(",")[0].strip() if race else None)))

print(f"{'zone':<26}{'guide levels':>13}  catalog / plan")
print("-" * 78)
ok = fail = 0
for r in rows:
    out = os.path.join(TMP, "sw_%s.json" % re.sub(r"[^A-Za-z0-9]", "", r["zone"]))
    cmd = [sys.executable, "-m", "tools.router.vanilla_catalog", "--zone", r["zone"],
           "--faction", r["faction"], "--levels", f"{r['lo']}-{r['hi']}", "-o", out]
    if r["race"]:
        cmd += ["--race", r["race"]]
    c = subprocess.run(cmd, capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{r['zone'][:26]:<26}{str(r['lo'])+'-'+str(r['hi']):>13}  CATALOG FAILED: {(c.stderr.strip().splitlines() or ['?'])[-1][:40]}")
        fail += 1
        continue
    nq = re.search(r"(\d+) quests", c.stdout)
    p = subprocess.run([sys.executable, "-m", "tools.router", "plan", out, "--target", str(r["hi"])],
                       capture_output=True, text=True, timeout=900)
    if p.returncode != 0:
        last = (p.stderr.strip().splitlines() or ["?"])[-1]
        print(f"{r['zone'][:26]:<26}{str(r['lo'])+'-'+str(r['hi']):>13}  {nq.group(1) if nq else '?':>3}q  PLAN FAILED: {last[:44]}")
        fail += 1
        continue
    note = re.search(r"#note[^\n]*?(\d+) min simulated, (\d+) xp/min", p.stdout)
    steps = p.stdout.count("\nstep")
    print(f"{r['zone'][:26]:<26}{str(r['lo'])+'-'+str(r['hi']):>13}  {nq.group(1) if nq else '?':>3}q  {steps:>3} steps"
          + (f", {note.group(1)} min, {note.group(2)} xp/min" if note else ""))
    ok += 1
print(f"\nplanned {ok}, failed {fail}")

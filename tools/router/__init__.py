"""Lodestar route optimizer (offline, Python 3.11+, no third-party deps).

Turns a quest catalog + recorded NPC/objective positions into an ordered step list in the
Lodestar guide text format (see Lodestar_Guide/Parser.lua).

Pipeline:  catalog + recordings  ->  world (yards)  ->  hubs  ->  plan (simulate)  ->  prune  ->  emit

    python -m tools.router plan tools/router/examples/deathknell.json --target 6 > out.txt
    lua5.1 tools/router/check_guide.lua out.txt          # parse with the real Parser.lua

Real data (the pfQuest-derived Lodestar_Guide/Data/Vanilla.lua):

    python -m tools.router.vanilla_catalog --zone Durotar --faction Horde --race Orc --levels 1-12 -o durotar.json
    python -m tools.router durotar.json -o durotar.txt   # "plan" is the default; --target defaults to the level band
    python tools/router/lint_guides.py                   # check every guide pack against the data (ids, order, prereqs, positions)

Modules
    model     dataclasses for quests, objectives, NPCs, hubs, steps, player state
    xp        Classic XP formulas (mob kill XP, quest XP scaling, XP to level) - one place to retune for Forever
    world     uiMap percent -> world yards, distances, run/flight/hearth edge costs
    cost      time models: kill time by level difference, objective duration, travel
    sim       PlayerState simulation (apply accept/complete/turnin/grind/travel)
    router    the planner: hub clustering, bundle search, 2-opt excursions, grind insertion, pruning
    emit      write the guide text format
    laps      ingest recorded laps (Recorder.lua export) to calibrate the cost model and warm-start
    validate  invariants a plan must satisfy before it is emitted
    vanilla_catalog  build a catalog JSON from Data/Vanilla.lua (zone frames, quest XP table, objectives, roles)
    lint_guides      lint Lodestar_Guides_*/**.lua against the data (standalone script, also importable)
"""

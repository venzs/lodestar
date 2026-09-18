"""Lodestar route optimizer (offline, Python 3.11+, no third-party deps).

Turns a quest catalog + recorded NPC/objective positions into an ordered step list in the
Lodestar guide text format (see Lodestar_Guide/Parser.lua).

Pipeline:  catalog + recordings  ->  world (yards)  ->  hubs  ->  plan (simulate)  ->  prune  ->  emit

    python -m tools.router plan tools/router/examples/deathknell.json --target 6 > out.txt
    lua5.1 tools/router/check_guide.lua out.txt          # parse with the real Parser.lua

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
"""

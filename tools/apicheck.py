#!/usr/bin/env python3
"""Verify the suite's WoW API usage against the extracted Forever API surface.

Checks every C_Namespace.Function reference, every RegisterEvent("NAME") and every Enum.X.Y
in the addon sources (Libs excluded) against tools/wow-api/api.json produced by extract_api.py.

Usage: apicheck.py <repo root> [api.json]
Exit status 1 when something unknown is referenced.
"""
import json
import os
import re
import sys

root = sys.argv[1]
api_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "tools", "wow-api", "api.json")
api = json.load(open(api_path))
namespaces = api["namespaces"]
events = set(api["events"])
enums = api["enums"]
ui_globals = set(api.get("ui_globals", []))
c_inferred = set(api.get("c_globals_inferred", []))

# Events that exist but are not in the generated docs (fired by Blizzard Lua or undocumented).
KNOWN_EVENTS = set()

ns_re = re.compile(r"\b(C_[A-Za-z0-9]+)\.([A-Za-z0-9_]+)")
ev_re = re.compile(r"RegisterEvent\(\s*\"([A-Z0-9_]+)\"")
enum_re = re.compile(r"\bEnum\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)")

problems = []
checked = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ("Libs", ".git", "tools", ".release", "node_modules")]
    for fn in filenames:
        if not fn.endswith(".lua"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, root)
        for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
            code = line.split("--")[0]
            for ns, func in ns_re.findall(code):
                checked += 1
                if ns not in namespaces:
                    problems.append(f"{rel}:{lineno}: unknown namespace {ns}")
                elif func not in namespaces[ns]:
                    problems.append(f"{rel}:{lineno}: {ns}.{func} not in Forever API docs")
            for ev in ev_re.findall(code):
                checked += 1
                if ev not in events and ev not in KNOWN_EVENTS:
                    problems.append(f"{rel}:{lineno}: event {ev} not in Forever API docs")
            for enum, field in enum_re.findall(code):
                checked += 1
                if enum not in enums:
                    problems.append(f"{rel}:{lineno}: Enum.{enum} not in Forever API docs")
                elif field not in enums[enum]:
                    problems.append(f"{rel}:{lineno}: Enum.{enum}.{field} not in Forever API docs")

print(f"apicheck: {checked} references checked, {len(problems)} problems")
for p in problems:
    print("  " + p)
sys.exit(1 if problems else 0)

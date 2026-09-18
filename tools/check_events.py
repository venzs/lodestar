#!/usr/bin/env python3
"""Catch two files in one module registering the same event.

AceEvent-3.0 keeps ONE handler per event per object, so a second
`self:RegisterEvent("QUEST_TURNED_IN", ...)` anywhere in a module silently REPLACES the first. The
addon keeps loading, the tests keep passing, and one feature just stops receiving an event it used
to get. That is exactly what happened when QuestLog.lua registered QUEST_TURNED_IN alongside
XPTracker.lua's handler for it, and nothing anywhere would have said so.

The rule is per module (all files in one addon folder share the AceAddon object), and a file
registering the same event twice is fine — that is a re-registration, not a collision.

    python3 tools/check_events.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# self:RegisterEvent("NAME") or self:RegisterEvent("NAME", "Handler")
CALL = re.compile(r'self:RegisterEvent\(\s*"([A-Z0-9_]+)"\s*(?:,\s*"([A-Za-z0-9_]+)"\s*)?\)')


def main():
    problems = []
    for toc in sorted(glob.glob(os.path.join(ROOT, "*", "*.toc"))):
        folder = os.path.dirname(toc)
        addon = os.path.basename(folder)
        # event -> {file: handler}
        seen: dict[str, dict[str, str]] = {}
        for path in sorted(glob.glob(os.path.join(folder, "**", "*.lua"), recursive=True)):
            if os.sep + "Libs" + os.sep in path:
                continue
            rel = os.path.relpath(path, ROOT)
            for event, handler in CALL.findall(open(path, encoding="utf-8").read()):
                seen.setdefault(event, {}).setdefault(rel, handler or "(default)")
        for event, byfile in seen.items():
            if len(byfile) > 1:
                where = ", ".join("%s -> %s" % (f, h) for f, h in sorted(byfile.items()))
                problems.append(
                    "%s: %s registered in %d files (%s). AceEvent keeps one handler per event per "
                    "object, so the last one to run replaces the others — have one of them call the "
                    "other instead." % (addon, event, len(byfile), where))
    if problems:
        print("event check: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("event check: no module registers the same event from two files")
    return 0


if __name__ == "__main__":
    sys.exit(main())

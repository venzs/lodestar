#!/usr/bin/env python3
"""Catch a movable frame rolling its own save-and-restore-the-position code.

A WoW anchor is four values: which corner of the frame, which corner of the parent, and the offset
between them. After a drag the two corners are usually NOT the same one, so code that saves

    local point, _, _, x, y = frame:GetPoint(1)

and restores with SetPoint(point, UIParent, point, x, y) measures the same offsets from a different
origin. The window reappears somewhere else, the player drags it back, that new spot is saved, and
it moves again next login. It reads as "the addon doesn't remember where I put it" while the saved
variables look perfectly fine -- which is why it survived being looked for twice.

Two of the suite's five movable frames had exactly this (the XP tracker and the guild board). Both
now go through Lodestar:SaveAnchor / Lodestar:ApplyAnchor, and this keeps it that way: GetPoint and
a UIParent-relative SetPoint belong to Core/Anchor.lua.

    python3 tools/check_anchors.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OWNER = os.path.join("Lodestar", "Core", "Anchor.lua")

GETPOINT = re.compile(r"\bGetPoint\s*\(")
# SetPoint against UIParent is the restore half -- but only when its arguments come from a stored
# table (pos.point, cfg.pos.x). A SetPoint whose point and offsets are all literals is a fixed
# fallback for a frame that has never been dragged: there is no saved relativePoint for it to lose,
# so it is not this bug. Anchoring to another frame (a tooltip to its owner, a row to the row above)
# is ordinary layout and not what this is about either.
SETPOINT_UIPARENT = re.compile(r"\bSetPoint\s*\([^)\n]*\bUIParent\b")
FROM_TABLE = re.compile(r"\b\w+\.(?:point|rel|relativePoint|pos|x|y)\b")


def main():
    problems = []
    for toc in sorted(glob.glob(os.path.join(ROOT, "*", "*.toc"))):
        folder = os.path.dirname(toc)
        for path in sorted(glob.glob(os.path.join(folder, "**", "*.lua"), recursive=True)):
            if os.sep + "Libs" + os.sep in path:
                continue
            rel = os.path.relpath(path, ROOT)
            if rel == OWNER:
                continue
            for n, line in enumerate(open(path, encoding="utf-8"), 1):
                if line.lstrip().startswith("--"):
                    continue
                if GETPOINT.search(line):
                    problems.append("%s:%d: reads GetPoint directly — use Lodestar:SaveAnchor, which "
                                    "keeps the relativePoint. Dropping it is why a window moves on "
                                    "every login.\n      %s" % (rel, n, line.strip()))
                elif (SETPOINT_UIPARENT.search(line) and FROM_TABLE.search(line)
                      and "ApplyAnchor" not in line):
                    problems.append("%s:%d: anchors to UIParent by hand — use Lodestar:ApplyAnchor so "
                                    "the saved relativePoint is honoured.\n      %s" % (rel, n, line.strip()))
    if problems:
        print("anchor check: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("anchor check: every movable frame uses the shared anchor helper")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Reject calls to functions the client protects from addons.

A protected function called from addon code does not raise a Lua error. It raises
ADDON_ACTION_BLOCKED and taints the execution path, and a pcall around it does not help --
pcall catches Lua errors, and this is not one. Nothing in the addon notices; the symptoms turn up
somewhere else entirely, much later, as things quietly not working.

Lodestar shipped CheckInteractDistance in the harvest for weeks. It fired on NAME_PLATE_UNIT_ADDED,
UPDATE_MOUSEOVER_UNIT and PLAYER_TARGET_CHANGED -- so on essentially every creature walked past --
and it took reading ADDON_ACTION_BLOCKED entries off a player's disk to find it. luacheck and the
API existence check both passed it happily: the function is real, it is just not ours to call.

    python3 tools/check_protected.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Protected for addons on the Mainline API this client runs. The comment on each is why it is
# tempting, which is the thing that puts it back in the code a year from now.
PROTECTED = {
    "CheckInteractDistance": "range to an arbitrary unit; use the interaction frames instead",
    "InteractUnit": "talking to an NPC",
    "TargetUnit": "changing target",
    "FollowUnit": "following",
    "CastSpellByName": "casting",
    "CastSpellByID": "casting",
    "UseAction": "action bar",
    "RunMacro": "macro execution",
    "RunMacroText": "macro execution",
    "JumpOrAscendStart": "movement",
    "MoveForwardStart": "movement",
    "TurnLeftStart": "movement",
    "AcceptGroup": "group invites",
    "ConfirmSummon": "summons",
}

# Places the name may legitimately appear: prose, and the checker's own table.
COMMENT = re.compile(r"^\s*--")


def main():
    problems = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Lodestar*", "**", "*.lua"), recursive=True)):
        if os.sep + "Libs" + os.sep in path:
            continue
        rel = os.path.relpath(path, ROOT)
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if COMMENT.match(line):
                continue
            for name, why in PROTECTED.items():
                # A call or a reference that could become one: `f(`, `pcall(f`, `= f`.
                if re.search(r"\b%s\b" % re.escape(name), line):
                    problems.append("%s:%d: %s is protected (%s) -- calling it raises "
                                    "ADDON_ACTION_BLOCKED and taints, and pcall does not help"
                                    % (rel, n, name, why))
    if problems:
        print("protected check: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("protected check: no addon file calls a protected function")
    return 0


if __name__ == "__main__":
    sys.exit(main())

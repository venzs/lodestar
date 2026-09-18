#!/usr/bin/env python3
"""Verify every shipped TOC before it reaches a client.

A TOC fault is uniquely nasty: the addon still loads and still runs, so nothing looks broken, but
the client quietly declines to hand back its saved variables and the player's data is thrown away
once per session with no error anywhere. That cost this project a day, so it is checked mechanically
from here on.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
problems = []

# Names Lodestar used before the rename. They stay declared so a player upgrading from an older
# build has their data adopted once (Lodestar/Core/Saved.lua), and are exempt from the rule below.
ADOPTED = {"LodestarDB", "LodestarProbeDB", "LodestarScanDB", "LodestarShareDB"}

for toc in sorted(glob.glob(os.path.join(ROOT, "*", "*.toc"))):
    rel = os.path.relpath(toc, ROOT)
    raw = open(toc, "rb").read()
    text = raw.decode("utf-8")

    if raw.startswith(b"\xef\xbb\xbf"):
        problems.append("%s: starts with a UTF-8 BOM" % rel)
    if b"\r\n" not in raw:
        problems.append("%s: not CRLF (the client reads these on Windows)" % rel)

    folder = os.path.basename(os.path.dirname(toc))
    if os.path.splitext(os.path.basename(toc))[0] != folder:
        problems.append("%s: TOC name must match its folder (%s)" % (rel, folder))

    declared = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith("## SavedVariables"):
            _, _, rest = line.partition(":")
            # One space after the colon is the convention and the client handles it. What is worth
            # flagging is padding BETWEEN entries, where a parser that does not trim would end up
            # looking for a global named " LodestarHarvest".
            rest = rest.lstrip(" ")
            for i, part in enumerate(rest.split(",")):
                if i > 0 and part != part.lstrip(" "):
                    problems.append("%s: space after the comma before %r in ## SavedVariables" % (rel, part.strip()))
                if part != part.rstrip():
                    problems.append("%s: trailing space after %r in ## SavedVariables" % (rel, part.strip()))
                name = part.strip()
                if name:
                    declared.append(name)
                    if not re.match(r"^[A-Za-z_]\w*$", name):
                        problems.append("%s: %r is not a valid global name" % (rel, name))
                    if name.endswith("DB") and name not in ADOPTED:
                        problems.append(
                            "%s: %r ends in 'DB'. Lodestar moved off that suffix while chasing saved "
                            "variables that never came back; whether the name was ever the cause is "
                            "still open (see Lodestar/Core/Saved.lua), but the suite uses one "
                            "convention and this is it." % (rel, name))
        if line.startswith("## Version:") and "@" in line:
            problems.append("%s: unreplaced packager token in %r" % (rel, line.strip()))
        if line.startswith("## Interface:") and not re.search(r"\d", line):
            problems.append("%s: no interface number" % rel)

    # Every file the TOC lists must exist, or the client silently skips it.
    base = os.path.dirname(toc)
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        target = os.path.join(base, line.replace("\\", os.sep))
        if not os.path.exists(target):
            problems.append("%s: lists a file that does not exist: %s" % (rel, line))

seen = {}
for toc in sorted(glob.glob(os.path.join(ROOT, "*", "*.toc"))):
    text = open(toc, "rb").read().decode("utf-8")
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith("## SavedVariables"):
            for name in (p.strip() for p in line.partition(":")[2].split(",")):
                if name:
                    if name in seen:
                        problems.append("%s declared in two TOCs: %s and %s"
                                        % (name, seen[name], os.path.relpath(toc, ROOT)))
                    seen[name] = os.path.relpath(toc, ROOT)

if problems:
    print("toc check: %d problem(s)" % len(problems))
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("toc check: %d TOCs, %d saved variables, no problems" % (
    len(glob.glob(os.path.join(ROOT, "*", "*.toc"))), len(seen)))

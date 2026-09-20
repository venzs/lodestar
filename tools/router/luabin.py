"""Find a Lua interpreter that subprocess can actually start.

On this project's Windows setup `lua5.1` on PATH is a bash shim, not a program: bash runs it fine,
CreateProcess refuses it with WinError 193, and shutil.which() is no help either way. Two things had
quietly gone wrong because of that -- plan_sweep.py carried a hard-coded path to one developer's
LuaJIT, and test_router.py's "the emitted guide parses with the real Parser.lua" check printed
"(lua not found, skipping)" and passed without ever parsing anything.

A candidate is a shim if it starts with `#!`, which is also the only reliable test here: splitting
the extension off `lua5.1` yields ".1" and would call the shim a program.

Order: $LUA, then every PATH directory, following a shim's `exec` line to the real interpreter.
"""
from __future__ import annotations

import os
import re
from typing import Optional

NAMES = ("luajit", "lua5.1", "lua")


def _msys_to_windows(p: str) -> str:
    return p[1].upper() + ":" + p[2:] if re.match(r"^/[a-zA-Z]/", p) else p


def _resolve(path: str, depth: int = 0) -> Optional[str]:
    """The program this path names: itself, or whatever a `#!` shim execs (once)."""
    try:
        with open(path, "rb") as f:
            head = f.read(2048)
    except OSError:
        return None
    if not head.startswith(b"#!"):
        return path
    if depth:
        return None
    m = re.search(r'^\s*exec\s+"?([^"\n]+?)"?\s', head.decode("utf-8", "replace"), re.M)
    if not m:
        return None
    target = _msys_to_windows(m.group(1))
    return _resolve(target, depth + 1) if os.path.isfile(target) else None


def find_lua() -> Optional[str]:
    env = os.environ.get("LUA")
    if env and os.path.isfile(env):
        return _resolve(env)
    exts = [""] + [e for e in os.environ.get("PATHEXT", "").split(os.pathsep) if e]
    for d in os.environ.get("PATH", "").split(os.pathsep):
        for n in NAMES:
            for ext in exts:
                cand = os.path.join(d, n + ext)
                if os.path.isfile(cand):
                    got = _resolve(cand)
                    if got:
                        return got
    return None

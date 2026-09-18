"""Classic-era XP formulas. One file to retune once Forever's numbers are confirmed by the recorder.

Sources (see docs in the design notes):
  * Mob XP, ZD table, grey level:  Warcraft Wiki "Mob experience" (Classic section)
  * Quest XP scaling by level:      Warcraft Wiki / vanilla-wow-archive "Experience point"
  * XP to level:                    WoWWiki "Formulas:XP To Level"  (verified: 400, 900, 1400, ... 7600 for 1-10)

Forever unknowns are surfaced as XPConfig fields, all of which the recorder can validate:
  QUEST_TURNED_IN carries the actual xp reward (Recorder writes it as "-- ... N xp"),
  PLAYER_LEVEL_UP + UnitXPMax gives the XP-to-level curve, and kill XP deltas give mob XP.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class XPConfig:
    max_level: int = 60
    patch_2_3_reduction: bool = False     # RF(CL) < 1 for 11..59; Classic Era uses False
    rested_fraction: float = 0.0          # share of kill XP earned while rested (doubles it)
    elite_multiplier: float = 2.0
    kill_xp_scale: float = 1.0            # global fudge factor fitted from recordings
    quest_xp_scale: float = 1.0


CFG = XPConfig()


# --- mob XP ----------------------------------------------------------------------------------------

def zero_difference(char_level: int) -> int:
    """ZD: the level gap at which a lower-level mob stops giving XP."""
    cl = char_level
    if cl <= 7: return 5
    if cl <= 9: return 6
    if cl <= 11: return 7
    if cl <= 15: return 8
    if cl <= 19: return 9
    if cl <= 29: return 11
    if cl <= 39: return 12
    if cl <= 44: return 13
    if cl <= 49: return 14
    if cl <= 54: return 15
    if cl <= 59: return 16
    return 17


def grey_level(char_level: int) -> int:
    """Highest mob level that is grey (no XP) to a character of this level."""
    cl = char_level
    if cl <= 5: return 0
    if cl <= 39: return cl - cl // 10 - 5
    if cl <= 59: return cl - cl // 5 - 1
    return cl - 9


def mob_xp(char_level: int, mob_level: int, elite: bool = False, cfg: XPConfig = CFG) -> int:
    """XP for a solo kill (Azeroth base). Returns 0 for grey mobs."""
    base = char_level * 5 + 45
    if mob_level >= char_level:
        xp = base * (1 + 0.05 * (mob_level - char_level))
    else:
        if mob_level <= grey_level(char_level):
            return 0
        xp = base * (1 - (char_level - mob_level) / zero_difference(char_level))
    if elite:
        xp *= cfg.elite_multiplier
    xp *= cfg.kill_xp_scale
    xp *= 1 + cfg.rested_fraction  # rested doubles the rested share
    return int(round(xp))


def level_color(char_level: int, mob_level: int) -> str:
    """Difficulty colour as the client shows it (used for step labels and level checks)."""
    d = mob_level - char_level
    if d >= 5: return "red"
    if d >= 3: return "orange"
    if d >= -2: return "yellow"
    if mob_level > grey_level(char_level): return "green"
    return "grey"


# --- quest XP ----------------------------------------------------------------------------------------

def quest_xp_fraction(char_level: int, quest_level: int) -> float:
    d = char_level - quest_level
    if d <= 5: return 1.0
    if d == 6: return 0.8
    if d == 7: return 0.6
    if d == 8: return 0.4
    if d == 9: return 0.2
    return 0.1


def quest_xp(char_level: int, quest: "Quest", cfg: XPConfig = CFG) -> int:  # noqa: F821
    frac = quest_xp_fraction(char_level, quest.level)
    raw = quest.xp * frac * cfg.quest_xp_scale
    return int(round(raw / 5.0) * 5)


# --- XP to level -------------------------------------------------------------------------------------

def _diff(cl: int) -> int:
    if cl <= 28: return 0
    if cl == 29: return 1
    if cl == 30: return 3
    if cl == 31: return 6
    return 5 * (cl - 30)


def _rf(cl: int, cfg: XPConfig) -> float:
    if not cfg.patch_2_3_reduction or cl <= 10:
        return 1.0
    if cl <= 27:
        return 1 - (cl - 10) / 100
    return 0.82


def xp_to_level(cl: int, cfg: XPConfig = CFG) -> int:
    """XP needed to go from level cl to cl+1 (Classic formula, rounded to the nearest hundred)."""
    mxp = 45 + 5 * cl
    raw = (8 * cl + _diff(cl)) * mxp * _rf(cl, cfg)
    return int(round(raw / 100.0) * 100)


def total_xp_at(level: int, cfg: XPConfig = CFG) -> int:
    return sum(xp_to_level(l, cfg) for l in range(1, level))


def level_from_total(total: int, cfg: XPConfig = CFG) -> tuple[int, int]:
    """(level, xp into level) for a cumulative XP amount."""
    lvl = 1
    while lvl < cfg.max_level and total >= xp_to_level(lvl, cfg):
        total -= xp_to_level(lvl, cfg)
        lvl += 1
    return lvl, total

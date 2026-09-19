#!/usr/bin/env python3
"""Turn pasted `/lode export` strings into a scan JSON that merge_scan.py understands.

    tools/pfquest/import_paste.py paste1.txt paste2.txt ... > data/beta/scan-<date>.json
    tools/pfquest/import_paste.py --stdin < pasted.txt > data/beta/scan-<date>.json

A contributor types /lode export in game, copies the box, and pastes it into Discord. This is the
other end of that: no file hunting for them, no manual extraction here.

The string is `LODE<format>:<build>:<payload>`, where the payload is DEFLATE compressed and then
encoded with LibDeflate's EncodeForPrint -- a six-bit alphabet of a-z A-Z 0-9 ( ), chosen because
every character in it survives a chat window. Both halves are reimplemented here rather than shelled
out to Lua, so the importer has no runtime dependency on the addon.

Several pastes can be given at once, including the multi-part form the addon emits for a very large
session; parts carry their own header and may arrive in any order.
"""
import argparse
import json
import re
import sys
import zlib

FORMAT = 1
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
INDEX = {c: i for i, c in enumerate(ALPHABET)}
HEADER = re.compile(r"LODE(\d+):([^:]*):")


def decode_for_print(text: str) -> bytes:
    """LibDeflate's EncodeForPrint, in reverse.

    Six bits per character, little-endian within each group of four characters, which is the order
    LibDeflate writes them. A trailing group of 2 or 3 characters carries 1 or 2 bytes.
    """
    cleaned = [c for c in text if c in INDEX]
    out = bytearray()
    for i in range(0, len(cleaned), 4):
        group = cleaned[i:i + 4]
        bits = 0
        for j, c in enumerate(group):
            bits |= INDEX[c] << (6 * j)
        for j in range(len(group) - 1):
            out.append((bits >> (8 * j)) & 0xFF)
    return bytes(out)


def parse_one(text: str):
    """(build, rows) for one pasted string, or None when it is not one of ours."""
    m = HEADER.search(text)
    if not m:
        return None
    fmt, build = int(m.group(1)), m.group(2)
    if fmt != FORMAT:
        raise SystemExit("paste uses export format %d; this importer understands %d. "
                         "Ask the contributor which Lodestar version they are on." % (fmt, FORMAT))
    payload = text[m.end():]
    # Every alphabet character after the header, with everything else dropped. That includes the
    # addon's own multi-part separator and any chat decoration a contributor typed around the paste
    # -- "here you go!" contributes letters that are in the alphabet and so end up appended as extra
    # bytes. They are harmless because a DEFLATE stream carries its own end marker: the decompressor
    # stops there and never looks at what follows. That is load-bearing, not luck, which is why the
    # payload is not truncated at the first stray character instead -- Discord wraps long lines, and
    # cutting at the first newline would throw away most of a real paste.
    raw = decode_for_print(payload)
    try:
        body = zlib.decompressobj(-15).decompress(raw).decode("utf-8")   # raw DEFLATE, no wrapper
    except zlib.error as e:
        raise SystemExit("could not decompress the paste (%s). It may have been truncated -- a "
                         "chat client that cut it short is the usual cause." % e)
    return build, [r for r in body.split(";") if r]


# Every row kind the importer counts, in one place. They were written out twice -- once in add() and
# once in main() -- and adding `c` to only the first turned the very first export carrying an
# identity row into a KeyError, with every unit test still green. One tuple, both dicts.
ROW_KINDS = ("n", "o", "q", "f", "l", "c", "p")


def add(scan, build, rows, seen=None, part_log=None):
    npcs, objs, quests, taxi, levels = (scan.setdefault(k, {}) for k in
                                        ("npcs", "objects", "quests", "taxi", "levels"))
    counts = dict.fromkeys(ROW_KINDS, 0)
    for row in rows:
        kind, rest = row[0], row[1:]
        parts = rest.split(",")
        try:
            if kind in "nof" and len(parts) == 4:
                i, m, x, y = int(parts[0]), int(parts[1]), float(parts[2]), float(parts[3])
                # A coordinate outside the map is a corrupt row, not a discovery.
                if not (0 <= x <= 100 and 0 <= y <= 100):
                    continue
                target = {"n": npcs, "o": objs, "f": taxi}[kind]
                target[str(i)] = {"map": m, "x": x, "y": y, "exact": True}
            elif kind == "q" and len(parts) == 3:
                i, giver, ender = (int(p) for p in parts)
                q = quests.setdefault(str(i), {})
                if giver:
                    q["giver"] = giver
                if ender:
                    q["ender"] = ender
            elif kind == "l" and len(parts) == 2:
                levels[str(int(parts[0]))] = int(parts[1])
            elif kind == "c" and len(parts) >= 5:
                # Who recorded it, in the same shape the saved-variable exporter writes, so
                # merge_scan counts both kinds of contribution through one code path.
                who = scan.setdefault("meta", {}).setdefault("contributors", {})
                e = who.setdefault(parts[0], {"sessions": 0})
                e["race"], e["class"], e["faction"] = parts[1], parts[2], parts[3]
                e["level"] = int(parts[4])
                ts = int(parts[5]) if len(parts) > 5 and parts[5].lstrip("-").isdigit() else 0
                if ts > 0:
                    e["first"] = min(e.get("first") or ts, ts)
                    e["last"] = max(e.get("last") or ts, ts)
                # A split export carries the identity on every part so each part stands on its own,
                # which means the same session arrives two or three times. Folded back together by
                # the timestamp the exporter stamps once per export. Without a timestamp -- an older
                # build, or a row someone retyped -- there is nothing to fold on, so the parts count
                # separately rather than being guessed at.
                key = (parts[0], ts)
                if ts <= 0 or seen is None or key not in seen:
                    if seen is not None and ts > 0:
                        seen.add(key)
                    e["sessions"] = (e.get("sessions") or 0) + 1
            elif kind == "p" and len(parts) == 2:
                # "part i of n", so a missing piece is reported rather than silently merged.
                if part_log is not None:
                    part_log.add((int(parts[1]), int(parts[0])))
            else:
                continue
            counts[kind] += 1
        except ValueError:
            continue          # one malformed row must not cost the other nine hundred
    scan.setdefault("builds", [])
    if build and build not in scan["builds"]:
        scan["builds"].append(build)
    return counts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="files containing pasted export strings")
    ap.add_argument("--stdin", action="store_true", help="read the paste from standard input")
    args = ap.parse_args()

    texts = []
    if args.stdin or not args.files:
        texts.append(sys.stdin.read())
    for path in args.files:
        with open(path, encoding="utf-8", errors="replace") as fh:
            texts.append(fh.read())

    scan, total = {}, dict.fromkeys(ROW_KINDS, 0)
    # seen: (contributor, timestamp) already counted, so a split export is one session not three.
    # part_log: (total, index) markers, so "you sent 1 and 3 of 3" can be said out loud.
    seen, part_log = set(), set()
    found = 0
    for text in texts:
        # One file may hold several pastes -- a Discord channel copied wholesale, for instance.
        for chunk in re.split(r"(?=LODE\d+:)", text):
            parsed = parse_one(chunk)
            if not parsed:
                continue
            found += 1
            build, rows = parsed
            for k, v in add(scan, build, rows, seen, part_log).items():
                total[k] += v
    if not found:
        raise SystemExit("no Lodestar export found in the input. A paste starts with LODE1: -- if "
                         "the contributor sent a file instead, use sv_to_json.lua.")

    sys.stderr.write("import_paste: %d paste(s): %d NPCs, %d objects, %d quest links, %d flight points, %d level costs\n"
                     % (found, total["n"], total["o"], total["q"], total["f"], total["l"]))
    # A split export says how many pieces it has. Saying which are missing is the whole reason the
    # marker exists: the alternative is merging two thirds of somebody's evening without a word.
    for n_parts in sorted({n for n, _ in part_log}):
        have = {i for n, i in part_log if n == n_parts}
        missing = sorted(set(range(1, n_parts + 1)) - have)
        if missing:
            sys.stderr.write("import_paste: WARNING -- a %d-part export is missing part(s) %s. "
                             "Ask the contributor to send %s; each part stands on its own.\n"
                             % (n_parts, ", ".join(str(i) for i in missing),
                                "it" if len(missing) == 1 else "them"))
        else:
            sys.stderr.write("import_paste: all %d parts of a split export present\n" % n_parts)
    json.dump(scan, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

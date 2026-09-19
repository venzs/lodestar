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


def add(scan, build, rows):
    npcs, objs, quests, taxi, levels = (scan.setdefault(k, {}) for k in
                                        ("npcs", "objects", "quests", "taxi", "levels"))
    counts = dict.fromkeys(("n", "o", "q", "f", "l"), 0)
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

    scan, total = {}, dict.fromkeys(("n", "o", "q", "f", "l"), 0)
    found = 0
    for text in texts:
        # One file may hold several pastes -- a Discord channel copied wholesale, for instance.
        for chunk in re.split(r"(?=LODE\d+:)", text):
            parsed = parse_one(chunk)
            if not parsed:
                continue
            found += 1
            build, rows = parsed
            for k, v in add(scan, build, rows).items():
                total[k] += v
    if not found:
        raise SystemExit("no Lodestar export found in the input. A paste starts with LODE1: -- if "
                         "the contributor sent a file instead, use sv_to_json.lua.")

    sys.stderr.write("import_paste: %d paste(s): %d NPCs, %d objects, %d quest links, %d flight points, %d level costs\n"
                     % (found, total["n"], total["o"], total["q"], total["f"], total["l"]))
    json.dump(scan, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

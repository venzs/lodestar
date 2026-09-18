#!/usr/bin/env python3
"""Extract the WoW API surface that is actually available in a given game type
(default: camelot == WoW: Forever) from a Gethe/wow-ui-source export.

Outputs into <out dir>:
  api.json               namespaces, documented globals, events, enums, loaded files
  luacheck_globals.lua   Lua table of read_globals for .luacheckrc
  c_globals_inferred.txt globals referenced by loaded Blizzard Lua but defined nowhere in Lua/XML/docs
                         (i.e. undocumented C-side API — exists, but treat with mild suspicion)

Usage: extract_api.py <Interface dir> <out dir> [gametype=camelot]
"""
import json
import os
import re
import sys

iface_dir, out_dir = sys.argv[1], sys.argv[2]
GAMETYPE = sys.argv[3] if len(sys.argv) > 3 else "camelot"
FAMILY_OF = {"camelot": "mainline", "standard": "mainline", "plunderstorm": "mainline", "wowhack": "mainline",
             "vanilla": "classic", "tbc": "classic", "wrath": "classic", "cata": "classic", "mists": "classic"}
FAMILY = FAMILY_OF[GAMETYPE]
FAMILY_DIR = {"mainline": "Mainline", "classic": "Classic"}[FAMILY]
GAME_DIR = GAMETYPE.capitalize()  # camelot -> Camelot, vanilla -> Vanilla
os.makedirs(out_dir, exist_ok=True)
addons_dir = os.path.join(iface_dir, "AddOns")
doc_dir = os.path.join(addons_dir, "Blizzard_APIDocumentationGenerated")

# ---------------------------------------------------------------- TOC resolution
tag_re = re.compile(r"\[([A-Za-z]+)\s+([^\]]+)\]")

def gate_passes(tags):
    for k, v in tags:
        vals = {x.strip().lower() for x in v.split(",")}
        if k == "AllowLoadGameType" and not (GAMETYPE in vals or FAMILY in vals):
            return False
        if k == "ExcludeLoadGameType" and (GAMETYPE in vals or FAMILY in vals):
            return False
        if k == "AllowLoad" and vals & {"glue"} and not vals & {"both", "game"}:
            return False
    return True

loaded_files = []   # absolute paths of lua/xml that load under GAMETYPE
loaded_addons = []
skipped_addons = []
toc_list = open(os.path.join(iface_dir, "ui-toc-list.txt"), encoding="utf-8", errors="replace").read().split()
for rel in toc_list:
    rel = rel.replace("\\", "/")
    if rel.startswith("Interface/"):
        rel = rel[len("Interface/"):]
    toc_path = os.path.join(iface_dir, rel)
    if not os.path.exists(toc_path):
        continue
    addon_dir = os.path.dirname(toc_path)
    addon_name = os.path.basename(addon_dir)
    header_ok = True
    files = []
    for line in open(toc_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#"):
            m = re.match(r"^##\s*AllowLoadGameType:\s*(.+)$", line)
            if m:
                header_ok = header_ok and gate_passes([("AllowLoadGameType", m.group(1))])
            m = re.match(r"^##\s*AllowLoad:\s*(.+)$", line)
            if m and m.group(1).strip().lower() == "glue":
                header_ok = False
            continue
        tags = tag_re.findall(line)
        path = tag_re.sub("", line).strip()
        if not gate_passes(tags):
            continue
        path = path.replace("[Family]", FAMILY_DIR).replace("[Game]", GAME_DIR).replace("\\", "/")
        files.append(os.path.join(addon_dir, path))
    if not header_ok:
        skipped_addons.append(addon_name)
        continue
    loaded_addons.append(addon_name)
    loaded_files.extend(files)

# ---------------------------------------------------------------- API docs
namespaces, global_funcs, events, enums, constants = {}, set(), set(), {}, set()
sec_re = re.compile(r"^\t(Functions|Events|Tables)\s*=", re.M)
for fn in sorted(os.listdir(doc_dir)):
    if not fn.endswith(".lua"):
        continue
    src = open(os.path.join(doc_dir, fn), encoding="utf-8", errors="replace").read()
    ns_m = re.search(r'^\tNamespace = "([^"]+)"', src, re.M)
    ns = ns_m.group(1) if ns_m else None
    parts = list(sec_re.finditer(src))
    for i, m in enumerate(parts):
        sec = m.group(1)
        body = src[m.end(): parts[i + 1].start() if i + 1 < len(parts) else len(src)]
        if sec == "Functions":
            for f in re.finditer(r'^\t\t\{\s*\n\t\t\tName = "([A-Za-z0-9_]+)"', body, re.M):
                (namespaces.setdefault(ns, set()) if ns else global_funcs).add(f.group(1))
        elif sec == "Events":
            events.update(re.findall(r'LiteralName = "([A-Z0-9_]+)"', body))
        elif sec == "Tables":
            for t in re.finditer(r'^\t\t\{\s*\n\t\t\tName = "([A-Za-z0-9_]+)",\s*\n\t\t\tType = "(Enumeration|Constants|Structure|CallbackType)"', body, re.M):
                name, typ = t.group(1), t.group(2)
                if typ == "Enumeration":
                    tail = body[t.end():]
                    stop = tail.find("\n\t\t},")
                    block = tail[: stop if stop > 0 else len(tail)]
                    enums[name] = set(re.findall(r'\{ Name = "([A-Za-z0-9_]+)", Type = "' + name + '"', block))
                elif typ == "Constants":
                    constants.add(name)

# ---------------------------------------------------------------- UI-defined globals (only files that load)
ui_globals, referenced = set(), set()
func_re = re.compile(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*[\.:(]", re.M)
assign_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)", re.M)
ident_re = re.compile(r"(?<![\.:\w])([A-Za-z_][A-Za-z0-9_]*)\s*[\(\.\[]")
xml_name_re = re.compile(r'<[A-Za-z]+[^>]*?\sname="([A-Za-z_][A-Za-z0-9_]*)"')
xml_virtual_re = re.compile(r'virtual="true"')
missing_files = 0
for p in loaded_files:
    if not os.path.exists(p):
        missing_files += 1
        continue
    src = open(p, encoding="utf-8", errors="replace").read()
    if p.endswith(".lua"):
        ui_globals.update(func_re.findall(src))
        ui_globals.update(m for m in assign_re.findall(src) if m not in ("local", "return", "end", "if", "else"))
        referenced.update(ident_re.findall(src))
    elif p.endswith(".xml"):
        for tag in re.finditer(r"<[A-Za-z]+[^>]*>", src):
            t = tag.group(0)
            m = re.search(r'\sname="([A-Za-z_][A-Za-z0-9_]*)"', t)
            if m and "$parent" not in m.group(1) and 'virtual="true"' not in t:
                ui_globals.add(m.group(1))
            elif m and 'virtual="true"' in t:
                ui_globals.add(m.group(1))  # templates are referenced by name in CreateFrame; harmless to allow

lua_std = """_G getfenv setfenv loadstring loadstring_untainted pcall xpcall error assert select type tostring tonumber unpack pairs ipairs next
rawget rawset rawequal setmetatable getmetatable string table math bit coroutine os date time collectgarbage gcinfo newproxy
debugstack debuglocals print""".split()
lua_kw = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())

documented = set(namespaces) | global_funcs
defined = documented | ui_globals | set(lua_std)
c_inferred = sorted(g for g in referenced if g not in defined and g not in lua_kw and not g.startswith("_"))

read_globals = defined | {"Enum", "Constants", "LibStub"} | set(c_inferred)
read_globals = {g for g in read_globals if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", g) and g not in lua_kw}

json.dump({
    "gametype": GAMETYPE,
    "loaded_addons": loaded_addons, "skipped_addons": skipped_addons,
    "namespaces": {k: sorted(v) for k, v in sorted(namespaces.items())},
    "global_functions": sorted(global_funcs), "events": sorted(events),
    "enums": {k: sorted(v) for k, v in sorted(enums.items())}, "constants": sorted(constants),
    "ui_globals": sorted(ui_globals), "c_globals_inferred": c_inferred,
}, open(os.path.join(out_dir, "api.json"), "w"), indent=1)

with open(os.path.join(out_dir, "luacheck_globals.lua"), "w") as f:
    f.write(f"-- generated by extract_api.py for gametype={GAMETYPE}; do not edit\nreturn {{\n")
    for g in sorted(read_globals):
        f.write(f'  "{g}",\n')
    f.write("}\n")
open(os.path.join(out_dir, "c_globals_inferred.txt"), "w").write("\n".join(c_inferred) + "\n")

print(f"gametype={GAMETYPE} addons loaded={len(loaded_addons)} skipped={len(skipped_addons)} files={len(loaded_files)} missing={missing_files}")
print(f"namespaces={len(namespaces)} doc_globals={len(global_funcs)} events={len(events)} enums={len(enums)} ui_globals={len(ui_globals)} c_inferred={len(c_inferred)} read_globals={len(read_globals)}")

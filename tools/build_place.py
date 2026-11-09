#!/usr/bin/env python3
"""Builds MonsterLockdown.rbxlx (an XML Roblox place) from src/ without needing Rojo.

Usage: python3 tools/build_place.py
"""
import itertools
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
_ref = itertools.count(1)


def item(cls, name, children=(), source=None, extra=""):
    props = f'<string name="Name">{name}</string>' + extra
    if source is not None:
        props += f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>'
    inner = "".join(children)
    return f'<Item class="{cls}" referent="RBX{next(_ref)}"><Properties>{props}</Properties>{inner}</Item>'


def script_item(path):
    name = path.name
    source = path.read_text(encoding="utf-8")
    if name.endswith(".server.lua"):
        return item("Script", name[: -len(".server.lua")], source=source)
    if name.endswith(".client.lua"):
        return item("LocalScript", name[: -len(".client.lua")], source=source)
    return item("ModuleScript", path.stem, source=source)


def folder(path, name):
    children = []
    for child in sorted(path.iterdir()):
        if child.is_dir():
            children.append(folder(child, child.name))
        elif child.suffix == ".lua":
            children.append(script_item(child))
    return item("Folder", name, children)


# Future lighting (realistic shadows from every light) can only be set in the place file,
# not from scripts. Technology enum: 0 Legacy, 1 Voxel, 2 Compatibility, 3 ShadowMap, 4 Future.
LIGHTING = '<token name="Technology">4</token><bool name="GlobalShadows">true</bool>'

place = "".join([
    item("Lighting", "Lighting", extra=LIGHTING),
    item("ReplicatedStorage", "ReplicatedStorage", [folder(ROOT / "src/shared", "Shared")]),
    item("ServerScriptService", "ServerScriptService", [folder(ROOT / "src/server", "Server")]),
    item("StarterPlayer", "StarterPlayer", extra='<bool name="EnableMouseLockOption">false</bool>', children=[
        item("StarterPlayerScripts", "StarterPlayerScripts", [folder(ROOT / "src/client", "Client")]),
    ]),
])
out = ROOT / "MonsterLockdown.rbxlx"
out.write_text(f'<roblox version="4">{place}</roblox>', encoding="utf-8")
print(f"Wrote {out}")

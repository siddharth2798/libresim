"""Blender (5.x) headless: A320 exterior (FlightGear A320-family AC3D, GPL-2.0-only) -> game/aircraft/a320/models/exterior.glb

Usage (repo root):
  tools/24_a320_models_fetch.sh && tools/.venv/bin/python -I tools/24_a320_textures.py
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/blender/convert_a320.py

What it does (all listed in third_party/a320-family/SOURCE.md, change log): imports Models/Fuselage/res/A320-216.ac
and CFM56.ac with our own AC3D reader (tools/blender/ac3d_parse.py; no Blender AC3D importer exists for 5.x),
drops FlightGear-only / hidden meshes (door and cargo interiors, actuators, placards, nav-light glass, the
WingtipFence variant, blur fans), rebuilds materials as Principled BSDF from the cleaned textures
(tools/24_a320_textures.py: no airline livery, no registration, no logos), adds the `pivot_<name>` empties of
tools/blender/a320_hinges.py, merges the static parts into one mesh and exports Y-up glTF.
Frame: FlightGear model frame == JSBSim structural frame for this model, so the glb origin is the structural
origin and aircraft.json model.origin_m is [0, 0, 0] (the config's vrp_m z = -0.83109 is FlightGear's model
offset, already absorbed).
"""
import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_hinges as H  # noqa: E402
import a320_scene as S  # noqa: E402

RAW = S.ROOT / "data/raw/fg/a320/Models/Fuselage/res"
OUT = S.ROOT / "game/aircraft/a320/models"


def main():
    S.reset()
    objs = S.import_ac(RAW / "A320-216.ac", H.keep_exterior, wheel_names=H.WHEELS)
    objs.update(S.import_ac(RAW / "CFM56.ac", H.keep_exterior))
    print("imported", len(objs), "objects")
    pivots = {}
    table = {}
    for name, h in {**H.HINGES, **H.ENGINE_HINGES}.items():
        found = [objs[n] for n in h["objs"] if n in objs]
        if len(found) != len(h["objs"]):
            print("WARN", name, "missing", [n for n in h["objs"] if n not in objs])
        pivots[name] = S.add_pivot(name, found, h["p1"], h["p2"], pivots.get(h.get("parent")))
        table[name] = {k: h[k] for k in ("drive", "sign", "p1", "p2") if k in h}
        table[name].update({k: h[k] for k in ("map", "parent") if k in h})
    body = S.join_static(list(bpy.data.objects), "body")
    S.smooth_by_angle(40.0)
    tris = S.triangles()
    mats = sorted({m.name for m in bpy.data.materials if m.users})
    ex = S.bbox([body])
    wheel_z = min(S.bbox([objs[n] for n in H.WHEELS if n in objs])[2][0] for _ in (0,))
    print("TRIANGLES", tris, "MATERIALS", len(mats), mats)
    print("BBOX body x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (*ex[0], *ex[1], *ex[2]), "wheel bottom z %.3f" % wheel_z)
    OUT.mkdir(parents=True, exist_ok=True)
    S.export_glb(OUT / "exterior.glb")
    (OUT / "exterior_pivots.json").write_text(json.dumps(table, indent=1))
    print("EXPORTED", OUT / "exterior.glb", (OUT / "exterior.glb").stat().st_size // 1024, "KB")


main()
